"""Display live YOLO fish detections and ByteTrack IDs from a webcam or stream.

Examples (run from the repository root):
    python byteTrack.py --source 1
    python byteTrack.py --source 0 --imgsz 960 --conf 0.20
    python byteTrack.py --source rtsp://camera-host/stream
    python byteTrack.py --source 1 --preview-only --backend msmf

For an iPhone, start its webcam bridge and Windows client before running this.
"""

import argparse
import sys
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
    parser.add_argument("--conf", type=float, default=0.25, help="Detection confidence")
    parser.add_argument("--imgsz", type=int, default=640, help="YOLO inference image size")
    parser.add_argument("--device", default=None, help="Inference device: cpu, 0 (GPU), etc.")
    args = parser.parse_args()
    if not 0 < args.conf <= 1:
        parser.error("--conf must be greater than 0 and at most 1")
    if args.imgsz <= 0:
        parser.error("--imgsz must be positive")
    if not args.preview_only and not args.model.is_file():
        parser.error(f"Model file not found: {args.model}")
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

        cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
        print(f"Camera connected using {cap.getBackendName()}.")
        print("Press Q or Esc, or close the preview, to stop.")

        while True:
            started = perf_counter()
            success, frame = cap.read()
            if not success or frame is None:
                raise RuntimeError("Camera frame unavailable. Check the camera connection.")

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
            cv2.imshow(window_name, annotated)
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), ord("Q"), 27):
                break
            if cv2.getWindowProperty(window_name, cv2.WND_PROP_VISIBLE) < 1:
                break
    finally:
        if cap is not None:
            cap.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nTracking stopped.")
    except RuntimeError as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
