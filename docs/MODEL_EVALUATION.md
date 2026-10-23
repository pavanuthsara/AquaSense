# Evaluating detection, tracking IDs, and appetite classification

These are three separate questions. Keep the metrics separate in your report:

| Component | Ground truth | Main metrics |
| --- | --- | --- |
| YOLO detector (`evaluate_yolo.py`) | Fish bounding boxes on validation images | Precision, recall, mAP@50, mAP@50-95 |
| YOLO + ByteTrack (`evaluate_bytetrack.py`) | Fish boxes AND consistent fish IDs on a recorded test clip | IDF1, ID precision/recall, ID switches, MOTA, false positives/misses, fragmentation |
| Appetite Random Forest (`evaluate_random_forest.py`) | Manually recorded High/Low session labels | Accuracy, balanced accuracy, per-class precision/recall/F1, macro F1, confusion matrices, majority-class baseline |

Your existing YOLO evaluator uses `split="val"`. Call those results validation
metrics unless the split was genuinely reserved as an untouched final test.
Seeing tracking IDs on the screen alone does not establish tracking accuracy.

## Environment

From the repository root with your research environment active:

```powershell
python -m pip install -r requirements-evaluation.txt
```

Use the existing Ultralytics, OpenCV, pandas, NumPy, scikit-learn, and joblib
research environment. The extra tracking dependency is `motmetrics==1.4.0`.
The IoU helper avoids NumPy APIs removed in NumPy 2. No mobile/backend/Docker
process is needed for these offline evaluations, and no camera is opened.

## 1. Tracking: prepare independent ground truth

Select a short recorded clip from a session excluded from detector training
and tracker tuning. Start with 10–20 seconds and include representative movement,
crossings, and any occlusions whose identities can actually be verified.

Use CVAT in VIDEO tracking mode. Annotate every visible guppy and preserve one
ground-truth ID for the same fish across the evaluated frames. Review any
interpolation and identity through crossings manually. Do not give the same
fish a new GT ID on every frame, and do not accept the model's own IDs as ground
truth. Normal YOLO image-label files have no tracking identities and cannot be
used to calculate IDF1 or identity switches. Your current checkout has those
detection labels, but no manually verified tracking GT file was found.

Export single-class tracks in MOT format. Each comma-separated row is:

```text
frame,id,left,top,width,height,confidence,-1,-1,-1
```

There is NO header in a MOT file. For GT, confidence is 1 (valid annotation).
Original video frames start at 1, fish IDs must be nonnegative integers, and
bounding-box left/top use 1-based original-image pixel coordinates. Example:

```text
1,1,101,51,30,15,1,-1,-1,-1
1,2,201,81,25,12,1,-1,-1,-1
7,1,105,52,30,15,1,-1,-1,-1
7,2,198,83,25,12,1,-1,-1,-1
```

These four rows are illustrative only, not ground truth for your actual video.
CVAT MOT ground truth may have nine columns; the evaluator reads the first
seven and assumes all scored objects are guppies. Confirm the exported coordinate
origin; add 1 to left/top if your annotation exporter uses 0-based coordinates.
Ignored boxes/regions (GT flag 0) and multiclass/distractor preprocessing are
not supported. Start with a fully annotated, single-class clip.

Annotate a declared frame range or frame list completely. An unannotated frame
is not necessarily an empty tank. Include actually empty annotated frames in
the frame list so spurious tracks count as false positives.

## 2. Export tracker predictions

Replace the video path with your held-out recorded test clip:

```powershell
python evaluate_bytetrack.py --video data_collection/held_out_test.mp4 --save-video --output output/evaluation/tracking_export
```

Without `--gt`, this is export only. `summary.json` explicitly says
`NOT_EVALUATED_NO_GROUND_TRUTH` and contains no fabricated accuracy scores.
Output files include:

- `predictions_mot.txt`: original-video frame number, predicted ID, box, confidence.
- `evaluated_frames.csv`: every processed frame, including frames with no tracks.
- `tracked_preview.mp4`: optional visual evidence; a preview is not a metric.
- `summary.json`: detector settings, processing rate, hashes, dependency versions.

Default sampling is approximately 5 FPS, `imgsz=960`, `conf=0.20`, matching the
current behavior pipeline. For a 30 FPS video, sampled original frame numbers
are 1, 7, 13, etc.; annotate those frames or use dense original-video GT. A
`--process-fps 0` run evaluates native-rate tracking instead and must be reported
as a different experiment. `--max-frames 300` limits processing to the first
300 original frames. Keep settings fixed before collecting evaluation results.

If you used a tank crop, add `--crop LEFT TOP RIGHT BOTTOM`. Predictions are
shifted back into ORIGINAL-video coordinates for scoring; do not compare these
to crop-relative annotation coordinates. IDs are temporary within one sequence,
not proof of unique lifetime fish identity or total population.

## 3. Score tracking predictions against real annotations

After verifying `data_collection/tracking_gt/gt.txt` for your test video:

```powershell
python evaluate_bytetrack.py --predictions output/evaluation/tracking_export/predictions_mot.txt --gt data_collection/tracking_gt/gt.txt --frames output/evaluation/tracking_export/evaluated_frames.csv --output output/evaluation/tracking_scored
```

Or export and score together:

```powershell
python evaluate_bytetrack.py --video data_collection/held_out_test.mp4 --gt data_collection/tracking_gt/gt.txt --save-video --output output/evaluation/tracking_scored
```

Existing prediction files require `--frames` or `--num-frames N`. `--num-frames`
declares every frame from 1 through N fully annotated; it is unsuitable for
sparsely annotated clips unless every intervening frame really is annotated.
The default IoU matching threshold is 0.50. Track IDs need not have the same
numeric values as ground-truth IDs: the evaluator matches trajectories.

Outputs:

| File | Use |
| --- | --- |
| `metrics.csv`, `summary.json` | Exact metric values and protocol |
| `tracking_metrics.png` | Rates, error counts, and fish count comparison for a slide |
| `tracking_events.csv` | Frame-by-frame matches, misses, false positives, and switches |
| `per_frame_counts.csv`, `scored_frames.csv` | Scoring scope and visible-track counts |
| `methodology.md` | Method explanation and interpretation |

IDF1/IDP/IDR and precision/recall are fractions; multiply by 100 for percentages.
Higher IDF1 is better. Fewer ID switches and fragmentations are better. MOTA
penalizes misses, false positives, and ID switches and can be negative.
`motp` in motmetrics is mean 1-IoU distance; `mean_matched_iou` is 1 minus that
value. Undefined metrics are null/N/A, not silently perfect scores.

This is a single-class YOLO+ByteTrack evaluation using CLEAR and Identity
metrics, not an official MOT17 benchmark run. No HOTA metric is claimed. Evaluate
several independent clips and report each clip's scope, frame count, and settings.

Presentation wording AFTER scoring actual annotations:

> I evaluated YOLO and ByteTrack on an independently annotated test clip. Every
> visible fish had a consistent ground-truth ID. Using IoU matching at 0.5, I
> measured IDF1, identity switches, missed fish, false positives, and MOTA.

Before ground truth is ready, say predictions were exported and the quantitative
identity evaluation is pending. Do not substitute visual tracking for ID accuracy.

## 4. Evaluate the appetite model used by the mobile app

```powershell
python evaluate_random_forest.py
```

The default `--kind live-pre --mode cv` evaluates the live 10-second PRE model
using `output/poc_features.csv`. It reuses the exact data-selection and pipeline
builders from `train_live_rf.py`. It does not run the saved all-data classifier
on its own training rows and call that test accuracy.

Protocol:

1. Keep labeled 10-second PRE windows passing the same tracking-quality rules
   used in training. The CSV cannot establish actual sampled-frame coverage;
   live inference additionally checks the number of frames collected.
2. Hold out one entire feeding session at a time; train on all other sessions.
3. Fit the median imputer and RF using only that fold's training sessions.
4. Predict every held-out 10-second window; retain its source CSV row and fold.
5. Average held-out window probabilities to produce a supplementary session
   result. The individual-window metrics best describe the app's single check.
6. Compare with a training-fold majority-label baseline. Report per-class recall,
   particularly Low appetite, alongside accuracy and macro F1.

RF settings match the live recipe: 100 trees, maximum depth 3, minimum leaf size
5, balanced class weights, random seed 42. The current dataset has very few
independent sessions; repeated windows are not independent feeding trials.

The default output directory is a timestamped folder beneath
`output/evaluation/random_forest/`. An explicit `--output` must be new or empty
to protect earlier reports. No trained/deployment model is overwritten.

| File | Use |
| --- | --- |
| `confusion_matrices.png` | Held-out segment and session confusion matrices |
| `classification_report.txt` | Per-class precision, recall, F1 and support |
| `summary.json` | Metrics, majority baseline, settings, hashes, session splits |
| `segment_predictions.csv` | Every held-out window and its probabilities |
| `session_predictions.csv` | Supplementary session-level results |
| `fold_metrics.csv` | Results by held-out session |
| `feature_importances.csv` / `.png` | Training-fold impurity importances, not causal effects |
| `methodology.md` | Method and limitations |

Presentation wording:

> I evaluated the appetite classifier with leave-one-session-out cross-validation.
> All segments from one feeding session were held out together. Missing-value
> handling was learned only from training sessions. I reported per-class
> precision, recall, F1, confusion matrices, and comparison with a majority baseline.

Show the generated scores honestly, including errors. Cross-validation reused
to select hyperparameters is development evidence, not an untouched final test.

## 5. Optional: retrospective session-v3 experiment

```powershell
python evaluate_random_forest.py --kind session-v3
```

This uses the 50-tree/depth-2 session aggregation recipe in `train_rf_v3.py`.
It requires all PRE, FEED, and POST phases and includes recorded response
latency. Missing numeric feature values use constant zero imputation, matching
that script. It rejects incomplete phase sets instead of inventing future
measurements. Report it as retrospective session classification, separately
from the live PRE model. Its score does NOT validate appetite before feeding.

## 6. Optional: evaluate a saved live model on genuinely new sessions

The updated training script saves the actual training session IDs and a data
hash. Older bundles lack that provenance, so the evaluator rejects held-out
mode for them. Use the default CV mode for your current dataset, or deliberately
re-export a training bundle using `train_live_rf.py`, then collect NEW sessions:

```powershell
python evaluate_random_forest.py --mode held-out --model models/random_forest_live_pre.joblib --features output/new_test_features.csv
```

Any session-ID overlap with the recorded training set is rejected. Keep session
IDs truthful; renaming training sessions does not create a test set. Labels
should come from your recorded feeding-response protocol, never model predictions.

## Verification

```powershell
python -m unittest discover -s tests -p test_model_evaluation.py -v
```

Known-answer tests cover identity renaming, ID switches, missed detections,
fragmentation, false positives on empty frames, negative MOTA, missing predictions,
invalid annotations, session-isolated folds, and rejection of training/test overlap.

References:

- https://github.com/cheind/py-motmetrics
- https://github.com/JonathonLuiten/TrackEval/blob/master/docs/MOTChallenge-format.txt
- https://scikit-learn.org/stable/modules/cross_validation.html
- https://scikit-learn.org/stable/common_pitfalls.html
