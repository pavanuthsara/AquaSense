
from ultralytics import YOLO

# Load your trained guppy detector
model = YOLO(
    "runs/guppy_detector_v1/weights/best.pt"
)

# Evaluate using validation images
metrics = model.val(
    data="dataset/data.yaml",
    split="val",
    imgsz=640,
    plots=True
)

print("\n===== Guppy Detection Results =====")

print(f"Precision: {metrics.box.mp:.4f}")
print(f"Recall: {metrics.box.mr:.4f}")
print(f"mAP@50: {metrics.box.map50:.4f}")
print(f"mAP@50-95: {metrics.box.map:.4f}")

print("===================================")
