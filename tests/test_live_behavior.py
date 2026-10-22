"""Behavior/prediction checks that do not require a camera or GUI."""

import math
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import joblib
import torch
from sklearn.dummy import DummyClassifier

from live_behavior import (
    AppetitePredictor, FEATURE_COLUMNS, LiveBehaviorMonitor, MODEL_FORMAT,
    PROCESS_FPS, SEGMENT_SECONDS, detections_from_result, feature_frame,
)


class LiveBehaviorTests(unittest.TestCase):
    def test_boxes_are_normalized_and_untracked_detections_are_retained(self):
        result = SimpleNamespace(boxes=SimpleNamespace(
            xyxy=torch.tensor([[20., 10., 60., 30.]]), id=torch.tensor([7.])
        ))
        detection = detections_from_result(result, 200, 100)[0]
        self.assertEqual(detection["id"], 7)
        self.assertAlmostEqual(detection["x"], 0.2)
        self.assertAlmostEqual(detection["y"], 0.2)
        result.boxes.id = None
        self.assertIsNone(detections_from_result(result, 200, 100)[0]["id"])

    def test_prediction_columns_have_fixed_order_and_missing_values(self):
        row = {name: i for i, name in enumerate(reversed(FEATURE_COLUMNS))}
        row["avg_speed_norm_per_sec"] = None
        row["appetite_label"] = "THIS IS NOT AN INPUT"
        frame = feature_frame([row])
        self.assertEqual(list(frame.columns), FEATURE_COLUMNS)
        self.assertTrue(math.isnan(frame.iloc[0]["avg_speed_norm_per_sec"]))
        self.assertEqual(frame.iloc[0]["direction_change_fraction"], 0)

    def test_completed_window_excludes_first_frame_of_next_window(self):
        monitor = LiveBehaviorMonitor("test")
        for i in range(50):
            self.assertIsNone(monitor.update(100 + i / 5, [
                {"id": 1, "x": 0.1 + i * 0.001, "y": 0.1}
            ]))
        completed = monitor.update(110, [{"id": 1, "x": 0.9, "y": 0.9}])
        self.assertEqual(completed["sampled_frames"], 50)
        self.assertEqual(completed["upper_zone_pct"], 100)
        self.assertAlmostEqual(completed["avg_speed_norm_per_sec"], 0.005 / math.sqrt(2))
        self.assertEqual(completed["prediction_status"], "FEATURES_ONLY")
        self.assertEqual(monitor.stats.frame_count, 1)
        self.assertEqual(monitor.stats.speeds, [])

    def test_no_fish_does_not_become_low_appetite(self):
        monitor = LiveBehaviorMonitor("test")
        for i in range(50):
            monitor.update(i / 5, [])
        completed = monitor.update(10, [])
        self.assertEqual(completed["prediction_status"], "INSUFFICIENT_DATA")
        self.assertEqual(completed["predicted_appetite"], "")

    def test_sparse_and_stalled_windows_are_not_predicted(self):
        for boundary in (10, 30):
            monitor = LiveBehaviorMonitor("test")
            monitor.update(0, [{"id": 1, "x": 0.1, "y": 0.1}])
            monitor.update(0.2, [{"id": 1, "x": 0.2, "y": 0.1}])
            completed = monitor.update(boundary, [])
            self.assertEqual(completed["prediction_status"], "INSUFFICIENT_DATA")

    def test_long_capture_stall_rejects_previously_full_window(self):
        monitor = LiveBehaviorMonitor("test")
        for i in range(50):
            monitor.update(i / 5, [{"id": 1, "x": 0.1 + i * 0.001, "y": 0.1}])
        self.assertEqual(monitor.update(30, [])["prediction_status"], "INSUFFICIENT_DATA")

    def test_saved_model_uses_its_class_mapping_and_window_predicts(self):
        rows = [{name: 1.0 for name in FEATURE_COLUMNS}] * 3
        model = DummyClassifier(strategy="prior").fit(feature_frame(rows), ["LOW", "HIGH", "HIGH"])
        bundle = {
            "format": MODEL_FORMAT, "model": model, "feature_columns": FEATURE_COLUMNS,
            "segment_seconds": SEGMENT_SECONDS, "process_fps": PROCESS_FPS,
        }
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as folder:
            path = Path(folder) / "test.joblib"
            joblib.dump(bundle, path)
            predictor = AppetitePredictor(path)
            label, confidence = predictor.predict(rows[0])
            self.assertEqual(label, "HIGH")
            self.assertAlmostEqual(confidence, 2 / 3)
            monitor = LiveBehaviorMonitor("test", predictor)
            for i in range(50):
                monitor.update(i / 5, [{"id": 1, "x": 0.1 + i * 0.001, "y": 0.1}])
            completed = monitor.update(10, [])
            self.assertEqual(completed["predicted_appetite"], "HIGH")
            self.assertEqual(completed["prediction_status"], "PREDICTED")
            self.assertAlmostEqual(completed["prediction_confidence"], 2 / 3)

    def test_session_model_is_rejected_instead_of_padding_future_features(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as folder:
            path = Path(folder) / "test.joblib"
            joblib.dump({"feature_columns": ["POST_avg_speed_norm_per_sec"]}, path)
            with self.assertRaisesRegex(ValueError, "train_live_rf"):
                AppetitePredictor(path)


if __name__ == "__main__":
    unittest.main()
