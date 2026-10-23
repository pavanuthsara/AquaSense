"""Export YOLO + ByteTrack predictions and evaluate against annotated fish tracks.

Ground truth must contain stable fish IDs, not YOLO image-detection labels.
MOT rows: frame,id,left,top,width,height,confidence,-1,-1,-1 (no header).
Frame numbers and exported box origins follow the 1-based MOT convention.
"""

import argparse
import csv
import hashlib
import importlib.metadata
import json
import math
from datetime import datetime, timezone
from pathlib import Path
from time import perf_counter

import numpy as np
import pandas as pd


COLUMNS = ["frame", "id", "left", "top", "width", "height", "confidence"]
METRICS = ["idf1", "idp", "idr", "mota", "motp", "precision", "recall",
           "num_switches", "num_false_positives", "num_misses", "num_fragmentations",
           "num_objects", "num_predictions", "num_unique_objects", "mostly_tracked",
           "partially_tracked", "mostly_lost", "num_frames"]


def load_mot(path, ground_truth=False):
    records = []
    with Path(path).open(encoding="utf-8-sig", newline="") as source:
        for number, row in enumerate(csv.reader(source), 1):
            if not row or not any(item.strip() for item in row) or row[0].lstrip().startswith("#"):
                continue
            if len(row) < 7:
                raise ValueError(f"{path}:{number}: need MOT tracking rows with at least 7 columns, not YOLO labels.")
            try:
                values = [float(value) for value in row[:7]]
            except ValueError as error:
                raise ValueError(f"{path}:{number}: MOT rows must be numeric, without a header.") from error
            frame, identity, _, _, width, height, confidence = values
            if not all(math.isfinite(value) for value in values):
                raise ValueError(f"{path}:{number}: non-finite value")
            if frame < 1 or not frame.is_integer() or identity < 0 or not identity.is_integer():
                raise ValueError(f"{path}:{number}: need frame >= 1 and a nonnegative integer fish ID")
            if width <= 0 or height <= 0:
                raise ValueError(f"{path}:{number}: boxes must have positive width and height")
            if ground_truth and confidence <= 0:
                raise ValueError("Ignored GT boxes/regions are unsupported. Use a fully annotated single-class guppy clip with GT flags = 1.")
            records.append([int(frame), int(identity)] + values[2:])
    table = pd.DataFrame(records, columns=COLUMNS)
    if table.duplicated(["frame", "id"]).any():
        raise ValueError(f"{path}: a fish ID appears more than once in the same frame")
    return table.sort_values(["frame", "id"]).reset_index(drop=True)


def load_frames(path):
    frames = []
    with Path(path).open(encoding="utf-8-sig", newline="") as source:
        for row in csv.reader(source):
            if not row or row[0].strip().lower() == "frame":
                continue
            value = float(row[0])
            if not math.isfinite(value) or value < 1 or not value.is_integer():
                raise ValueError("Evaluation frames must be positive integers")
            frames.append(int(value))
    if not frames or len(frames) != len(set(frames)):
        raise ValueError("Evaluation frame list must be nonempty and have no duplicates")
    return sorted(frames)


def iou_distances(gt_boxes, predicted_boxes, threshold):
    """IoU gating without removed NumPy APIs used in older motmetrics helpers."""
    a = np.asarray(gt_boxes, dtype=float).reshape(-1, 4)
    b = np.asarray(predicted_boxes, dtype=float).reshape(-1, 4)
    if not len(a) or not len(b):
        return np.empty((len(a), len(b)), dtype=float)
    top_left = np.maximum(a[:, None, :2], b[None, :, :2])
    bottom_right = np.minimum(a[:, None, :2] + a[:, None, 2:], b[None, :, :2] + b[None, :, 2:])
    intersection = np.maximum(bottom_right - top_left, 0).prod(axis=2)
    union = a[:, 2:].prod(axis=1)[:, None] + b[:, 2:].prod(axis=1)[None, :] - intersection
    iou = np.divide(intersection, union, out=np.zeros_like(intersection), where=union > 0)
    return np.where(iou >= threshold, 1 - iou, np.nan)


def evaluate_tracks(gt, predictions, frames, threshold=0.5):
    import motmetrics as mm

    if not frames or frames != sorted(set(frames)):
        raise ValueError("Frames must be sorted, unique, and nonempty")
    if not gt["frame"].isin(frames).any():
        raise ValueError("No ground-truth fish occur in the scored frames; check frame numbering and annotation range.")
    acc = mm.MOTAccumulator(auto_id=False)
    box_cols = ["left", "top", "width", "height"]
    gt_frames = {int(frame): group for frame, group in gt.groupby("frame")}
    pred_frames = {int(frame): group for frame, group in predictions.groupby("frame")}
    empty = pd.DataFrame(columns=COLUMNS)
    counts = []
    for frame in frames:
        actual, predicted = gt_frames.get(frame, empty), pred_frames.get(frame, empty)
        acc.update(actual["id"].astype(int).tolist(), predicted["id"].astype(int).tolist(),
                   iou_distances(actual[box_cols], predicted[box_cols], threshold), frameid=frame)
        counts.append({"frame": frame, "ground_truth_fish": len(actual), "predicted_tracks": len(predicted)})
    summary = mm.metrics.create().compute(acc, metrics=METRICS, name="guppy_test")
    metrics = {}
    for key, value in summary.loc["guppy_test"].items():
        metrics[key] = float(value) if math.isfinite(float(value)) else None
    metrics["mean_matched_iou"] = None if metrics["motp"] is None else 1 - metrics["motp"]
    # MOTP is distance in motmetrics; retain both fields to prevent mislabeling.
    return metrics, acc.mot_events.reset_index(), pd.DataFrame(counts)


def export_video(args, output):
    import cv2
    from ultralytics import YOLO

    if not args.video.is_file() or not args.model.is_file():
        raise ValueError("Video/model not found. Supply a recorded test clip and your trained guppy detector.")
    model = YOLO(str(args.model))
    cap = cv2.VideoCapture(str(args.video))
    writer = None
    tracked_rows, frames, raw_detections, untracked_detections = [], [], 0, 0
    inference_seconds = 0.0
    try:
        if not cap.isOpened():
            raise ValueError(f"Cannot open video: {args.video}")
        source_fps = float(cap.get(cv2.CAP_PROP_FPS))
        if not math.isfinite(source_fps) or source_fps <= 0:
            raise ValueError("Video has no valid source FPS")
        interval = 1 if args.process_fps == 0 else max(1, round(source_fps / args.process_fps))
        index = 0
        while True:
            if args.max_frames is not None and index >= args.max_frames:
                break
            success, original = cap.read()
            if not success:
                break
            index += 1
            if (index - 1) % interval:
                continue
            frames.append(index)
            left = top = 0
            frame = original
            if args.crop:
                left, top, right, bottom = args.crop
                if right > original.shape[1] or bottom > original.shape[0]:
                    raise ValueError("Crop exceeds original video dimensions")
                frame = original[top:bottom, left:right]
            started = perf_counter()
            result = model.track(frame, persist=True, tracker="bytetrack.yaml", conf=args.conf,
                                 imgsz=args.imgsz, device=args.device, classes=[0], verbose=False)[0]
            inference_seconds += perf_counter() - started
            boxes = result.boxes
            if boxes is not None:
                raw_detections += len(boxes)
                if boxes.id is None:
                    untracked_detections += len(boxes)
                else:
                    for box, identity, confidence in zip(boxes.xyxy.cpu().numpy(), boxes.id.int().cpu().tolist(), boxes.conf.cpu().tolist()):
                        x1, y1, x2, y2 = box
                        # Evaluate against original-video GT even when detection uses a crop.
                        tracked_rows.append([index, identity, float(x1 + left + 1), float(y1 + top + 1),
                                             float(x2 - x1), float(y2 - y1), float(confidence), -1, -1, -1])
            if args.save_video:
                annotated = result.plot()
                if writer is None:
                    writer = cv2.VideoWriter(str(output / "tracked_preview.mp4"), cv2.VideoWriter_fourcc(*"mp4v"),
                                             source_fps / interval, (annotated.shape[1], annotated.shape[0]))
                    if not writer.isOpened():
                        raise ValueError("Cannot create preview video")
                writer.write(annotated)
        if not frames:
            raise ValueError("No video frames decoded")
    finally:
        cap.release()
        if writer is not None:
            writer.release()
    prediction_path = output / "predictions_mot.txt"
    with prediction_path.open("w", encoding="utf-8", newline="") as target:
        csv.writer(target).writerows(tracked_rows)
    pd.DataFrame({"frame": frames}).to_csv(output / "evaluated_frames.csv", index=False)
    metadata = {
        "video": str(args.video.resolve()), "video_sha256": file_hash(args.video),
        "model": str(args.model.resolve()), "model_sha256": file_hash(args.model),
        "source_fps": source_fps, "frame_stride": interval, "nominal_processed_fps": source_fps / interval,
        "decoded_frames": index, "processed_frames": len(frames), "returned_detections": raw_detections,
        "detections_without_track_id": untracked_detections, "tracker": "bytetrack.yaml",
        "conf": args.conf, "imgsz": args.imgsz, "crop": args.crop,
        "inference_fps": len(frames) / inference_seconds if inference_seconds > 0 else None,
        "speed_note": "Includes model.track calls only; excludes video decode, drawing and export; first-call warmup included.",
        "ultralytics_version": importlib.metadata.version("ultralytics"),
        "box_coordinates": "Original video coordinates; left/top shifted +1 to 1-based MOT convention",
    }
    return prediction_path, frames, metadata


def file_hash(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def save_plot(output, metrics, counts):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(1, 3, figsize=(14, 4.5))
    rate_names = ["idf1", "precision", "recall", "mota"]
    axes[0].bar(["IDF1", "Precision", "Recall", "MOTA"], [100 * metrics[k] if metrics[k] is not None else np.nan for k in rate_names])
    for index, name in enumerate(rate_names):
        if metrics[name] is None:
            axes[0].text(index, 0, "N/A", ha="center", va="bottom")
    axes[0].set_ylabel("Percent (MOTA can be negative)")
    axes[1].bar(["ID switches", "False positives", "Misses"], [metrics[k] for k in ("num_switches", "num_false_positives", "num_misses")])
    axes[1].set_ylabel("Count")
    axes[2].plot(counts["frame"], counts["ground_truth_fish"], label="Ground truth")
    axes[2].plot(counts["frame"], counts["predicted_tracks"], label="Tracked fish", alpha=0.8)
    axes[2].set_xlabel("Original video frame")
    axes[2].set_ylabel("Visible fish")
    axes[2].legend()
    fig.tight_layout()
    fig.savefig(output / "tracking_metrics.png", dpi=180)
    plt.close(fig)


def main():
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--video", type=Path, help="Recorded test video; produces predictions and a frame manifest")
    source.add_argument("--predictions", type=Path, help="Existing MOT-format tracker predictions")
    parser.add_argument("--gt", type=Path, help="Manually verified MOT-format GT; omit for export only (no accuracy scores)")
    frame_scope = parser.add_mutually_exclusive_group()
    frame_scope.add_argument("--frames", type=Path, help="CSV of fully annotated original frame numbers, headed 'frame'")
    frame_scope.add_argument("--num-frames", type=int, help="Score all frames 1..N, including empty frames")
    parser.add_argument("--model", type=Path, default=root / "runs/guppy_detector_v3/weights/best.pt")
    parser.add_argument("--process-fps", type=float, default=5, help="Video processing rate; 5 matches the live behavior pipeline, 0 means native FPS")
    parser.add_argument("--max-frames", type=int, help="Export only the first N original frames, for a short annotated clip or smoke test")
    parser.add_argument("--conf", type=float, default=0.20)
    parser.add_argument("--imgsz", type=int, default=960)
    parser.add_argument("--device", default=None)
    parser.add_argument("--crop", type=int, nargs=4, metavar=("LEFT", "TOP", "RIGHT", "BOTTOM"))
    parser.add_argument("--iou-threshold", type=float, default=0.5)
    parser.add_argument("--save-video", action="store_true")
    parser.add_argument("--output", type=Path, help="New/empty output directory")
    args = parser.parse_args()
    if not (0 < args.conf <= 1 and 0 < args.iou_threshold <= 1) or args.imgsz <= 0 or args.process_fps < 0 or not math.isfinite(args.process_fps):
        parser.error("Confidence/IoU must be within (0,1], image size positive, and FPS finite and nonnegative")
    if args.num_frames is not None and args.num_frames < 1:
        parser.error("--num-frames must be positive")
    if args.max_frames is not None and args.max_frames < 1:
        parser.error("--max-frames must be positive")
    if args.predictions and not (args.frames or args.num_frames):
        parser.error("Existing predictions require --frames or --num-frames, so empty/unannotated frames are handled explicitly")
    if args.crop:
        left, top, right, bottom = args.crop
        if not (0 <= left < right and 0 <= top < bottom):
            parser.error("Invalid crop rectangle")
    try:
        if args.gt:
            # Validate annotation format/dependency before running expensive inference.
            import motmetrics  # noqa: F401
            gt = load_mot(args.gt, ground_truth=True)
        output = args.output or root / "output/evaluation/bytetrack" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
        if output.exists() and any(output.iterdir()):
            raise ValueError("Output directory is not empty. Choose another --output to preserve previous results.")
        output.mkdir(parents=True, exist_ok=True)
        metadata = {"created_at": datetime.now(timezone.utc).isoformat(), "iou_threshold": args.iou_threshold,
                    "scope": "Single-class guppy YOLO + ByteTrack evaluation; detection and association errors are both included."}
        if args.video:
            prediction_path, exported_frames, details = export_video(args, output)
            metadata.update(details)
        else:
            prediction_path = args.predictions
            exported_frames = None
        frames = load_frames(args.frames) if args.frames else list(range(1, args.num_frames + 1)) if args.num_frames else exported_frames
        if exported_frames is not None and not set(frames).issubset(exported_frames):
            raise ValueError("Requested scored frames were not processed. Match --frames to the processing stride, or use --process-fps 0.")
        predictions = load_mot(prediction_path)
        metadata.update(predictions=str(prediction_path.resolve()), predictions_sha256=file_hash(prediction_path),
                        scored_frame_count=len(frames), scored_frames=frames, numpy_version=np.__version__)
        pd.DataFrame({"frame": frames}).to_csv(output / "scored_frames.csv", index=False)
        if args.gt:
            metrics, events, counts = evaluate_tracks(gt, predictions, frames, args.iou_threshold)
            metadata.update(ground_truth=str(args.gt.resolve()), ground_truth_sha256=file_hash(args.gt),
                            motmetrics_version=importlib.metadata.version("motmetrics"),
                            gt_rows_outside_scored_frames=int((~gt["frame"].isin(frames)).sum()),
                            prediction_rows_outside_scored_frames=int((~predictions["frame"].isin(frames)).sum()))
            report = {"status": "EVALUATED", "metadata": metadata, "metrics": metrics}
            pd.DataFrame([metrics]).to_csv(output / "metrics.csv", index=False)
            events.to_csv(output / "tracking_events.csv", index=False)
            counts.to_csv(output / "per_frame_counts.csv", index=False)
            save_plot(output, metrics, counts)
            for name in ("idf1", "idp", "idr", "mota", "precision", "recall", "mean_matched_iou"):
                value = metrics[name]
                print(f"{name}: {'N/A' if value is None else f'{value:.4f}'}")
            print("ID switches:", int(metrics["num_switches"]))
        else:
            report = {"status": "NOT_EVALUATED_NO_GROUND_TRUTH", "metadata": metadata, "metrics": None}
            print("Predictions exported. ID accuracy was NOT evaluated: annotated fish IDs are required.")
        (output / "summary.json").write_text(json.dumps(report, indent=2, allow_nan=False), encoding="utf-8")
        (output / "methodology.md").write_text(
            "# Tracking evaluation method\n\n"
            "One recorded sequence is evaluated using stable, manually verified guppy identities "
            "and bounding boxes. Matching uses IoU >= the recorded threshold and the motmetrics "
            "CLEAR/Identity implementation. Tracker IDs are mapped to GT identities; their numeric "
            "values need not be equal. Only the declared frame manifest is scored, including fully "
            "annotated frames containing no fish. Never treat unannotated frames as empty GT. "
            "Annotations must use the same original-video frame numbers and 1-based bounding-box "
            "coordinates as predictions. All visible fish in scored frames must be annotated. "
            "Ignored regions and multiclass MOT benchmark preprocessing are unsupported.\n\n"
            "IDF1/IDP/IDR measure identity association; ID switches and fragmentations measure "
            "identity disruption. MOTA also penalizes false positives and misses and can be negative. "
            "Raw motmetrics MOTP is mean 1-IoU distance, so mean_matched_iou = 1-MOTP. All rates "
            "in JSON/CSV are fractions, not percentages. This is an end-to-end detector+tracker "
            "evaluation, not a standalone detector score or guaranteed fish population count.\n\n"
            "Reference: https://github.com/cheind/py-motmetrics\n", encoding="utf-8")
        print(f"Saved evaluation evidence: {output}")
    except ImportError as error:
        parser.error(f"Missing evaluation dependency ({error}). Install requirements-evaluation.txt in your research venv.")
    except (OSError, ValueError, KeyError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
