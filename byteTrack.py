from ultralytics import YOLO

model = YOLO(
    "runs/guppy_detector_v1/weights/best.pt"
)

# Use a video cropped to the same tank ROI
# used during YOLO training.
results = model.track(
    source="data_collection/S01_PRE_CROPPED.mp4",
    tracker="bytetrack.yaml",
    conf=0.25,
    imgsz=640,
    persist=True,
    save=True
)

print("Tracking completed!")
