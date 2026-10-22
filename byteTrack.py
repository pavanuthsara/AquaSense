"""Display live YOLO fish detections and ByteTrack IDs from a webcam or stream.

Examples (run from the repository root):
    python byteTrack.py --source 1
    python byteTrack.py --source 0 --imgsz 960 --conf 0.20
    python byteTrack.py --source rtsp://camera-host/stream
    python byteTrack.py --source 1 --preview-only --backend msmf
    python byteTrack.py --source 1 --extract-behavior
    python byteTrack.py --source 1 --rf-model models/random_forest_live_pre.joblib

For an iPhone, start its webcam bridge and Windows client before running this.
"""

import argparse
import csv
import sys
from datetime import datetime, timezone
from pathlib import Path
from time import perf_counter


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source", default="0", help="Webcam index (0, 1, ...) or camera stream URL"
    )
    parser.add_argument(
        "--backend",
        choices=("auto", "dshow", "msmf"),
        default="dshow" if sys.platform == "win32" else "auto",
        help="Webcam capture backend; try msmf or auto if dshow shows green video",
    )
    parser.add_argument(
        "--preview-only", action="store_true", help="Show raw camera video without loading YOLO"
    )
    parser.add_argument(
        "--model",
        type=Path,
        default=Path(__file__).resolve().parent
        / "runs/guppy_detector_v3/weights/best.pt",
        help="Path to your trained fish detector",
    )
    parser.add_argument("--conf", type=float, default=None, help="Detection confidence (tracking: 0.25; behavior: 0.20)")
    parser.add_argument("--imgsz", type=int, default=None, help="YOLO image size (tracking: 640; behavior: 960)")
    parser.add_argument("--device", default=None, help="Inference device: cpu, 0 (GPU), etc.")
    parser.add_argument("--extract-behavior", action="store_true", help="Extract and log PRE behavior every 10 seconds")
    parser.add_argument("--rf-model", type=Path, help="PRE model exported by train_live_rf.py; also enables behavior extraction")
    parser.add_argument("--feature-output", type=Path, help="New CSV file for completed behavior windows")
    parser.add_argument("--crop", type=int, nargs=4, metavar=("LEFT", "TOP", "RIGHT", "BOTTOM"), help="Tank ROI in camera pixels; match your training setup")
    parser.add_argument("--feed-zone", type=float, nargs=4, metavar=("X_MIN", "Y_MIN", "X_MAX", "Y_MAX"), help="Optional feeding zone normalized within the cropped tank")
    args = parser.parse_args()
    args.behavior_enabled = args.extract_behavior or args.rf_model is not None
    if args.conf is None:
        args.conf = 0.20 if args.behavior_enabled else 0.25
    if args.imgsz is None:
        args.imgsz = 960 if args.behavior_enabled else 640
    if not 0 < args.conf <= 1:
        parser.error("--conf must be greater than 0 and at most 1")
    if args.imgsz <= 0:
        parser.error("--imgsz must be positive")
    if not args.preview_only and not args.model.is_file():
        parser.error(f"Model file not found: {args.model}")
    if args.rf_model is not None and not args.rf_model.is_file():
        parser.error(f"RF model not found: {args.rf_model}. Run train_live_rf.py first.")
    if args.preview_only and args.behavior_enabled:
        parser.error("Raw preview cannot extract behavior. Remove --preview-only.")
    if args.feature_output is not None and not args.behavior_enabled:
        parser.error("--feature-output requires --extract-behavior or --rf-model")
    if args.crop is not None:
        left, top, right, bottom = args.crop
        if not (0 <= left < right and 0 <= top < bottom):
            parser.error("--crop requires 0 <= LEFT < RIGHT and 0 <= TOP < BOTTOM")
    if args.feed_zone is not None:
        x_min, y_min, x_max, y_max = args.feed_zone
        if not (0 <= x_min < x_max <= 1 and 0 <= y_min < y_max <= 1):
            parser.error("--feed-zone must be a nonempty rectangle within 0..1")
    return args


def main():
    args = parse_args()

    import cv2

    source = int(args.source) if args.source.isdecimal() else args.source
    model = None
    if not args.preview_only:
        from ultralytics import YOLO

        model = YOLO(str(args.model))
    mode = "Raw camera preview" if args.preview_only else "Live fish tracking"
    window_name = f"AquaSense - {mode} (Q to quit)"
    cap = None
    feature_log = None
    feature_writer = None
    behavior = None
    next_sample = 0.0
    if args.behavior_enabled:
        from live_behavior import (
            AppetitePredictor, LiveBehaviorMonitor, PROCESS_FPS, detections_from_result,
        )

        predictor = AppetitePredictor(args.rf_model) if args.rf_model else None
        session_id = datetime.now(timezone.utc).strftime("LIVE_%Y%m%dT%H%M%S_%fZ")
        behavior = LiveBehaviorMonitor(session_id, predictor, args.feed_zone)
        if args.feature_output is None:
            args.feature_output = Path(__file__).resolve().parent / "output" / f"live_behavior_{session_id}.csv"

    try:
        backend = {
            "auto": cv2.CAP_ANY,
            "dshow": cv2.CAP_DSHOW,
            "msmf": cv2.CAP_MSMF,
        }[args.backend] if isinstance(source, int) else cv2.CAP_ANY
        cap = cv2.VideoCapture(source, backend)

        if not cap.isOpened():
            raise RuntimeError(
                "Cannot open camera. Start the iPhone webcam app and PC client, "
                "close other apps using the camera, then try another --source "
                "or --backend auto."
            )

        if behavior is not None:
            args.feature_output.parent.mkdir(parents=True, exist_ok=True)
            # Refuse to overwrite previous measurements accidentally.
            feature_log = args.feature_output.open("x", newline="", encoding="utf-8")
            print(f"Logging behavior to: {args.feature_output}")
            print("PRE mode: observe before adding food; stop this run when feeding starts.")

        cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
        print(f"Camera connected using {cap.getBackendName()}.")
        print("Press Q or Esc, or close the preview, to stop.")

        while True:
            started = perf_counter()
            success, frame = cap.read()
            if not success or frame is None:
                raise RuntimeError("Camera frame unavailable. Check the camera connection.")
            captured_at = perf_counter()
            if behavior is not None:
                # Keep draining the camera between samples to avoid a video backlog.
                if captured_at < next_sample:
                    continue
                next_sample = captured_at + 1.0 / PROCESS_FPS
            if args.crop is not None:
                left, top, right, bottom = args.crop
                if right > frame.shape[1] or bottom > frame.shape[0]:
                    raise RuntimeError("Crop exceeds camera frame size. Check --crop coordinates.")
                frame = frame[top:bottom, left:right]

            if args.preview_only:
                annotated = frame.copy()
                status = "Raw camera preview - YOLO disabled"
            else:
                result = model.track(
                    frame,
                    persist=True,
                    tracker="bytetrack.yaml",
                    conf=args.conf,
                    imgsz=args.imgsz,
                    device=args.device,
                    verbose=False,
                )[0]

                if behavior is not None:
                    completed = behavior.update(
                        captured_at,
                        detections_from_result(result, frame.shape[1], frame.shape[0]),
                    )
                    if completed is not None:
                        completed["observed_at_utc"] = datetime.now(timezone.utc).isoformat()
                        if feature_writer is None:
                            feature_writer = csv.DictWriter(feature_log, fieldnames=list(completed))
                            feature_writer.writeheader()
                        feature_writer.writerow(completed)
                        feature_log.flush()
                        print(behavior.status)
                        print({name: completed[name] for name in (
                            "avg_speed_norm_per_sec", "upper_zone_pct",
                            "mean_group_distance_norm", "direction_change_fraction",
                        )})

                # plot() draws boxes, class labels, confidence, and available track IDs.
                annotated = result.plot()
                detected = len(result.boxes) if result.boxes is not None else 0
                tracked = (
                    len(result.boxes.id)
                    if result.boxes is not None and result.boxes.id is not None
                    else 0
                )
                processing_fps = 1.0 / max(perf_counter() - started, 1e-6)
                status = (
                    f"Visible detections: {detected} | Tracked: {tracked} "
                    f"| FPS: {processing_fps:.1f}"
                )
            cv2.putText(
                annotated,
                status,
                (15, 30),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.65,
                (0, 255, 0),
                2,
            )
            if behavior is not None:
                cv2.putText(
                    annotated, behavior.status, (15, 60),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2,
                )
            cv2.imshow(window_name, annotated)
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), ord("Q"), 27):
                break
            if cv2.getWindowProperty(window_name, cv2.WND_PROP_VISIBLE) < 1:
                break
    finally:
        if feature_log is not None:
            feature_log.close()
        if cap is not None:
            cap.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nTracking stopped.")
    except (RuntimeError, ValueError, OSError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
