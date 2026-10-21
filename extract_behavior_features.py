
import cv2
import csv
import math
import argparse
from pathlib import Path
from itertools import combinations
from statistics import mean
from ultralytics import YOLO


# ==========================================
# CONFIGURATION
# ==========================================

SEGMENT_SECONDS = 30
PROCESS_FPS = 5
IMG_SIZE = 960
CONFIDENCE = 0.20

# Top third of the cropped tank
UPPER_ZONE_LIMIT = 1 / 3

# Direction change threshold
TURN_ANGLE = 45

# Ignore extremely small movements
MIN_MOVEMENT = 0.002

# Maximum allowed time between tracking points
MAX_TRACK_GAP = 0.6


# ==========================================
# SEGMENT STATISTICS
# ==========================================

class SegmentStats:

    def __init__(self, session_id, segment_number, feeding_zone=None):

        self.session_id = session_id
        self.segment_number = segment_number
        self.feeding_zone = feeding_zone

        self.frame_count = 0
        self.detected_fish_count = 0
        self.frames_with_tracks = 0

        self.upper_zone_count = 0
        self.feeding_zone_count = 0

        self.speeds = []
        self.group_distances = []

        self.direction_changes = 0
        self.valid_turns = 0

        # Track ID -> previous position/time/direction
        self.previous_positions = {}

    def update(self, timestamp, detections):

        self.frame_count += 1
        self.detected_fish_count += len(detections)

        if any(d["id"] is not None for d in detections):
            self.frames_with_tracks += 1

        current_points = []

        for fish in detections:

            x = fish["x"]
            y = fish["y"]
            fish_id = fish["id"]

            current_points.append((x, y))

            # ----------------------------------
            # UPPER ZONE OCCUPANCY
            # ----------------------------------

            if y < UPPER_ZONE_LIMIT:
                self.upper_zone_count += 1

            # ----------------------------------
            # FEEDING ZONE OCCUPANCY
            # ----------------------------------

            if self.feeding_zone is not None:

                x_min, y_min, x_max, y_max = self.feeding_zone

                if x_min <= x <= x_max and y_min <= y <= y_max:
                    self.feeding_zone_count += 1

            # Movement features require track IDs
            if fish_id is None:
                continue

            previous = self.previous_positions.get(fish_id)

            current_direction = None

            if previous is not None:

                old_x, old_y, old_time, old_direction = previous

                dt = timestamp - old_time

                # Ignore large tracking gaps
                if 0 < dt <= MAX_TRACK_GAP:

                    dx = x - old_x
                    dy = y - old_y

                    # Normalize by image diagonal
                    distance = math.hypot(dx, dy) / math.sqrt(2)

                    # --------------------------
                    # SWIMMING SPEED
                    # --------------------------

                    speed = distance / dt
                    self.speeds.append(speed)

                    # --------------------------
                    # DIRECTION CHANGES
                    # --------------------------

                    if distance >= MIN_MOVEMENT:

                        current_direction = (dx, dy)

                        if old_direction is not None:

                            old_dx, old_dy = old_direction

                            dot = old_dx * dx + old_dy * dy

                            mag1 = math.hypot(old_dx, old_dy)
                            mag2 = math.hypot(dx, dy)

                            if mag1 > 0 and mag2 > 0:

                                cosine = dot / (mag1 * mag2)
                                cosine = max(-1, min(1, cosine))

                                angle = math.degrees(math.acos(cosine))

                                self.valid_turns += 1

                                if angle >= TURN_ANGLE:
                                    self.direction_changes += 1

            self.previous_positions[fish_id] = (
                x,
                y,
                timestamp,
                current_direction
            )

        # --------------------------------------
        # GROUP SPACING
        # --------------------------------------

        if len(current_points) >= 2:

            distances = []

            for p1, p2 in combinations(current_points, 2):

                distance = math.hypot(
                    p1[0] - p2[0],
                    p1[1] - p2[1]
                ) / math.sqrt(2)

                distances.append(distance)

            self.group_distances.append(mean(distances))

    def get_features(self):

        total = self.detected_fish_count

        avg_speed = mean(self.speeds) if self.speeds else None

        upper_pct = (
            100 * self.upper_zone_count / total
            if total > 0 else None
        )

        feeding_pct = (
            100 * self.feeding_zone_count / total
            if total > 0 and self.feeding_zone is not None
            else None
        )

        group_spacing = (
            mean(self.group_distances)
            if self.group_distances else None
        )

        direction_fraction = (
            self.direction_changes / self.valid_turns
            if self.valid_turns > 0 else None
        )

        avg_visible_fish = (
            total / self.frame_count
            if self.frame_count > 0 else None
        )

        tracking_coverage = (
            100 * self.frames_with_tracks / self.frame_count
            if self.frame_count > 0 else None
        )

        return {
            "session_id": self.session_id,
            "segment_id": (
                f"{self.session_id}_PRE_"
                f"{self.segment_number + 1:02d}"
            ),
            "start_sec": self.segment_number * SEGMENT_SECONDS,
            "end_sec": (self.segment_number + 1) * SEGMENT_SECONDS,

            "avg_speed_norm_per_sec": avg_speed,
            "upper_zone_pct": upper_pct,
            "feeding_zone_pct": feeding_pct,
            "mean_group_distance_norm": group_spacing,
            "direction_change_fraction": direction_fraction,

            "mean_visible_fish": avg_visible_fish,
            "tracking_coverage_pct": tracking_coverage,
            "valid_speed_steps": len(self.speeds),
            "valid_turn_checks": self.valid_turns,

            # Do not invent an appetite label
            "appetite_label": ""
        }


# ==========================================
# PROCESS ONE PRE VIDEO
# ==========================================

def process_video(video_path, model_path, crop, feeding_zone):

    print(f"\nProcessing: {video_path.name}")

    # Fresh model resets tracker between videos
    model = YOLO(str(model_path))

    cap = cv2.VideoCapture(str(video_path))

    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")

    source_fps = cap.get(cv2.CAP_PROP_FPS)

    if source_fps <= 0:
        cap.release()
        raise RuntimeError("Could not read video FPS")

    frame_interval = max(1, round(source_fps / PROCESS_FPS))

    session_id = video_path.stem

    if session_id.upper().endswith("_PRE"):
        session_id = session_id[:-4]

    segments = {}

    frame_number = 0

    while True:

        success, frame = cap.read()

        if not success:
            break

        current_frame = frame_number
        frame_number += 1

        if current_frame % frame_interval != 0:
            continue

        timestamp = current_frame / source_fps

        # ----------------------------------
        # CROP TANK ROI
        # ----------------------------------

        if crop is not None:

            left, top, right, bottom = crop

            h, w = frame.shape[:2]

            if not (
                0 <= left < right <= w
                and 0 <= top < bottom <= h
            ):
                cap.release()
                raise ValueError("Invalid crop coordinates")

            frame = frame[top:bottom, left:right]

        height, width = frame.shape[:2]

        # ----------------------------------
        # YOLO + BYTETRACK
        # ----------------------------------

        results = model.track(
            frame,
            persist=True,
            tracker="bytetrack.yaml",
            conf=CONFIDENCE,
            imgsz=IMG_SIZE,
            verbose=False
        )

        result = results[0]

        detections = []

        if result.boxes is not None:

            boxes = result.boxes

            coords = boxes.xyxy.cpu().numpy()

            if boxes.id is not None:
                ids = boxes.id.int().cpu().tolist()
            else:
                ids = [None] * len(coords)

            for box, fish_id in zip(coords, ids):

                x1, y1, x2, y2 = box

                center_x = ((x1 + x2) / 2) / width
                center_y = ((y1 + y2) / 2) / height

                detections.append({
                    "id": fish_id,
                    "x": center_x,
                    "y": center_y
                })

        # ----------------------------------
        # SELECT 30-SECOND SEGMENT
        # ----------------------------------

        segment_number = int(timestamp // SEGMENT_SECONDS)

        if segment_number not in segments:

            segments[segment_number] = SegmentStats(
                session_id,
                segment_number,
                feeding_zone
            )

        segments[segment_number].update(
            timestamp,
            detections
        )

    cap.release()

    feature_rows = []

    for segment_number in sorted(segments):

        features = segments[segment_number].get_features()

        feature_rows.append(features)

    print(f"Generated {len(feature_rows)} segments")

    return feature_rows


# ==========================================
# MAIN PROGRAM
# ==========================================

def main():

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--videos",
        required=True,
        help="Folder containing PRE videos"
    )

    parser.add_argument(
        "--model",
        required=True,
        help="Path to best.pt"
    )

    parser.add_argument(
        "--crop",
        type=int,
        nargs=4,
        metavar=("LEFT", "TOP", "RIGHT", "BOTTOM")
    )

    parser.add_argument(
        "--feed-zone",
        type=float,
        nargs=4,
        metavar=("X_MIN", "Y_MIN", "X_MAX", "Y_MAX")
    )

    parser.add_argument(
        "--output",
        default="output/behavior_features.csv"
    )

    args = parser.parse_args()

    video_folder = Path(args.videos)
    model_path = Path(args.model)

    if not model_path.exists():
        raise FileNotFoundError(f"Model not found: {model_path}")

    if not video_folder.is_dir():
        raise FileNotFoundError(f"Video folder not found: {video_folder}")

    if args.feed_zone is not None:

        x_min, y_min, x_max, y_max = args.feed_zone

        if not (
            0 <= x_min < x_max <= 1
            and 0 <= y_min < y_max <= 1
        ):
            raise ValueError("Invalid feeding-zone coordinates")

    video_files = sorted([
        p for p in video_folder.rglob("*")
        if p.suffix.lower() in [".mp4", ".mov", ".avi", ".m4v"]
        and p.stem.upper().endswith("_PRE")
    ])

    if not video_files:
        print("No PRE videos found!")
        return

    all_features = []

    for video in video_files:

        rows = process_video(
            video,
            model_path,
            args.crop,
            args.feed_zone
        )

        all_features.extend(rows)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if all_features:

        with open(
            output_path,
            "w",
            newline="",
            encoding="utf-8"
        ) as file:

            writer = csv.DictWriter(
                file,
                fieldnames=all_features[0].keys()
            )

            writer.writeheader()
            writer.writerows(all_features)

    print("\n================================")
    print("FEATURE EXTRACTION COMPLETED")
    print("================================")
    print(f"Videos processed: {len(video_files)}")
    print(f"Feature rows: {len(all_features)}")
    print(f"Saved to: {output_path}")


if __name__ == "__main__":
    main()
