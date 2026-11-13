# Bundled on-device models

These TensorFlow Lite models ship inside the app and run on the phone. Nothing
is uploaded; only the result is sent to the backend.

## Photo white-spot check (existing)

| File | What it is |
|---|---|
| `guppy_disease.tflite` | MobileNetV3 2-class photo model (`healthy`, `white_spot`), 224x224 NHWC, pixels 0-255. |
| `guppy_disease_labels.txt` | `healthy`, `white_spot`. |

Source: `Research new/All models data notebooks/1_models/photo_model_v1_2026-10-16/guppy_baseline_dynamic.tflite`.
Model version string: `guppy-white-spot-2026-10-16`.

## Video white-spot check (DIS-011..018)

| File | What it is | md5 |
|---|---|---|
| `fish_detector.tflite` | YOLO11n fish finder, 1 class `fish`. Input `[1,3,512,512]` float32 **NCHW**, RGB, 0-1. Output `[1,5,5376]` = cx,cy,w,h,score, box values normalised 0-1 of the 512 square. No NMS inside. | `a915e2bbac39c4cc911df2da90b06dad` |
| `guppy_video_model.tflite` | MobileNetV3 3-class model (`healthy`, `not_fish`, `white_spot`). Input `[1,224,224,3]` float32 **NHWC**, RGB, 0-255. Output `[1,3]` probabilities. | `bf01e88db3b0843dbfc178e033463c08` |
| `guppy_video_labels.txt` | `healthy`, `not_fish`, `white_spot` (one per line, in that order). | |

Sources:
- `Research new/All models data notebooks/1_models/fish_finder_2026-10-19/fish_detector.tflite`
- `Research new/All models data notebooks/1_models/video_model_v5_2026-10-19_CURRENT/guppy_video_model.tflite`
- `Research new/All models data notebooks/1_models/video_model_v5_2026-10-19_CURRENT/labels_video.txt`

Model version strings: `guppy-video-v5-2026-10-19` (white-spot), `fish-finder-yolo11n-2026-10-19` (finder).

The whole pipeline mirrors the reference script `video_check/check_video.py`; the
fixed numbers live in `lib/features/disease_check/domain/video_check_settings.dart`.
