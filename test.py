
from ultralytics import YOLO

model = YOLO(
    "runs/guppy_detector_v1/weights/best.pt"
)

model.predict(
    source="dataset/images/val",
    conf=0.25,
    save=True
)

print("Prediction completed!")
