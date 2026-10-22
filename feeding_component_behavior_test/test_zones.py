import cv2
import argparse
from pathlib import Path

def visualize_zones(video_path, crop=None, feed_zone=None, output_path="zone_preview.mp4", show_live=False):
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")

    source_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    orig_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    orig_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    # Determine canvas dimensions after cropping
    if crop is not None:
        left, top, right, bottom = crop
        canvas_w = right - left
        canvas_h = bottom - top
    else:
        canvas_w = orig_w
        canvas_h = orig_h

    # Video writer setup
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output_path, fourcc, source_fps, (canvas_w, canvas_h))

    print(f"Processing preview: {video_path}")
    print(f"Canvas size: {canvas_w}x{canvas_h}")

    frame_count = 0
    while True:
        success, frame = cap.read()
        if not success:
            break

        frame_count += 1

        # 1. Apply Tank Crop
        if crop is not None:
            left, top, right, bottom = crop
            frame = frame[top:bottom, left:right].copy()

        h, w = frame.shape[:2]

        # 2. Draw Upper Zone Limit (Top 1/3)
        upper_y = int(h * (1 / 3))
        cv2.line(frame, (0, upper_y), (w, upper_y), (255, 165, 0), 2)  # Cyan/Blue line
        cv2.putText(
            frame, "Upper Zone Limit (Top 1/3)", (10, upper_y - 10),
            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 165, 0), 2
        )

        # 3. Draw Feeding Zone Box
        if feed_zone is not None:
            x_min, y_min, x_max, y_max = feed_zone
            
            # Convert normalized coordinates (0.0 - 1.0) to pixel coordinates
            px_xmin = int(x_min * w)
            px_ymin = int(y_min * h)
            px_xmax = int(x_max * w)
            px_ymax = int(y_max * h)

            # Semi-transparent overlay box
            overlay = frame.copy()
            cv2.rectangle(overlay, (px_xmin, px_ymin), (px_xmax, px_ymax), (0, 255, 0), -1)
            cv2.addWeighted(overlay, 0.25, frame, 0.75, 0, frame)

            # Border line and label
            cv2.rectangle(frame, (px_xmin, px_ymin), (px_xmax, px_ymax), (0, 255, 0), 2)
            cv2.putText(
                frame, "FEEDING ZONE", (px_xmin + 5, px_ymin + 25),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2
            )

        # 4. Write Frame & Optional Live Display
        out.write(frame)

        if show_live:
            cv2.imshow("Zone Test Preview (Press 'q' to quit)", frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break

    cap.release()
    out.release()
    cv2.destroyAllWindows()
    print(f"Done! Preview video saved to: {output_path}")

def main():
    parser = argparse.ArgumentParser(description="Test and visualize tank crop and feed zone boundaries.")
    parser.add_argument("--video", required=True, help="Path to sample video file")
    parser.add_argument("--crop", type=int, nargs=4, metavar=("LEFT", "TOP", "RIGHT", "BOTTOM"), help="Crop parameters in pixels")
    parser.add_argument("--feed-zone", type=float, nargs=4, metavar=("X_MIN", "Y_MIN", "X_MAX", "Y_MAX"), help="Feeding zone normalized coords (0.0 to 1.0)")
    parser.add_argument("--output", default="zone_preview.mp4", help="Output preview video path")
    parser.add_argument("--show", action="store_true", help="Display interactive window while rendering")

    args = parser.parse_args()

    visualize_zones(
        video_path=args.video,
        crop=args.crop,
        feed_zone=args.feed_zone,
        output_path=args.output,
        show_live=args.show
    )

if __name__ == "__main__":
    main()