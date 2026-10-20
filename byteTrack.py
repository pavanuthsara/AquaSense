from ultralytics import YOLO

# Load your custom fine-tuned YOLO model
model = YOLO("runs/guppy_detector_v3/weights/best.pt")

# Stream the tracking process to keep RAM usage low
results = model.track(
    source="data_collection/S2026-10-07-AM-01_PRE_001.mp4",
    tracker="bytetrack.yaml",
    conf=0.25,
    imgsz=640,
    persist=True,
    save=True,
    stream=True  # Enables generator mode to prevent memory accumulation
)

# Iterate through the generator to execute tracking frame-by-frame
for frame_idx, r in enumerate(results):
    # Optional: print progress every 500 frames
    if frame_idx % 500 == 0:
        print(f"Processed frame {frame_idx}...")

print("Tracking completed successfully!")