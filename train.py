
from pathlib import Path
from ultralytics import YOLO

# Project folder
ROOT = Path(__file__).resolve().parent
DATASET = ROOT / "dataset"

# Generate data.yaml automatically
yaml_content = f"""
path: {DATASET.as_posix()}
train: images/train
val: images/val

names:
  0: guppy
"""

(DATASET / "data.yaml").write_text(
    yaml_content,
    encoding="utf-8"
)

# Load pretrained YOLOv8 Nano
model = YOLO("yolov8n.pt")

# Train the guppy detector
model.train(
    data=str(DATASET / "data.yaml"),
    epochs=30,
    imgsz=640,
    batch=4,
    workers=0,
    project=str(ROOT / "runs"),
    name="guppy_detector_v2",
    plots=True
)

print("Training completed!")
