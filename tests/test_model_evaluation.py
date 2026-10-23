"""Known-answer checks for the research evaluators (no camera required)."""

import tempfile
import json
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
import pandas as pd
from sklearn.dummy import DummyClassifier

from evaluate_bytetrack import COLUMNS, evaluate_tracks, iou_distances, load_frames, load_mot
from evaluate_bytetrack import main as tracking_main
from evaluate_random_forest import (
    aggregate_sessions, classification_metrics, cross_validate, evaluate_saved_model, prepare_session_v3,
)
from live_behavior import FEATURE_COLUMNS, MODEL_FORMAT, feature_frame
from train_live_rf import build_pipeline, prepare_training_data


def tracks(rows):
    return pd.DataFrame(rows, columns=COLUMNS)


def mot_row(frame, identity=1, left=1):
    return [frame, identity, left, 1, 10, 10, 1]


class TrackingEvaluationTests(unittest.TestCase):
    def test_perfect_tracks_allow_different_numeric_id_names(self):
        gt = tracks([mot_row(i) for i in (1, 2, 3)])
        predictions = tracks([mot_row(i, 99) for i in (1, 2, 3)])
        metrics, _, _ = evaluate_tracks(gt, predictions, [1, 2, 3])
        self.assertAlmostEqual(metrics["idf1"], 1)
        self.assertAlmostEqual(metrics["mota"], 1)
        self.assertAlmostEqual(metrics["mean_matched_iou"], 1)
        self.assertEqual(metrics["num_switches"], 0)

    def test_identity_change_penalizes_idf1_and_counts_switch(self):
        gt = tracks([mot_row(i) for i in (1, 2, 3, 4)])
        predictions = tracks([mot_row(i, 10 if i <= 2 else 20) for i in (1, 2, 3, 4)])
        metrics, events, _ = evaluate_tracks(gt, predictions, [1, 2, 3, 4])
        self.assertAlmostEqual(metrics["idf1"], 0.5)
        self.assertAlmostEqual(metrics["mota"], 0.75)
        self.assertEqual(metrics["num_switches"], 1)
        self.assertIn("SWITCH", events["Type"].tolist())

    def test_empty_gt_frame_is_scored_for_false_positives(self):
        gt = tracks([mot_row(1), mot_row(3)])
        predictions = tracks([mot_row(i, 10) for i in (1, 2, 3)])
        metrics, _, counts = evaluate_tracks(gt, predictions, [1, 2, 3])
        self.assertEqual(metrics["num_frames"], 3)
        self.assertEqual(metrics["num_false_positives"], 1)
        self.assertAlmostEqual(metrics["precision"], 2 / 3)
        self.assertAlmostEqual(metrics["mota"], 0.5)
        self.assertEqual(counts.loc[1, "ground_truth_fish"], 0)

    def test_missing_middle_detection_counts_miss_and_fragmentation(self):
        gt = tracks([mot_row(i) for i in (1, 2, 3)])
        predictions = tracks([mot_row(1, 10), mot_row(3, 10)])
        metrics, _, _ = evaluate_tracks(gt, predictions, [1, 2, 3])
        self.assertEqual(metrics["num_misses"], 1)
        self.assertEqual(metrics["num_fragmentations"], 1)
        self.assertAlmostEqual(metrics["recall"], 2 / 3)

    def test_iou_gate_and_mota_can_be_negative(self):
        gt = tracks([mot_row(1)])
        predictions = tracks([mot_row(1, 10, left=100)])
        metrics, _, _ = evaluate_tracks(gt, predictions, [1])
        self.assertEqual(metrics["num_misses"], 1)
        self.assertEqual(metrics["num_false_positives"], 1)
        self.assertEqual(metrics["mota"], -1)
        self.assertEqual(metrics["idf1"], 0)
        self.assertIsNone(metrics["mean_matched_iou"])
        self.assertTrue(np.isnan(iou_distances([[0, 0, 10, 10]], [[100, 0, 10, 10]], 0.5)[0, 0]))

    def test_no_predictions_is_a_valid_failed_tracker_not_a_crash(self):
        metrics, _, _ = evaluate_tracks(tracks([mot_row(1)]), tracks([]), [1])
        self.assertEqual(metrics["num_misses"], 1)
        self.assertEqual(metrics["idf1"], 0)

    def test_yolo_labels_and_duplicate_ids_and_ignored_gt_are_rejected(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as folder:
            path = Path(folder) / "gt.txt"
            for content in ("0 0.5 0.5 0.1 0.1", "1,1,1,1,10,10,1\n1,1,2,2,10,10,1", "1,1,1,1,10,10,0"):
                path.write_text(content)
                with self.assertRaises(ValueError):
                    load_mot(path, ground_truth=True)
            path.write_text("frame\n1\n7\n13\n")
            self.assertEqual(load_frames(path), [1, 7, 13])

    def test_scoring_cli_saves_metrics_events_and_plot_with_no_predictions(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as folder:
            root = Path(folder)
            gt, predictions, output = root / "gt.txt", root / "pred.txt", root / "report"
            gt.write_text("1,1,1,1,10,10,1,-1,-1,-1\n")
            predictions.write_text("")
            with patch("sys.argv", ["evaluate_bytetrack.py", "--predictions", str(predictions),
                                    "--gt", str(gt), "--num-frames", "2", "--output", str(output)]), patch("builtins.print"):
                tracking_main()
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual(summary["status"], "EVALUATED")
            self.assertEqual(summary["metrics"]["num_misses"], 1)
            self.assertIsNone(summary["metrics"]["precision"])
            self.assertTrue((output / "tracking_metrics.png").is_file())
            self.assertTrue((output / "tracking_events.csv").is_file())


def feature_data():
    rows = []
    for session, label in (("a", "HIGH"), ("b", "HIGH"), ("c", "LOW"), ("d", "LOW")):
        for segment in range(2):
            row = {name: float(segment + 1) for name in FEATURE_COLUMNS}
            row.update(session_id=session, appetite_label=label, phase="PRE", start_sec=10 * segment,
                       end_sec=10 * (segment + 1), tracking_coverage_pct=100, valid_speed_steps=10)
            rows.append(row)
    return pd.DataFrame(rows)


class RandomForestEvaluationTests(unittest.TestCase):
    def test_every_prediction_is_from_a_disjoint_held_out_session(self):
        data = prepare_training_data(feature_data())
        predictions, splits, _ = cross_validate(data, feature_frame(data.to_dict("records")), build_pipeline())
        self.assertEqual(len(predictions), len(data))
        self.assertEqual(len(splits), 4)
        for split in splits:
            self.assertTrue(set(split["train_sessions"]).isdisjoint(split["test_sessions"]))
        self.assertEqual(set(predictions["session_id"]), {"a", "b", "c", "d"})

    def test_session_aggregation_uses_named_probabilities(self):
        rows = pd.DataFrame([
            {"session_id": "s", "true_label": "LOW", "p_HIGH": 0.1, "p_LOW": 0.9, "baseline_label": "HIGH", "fold": 1},
            {"session_id": "s", "true_label": "LOW", "p_HIGH": 0.4, "p_LOW": 0.6, "baseline_label": "HIGH", "fold": 1},
        ])
        result = aggregate_sessions(rows)
        self.assertEqual(result.iloc[0]["predicted_label"], "LOW")
        self.assertAlmostEqual(result.iloc[0]["p_LOW"], 0.75)
        self.assertEqual(classification_metrics(result)["accuracy"], 1)

    def test_saved_model_evaluation_refuses_training_sessions_and_unknown_provenance(self):
        data = prepare_training_data(feature_data())
        X = feature_frame(data.to_dict("records"))
        model = DummyClassifier(strategy="prior").fit(X, data["appetite_label"])
        bundle = {"format": MODEL_FORMAT, "feature_columns": FEATURE_COLUMNS, "model": model}
        with self.assertRaisesRegex(ValueError, "training session IDs"):
            evaluate_saved_model(bundle, data, X)
        bundle["training_session_ids"] = ["a"]
        with self.assertRaisesRegex(ValueError, "overlap"):
            evaluate_saved_model(bundle, data, X)
        bundle["training_session_ids"] = ["earlier-training-session"]
        predictions, _, _ = evaluate_saved_model(bundle, data, X)
        self.assertEqual(len(predictions), 8)

    def test_session_v3_refuses_missing_future_phases(self):
        data = feature_data().assign(feeding_zone_pct=10, latency_first_response_sec=1)
        with self.assertRaisesRegex(ValueError, "PRE, FEED, POST"):
            prepare_session_v3(data)

    def test_contradictory_labels_are_rejected(self):
        data = feature_data()
        data.loc[0, "appetite_label"] = "LOW"
        with self.assertRaisesRegex(ValueError, "exactly one"):
            prepare_training_data(data)


if __name__ == "__main__":
    unittest.main()
