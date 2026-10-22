"""Shared behavior-to-appetite contract for PRE (before feeding) windows."""

import math

import pandas as pd

from extract_behavior_features import PROCESS_FPS, SEGMENT_SECONDS, SegmentStats


FEATURE_COLUMNS = [
    "avg_speed_norm_per_sec",
    "upper_zone_pct",
    "mean_group_distance_norm",
    "direction_change_fraction",
]
MODEL_FORMAT = "aquasense-pre-window-v1"
MIN_TRACKING_COVERAGE = 50.0


def feature_frame(rows):
    """Keep inference columns and missing values identical to training."""
    return pd.DataFrame(rows).reindex(columns=FEATURE_COLUMNS).apply(
        pd.to_numeric, errors="coerce"
    ).replace([float("inf"), float("-inf")], float("nan"))


def has_track_data(features):
    coverage = features.get("tracking_coverage_pct")
    speed = features.get("avg_speed_norm_per_sec")
    return (
        coverage is not None and math.isfinite(coverage)
        and coverage >= MIN_TRACKING_COVERAGE
        and features.get("valid_speed_steps", 0) > 0
        and speed is not None and math.isfinite(speed)
    )


def detections_from_result(result, width, height):
    """Convert YOLO boxes/IDs to the normalized coordinates SegmentStats uses."""
    if result.boxes is None:
        return []
    boxes = result.boxes.xyxy.cpu().numpy()
    ids = (
        result.boxes.id.int().cpu().tolist()
        if result.boxes.id is not None else [None] * len(boxes)
    )
    return [
        {"id": fish_id, "x": float((x1 + x2) / (2 * width)),
         "y": float((y1 + y2) / (2 * height))}
        for (x1, y1, x2, y2), fish_id in zip(boxes, ids)
    ]


class AppetitePredictor:
    def __init__(self, model_path):
        import joblib

        bundle = joblib.load(model_path)
        if (
            not isinstance(bundle, dict)
            or bundle.get("format") != MODEL_FORMAT
            or bundle.get("feature_columns") != FEATURE_COLUMNS
            or bundle.get("segment_seconds") != SEGMENT_SECONDS
            or bundle.get("process_fps") != PROCESS_FPS
        ):
            raise ValueError("Incompatible RF model. Export it using train_live_rf.py.")
        self.model = bundle["model"]
        if set(self.model.classes_) != {"HIGH", "LOW"}:
            raise ValueError("The RF model must predict both HIGH and LOW appetite.")

    def predict(self, features):
        probabilities = self.model.predict_proba(feature_frame([features]))[0]
        index = int(probabilities.argmax())
        return str(self.model.classes_[index]), float(probabilities[index])


class LiveBehaviorMonitor:
    """Accumulate disjoint windows without retaining unbounded tracking history."""

    def __init__(self, session_id, predictor=None, feeding_zone=None):
        self.session_id = session_id
        self.predictor = predictor
        self.feeding_zone = feeding_zone
        self.origin = None
        self.segment_number = None
        self.stats = None
        self.status = "Collecting PRE behavior..."

    def update(self, timestamp, detections):
        if self.origin is None:
            self.origin = timestamp
        elapsed = timestamp - self.origin
        segment_number = int(elapsed // SEGMENT_SECONDS)
        completed = None
        if self.segment_number != segment_number:
            if self.stats is not None:
                completed = self.stats.get_features()
                completed["sampled_frames"] = self.stats.frame_count
                enough_samples = self.stats.frame_count >= (
                    PROCESS_FPS * SEGMENT_SECONDS * 0.5
                )
                # A long capture stall must not publish an old partial window.
                usable = (
                    segment_number == self.segment_number + 1
                    and enough_samples and has_track_data(completed)
                )
                completed["prediction_status"] = (
                    "FEATURES_ONLY" if usable else "INSUFFICIENT_DATA"
                )
                completed["predicted_appetite"] = ""
                completed["prediction_confidence"] = ""
                if usable and self.predictor is not None:
                    label, confidence = self.predictor.predict(completed)
                    completed.update(
                        prediction_status="PREDICTED", predicted_appetite=label,
                        prediction_confidence=confidence,
                    )
                    self.status = f"PRE appetite: {label} ({confidence:.0%}) - last 10s"
                elif usable:
                    self.status = "Behavior extracted - no RF model loaded"
                else:
                    self.status = "Appetite unavailable - insufficient tracking/samples"
            self.segment_number = segment_number
            self.stats = SegmentStats(
                self.session_id, "PRE", segment_number, self.feeding_zone
            )
        self.stats.update(elapsed, detections)
        return completed
