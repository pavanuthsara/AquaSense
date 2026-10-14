# AquaSense — Smart Appetite-Based Feeding for Guppies
## Research Specification (`RESEARCH_SPEC.md`)

**Project:** AquaSense — A Smart System for Ornamental Fish Aquaculture Management  
**Individual component:** Smart Appetite-Based Feeding System  
**Research focus:** Guppy appetite / feeding-motivation estimation using computer vision and machine learning  
**Primary subject:** Guppy fish (*Poecilia reticulata*)  
**Current experimental group:** 7 guppies  
**Current camera:** iPhone 12  
**Current video format:** 1080p, 30 FPS  
**Current main camera view:** Fixed front/side view through the large tank glass panel  
**Current protocol version:** Revised pilot protocol, 3 min PRE + 2 min FEED + 3 min POST  
**Current development stack:** Python computer-vision pipeline, YOLOv8n, ByteTrack, scikit-learn/Random Forest, Spring Boot backend, Flutter mobile application  
**Status date:** 2026-10-12

---

# 1. Purpose of This Specification

This file is the working source of truth for the Smart Appetite-Based Feeding component of AquaSense.

It combines:

- the group proposal presentation,
- the individual proposal report,
- the Guppy Feeding Research Plan,
- the practical decisions made during data collection,
- the current video-recording setup,
- the current annotation and model-training plan,
- the planned application and feeder integration.

Where the original proposal and the later practical plan are different, this file clearly records the **current decision** instead of silently mixing both versions.

The proposal remains the academic basis of the study. This specification records how the research will actually be implemented and tested.

---

# 2. Project Context

AquaSense is a wider ornamental-fish management platform with four research components:

1. Smart appetite-based feeding.
2. Disease identification.
3. Smart water-quality and resource management.
4. Fish export packing plan and advisory.

This specification covers only the **Smart Appetite-Based Feeding** component, while also defining the information this component shares with the common AquaSense platform.

The feeding component is intended to answer a practical question:

> **Do the guppies currently show enough behavioural evidence of feeding motivation to justify feeding?**

The system should make that decision from observable behaviour rather than relying only on a timer.

---

# 3. Problem Statement

Manual feeding and normal automatic aquarium feeders usually depend on human judgement or a fixed schedule. They do not directly determine whether the fish currently show appetite-related behaviour.

This creates several practical problems:

- unnecessary feeding,
- inconsistent feeding,
- feed waste,
- possible water-quality effects from uneaten food,
- repeated manual observation,
- limited feedback to aquarium owners or farm workers.

The research therefore investigates whether measurable guppy behaviour can support a demand-based feeding decision.

---

# 4. Research Gap and Novelty

The literature reviewed in the proposal shows that fish feeding automation has used:

- fish presence in a feeding area,
- water-surface movement,
- fish swimming activity,
- vertical position,
- feeding intensity,
- uneaten feed,
- deep-learning video models,
- multi-modal sensors.

However, the reviewed work mainly uses other species such as koi, Nila fish, grass carp, hybrid grouper, and food-fish species in controlled environments.

The proposed novelty is therefore:

> **Behaviour-based appetite / feeding-motivation classification specifically investigated for guppies using computer vision, followed by an automatic feeding decision and user monitoring.**

The research also prefers measurable and explainable features such as speed, tank-zone occupancy, group spacing, and direction changes instead of relying only on an end-to-end black-box appetite model.

---

# 5. Main Research Question

**Can computer-vision-derived behavioural features from guppy video be used to classify guppy feeding motivation well enough to support a practical automatic feeding system?**

Supporting questions are:

1. Can guppies be detected reliably in the real aquarium setup?
2. Can their movement be tracked well enough to calculate group-level behavioural features?
3. Which behavioural features change most between different feeding-motivation conditions?
4. Can a multi-feature machine-learning model classify feeding motivation better than a simple single-feature rule?
5. Can the complete pipeline make a feeding decision fast and safely enough for a real prototype?

---

# 6. Research Objectives

## 6.1 Main Objective

Design, develop, and evaluate an intelligent appetite-based feeding system for guppies using computer vision, machine learning, automatic feeder control, and a user-facing application.

## 6.2 Specific Objectives

1. Collect and prepare a video dataset of guppies under different normal feeding conditions.
2. Develop a computer-vision model to detect guppies in aquarium video.
3. Track detected guppies across frames.
4. Extract measurable behavioural features related to feeding motivation.
5. Build and evaluate a machine-learning classifier for appetite / feeding-motivation state.
6. Connect the model decision to a safe feeding-control mechanism.
7. Expose current status, feeding history, alerts, and manual controls through the AquaSense application.
8. Evaluate the detector, behaviour features, appetite classifier, end-to-end latency, feeding decisions, and usability.

---

# 7. Scope

## 7.1 In Scope

- guppy video collection,
- frame extraction,
- guppy object detection,
- guppy tracking,
- group-level behaviour analysis,
- appetite / feeding-motivation classification,
- automatic feeding decision logic,
- feeder-control integration,
- feeding-event storage,
- monitoring through a Flutter app,
- Spring Boot API integration,
- evaluation against simple feeding baselines.

## 7.2 Out of Scope for the Current Progress Stage

- a final commercial feeder enclosure,
- multi-tank scaling,
- production cloud deployment,
- final Raspberry Pi INT8 optimization,
- a final three-class appetite model if the data does not support it,
- precise remaining-food stock measurement without a real sensor,
- claiming that a servo command proves food was physically released,
- disease diagnosis,
- water-quality prediction,
- export packing optimization.

---

# 8. Experimental Subjects

## 8.1 Current Fish Group

The current experimental group contains **7 guppies**.

The same group should be observed repeatedly across sessions.

Adding more fish during the main dataset would change:

- group density,
- competition,
- overlap/occlusion,
- movement patterns,
- feeding-zone crowding.

Therefore, the main dataset should keep the fish group stable. If the group size changes, that change must be recorded and treated as a new dataset condition/version.

## 8.2 Animal Welfare Rule

The fish must not be deliberately overfed, severely underfed, stressed, or kept without food for unsafe periods only to create artificial labels.

Normal safe feeding practice should take priority over creating balanced AI classes.

---

# 9. Current Aquarium and Camera Setup

## 9.1 Selected Camera View

The current selected setup is a **front/side view through the large flat glass panel**, not a top view.

The phone should face the glass close to perpendicular so that:

- the complete main swimming area is visible,
- vertical/upper-zone position can be measured,
- perspective distortion is reduced,
- movement coordinates remain stable,
- the same tank zones can be reused across sessions.

## 9.2 Camera

- Device: iPhone 12
- Resolution: 1080p
- Frame rate: 30 FPS
- Orientation: landscape
- Zoom: fixed; avoid changing digital zoom between sessions
- Position: fixed mount / tripod / stable support
- Camera movement during recording: not allowed for main dataset

## 9.3 Lighting

Use the same lighting setup whenever possible.

Preferred condition:

- controlled, stable LED illumination,
- no strong moving shadows,
- reduced reflections from room lights,
- no bright object directly behind the camera operator.

## 9.4 Tank ROI

The useful computer-vision region is the main front-water area of the tank.

The side-glass reflection zones, empty space above the water, and outside borders should be removed from training frames when possible.

For the current 1920×1080 camera position, the pilot crop used in discussion was approximately:

```text
LEFT   = 250 px
RIGHT  = 1640 px
TOP    = 170 px
BOTTOM = 900 px
```

These coordinates are **setup-specific**, not a universal requirement. They are valid only while the camera position stays the same. The crop must be visually checked before applying it to the complete dataset.

---

# 10. Revised Video Collection Protocol

## 10.1 Current Protocol

Each feeding session is divided into three separate videos:

| Phase | Duration | Purpose |
|---|---:|---|
| PRE | 3 minutes | Behaviour before food is given; main input for appetite analysis |
| FEED | 2 minutes | Observe actual response to food; supports label validation |
| POST | 3 minutes | Observe behavioural change after feeding |

Total recorded time per session: **8 minutes**.

This is the current practical protocol and replaces the original proposal's longer 10 min PRE + 5 min FEED + 10 min POST pilot plan.

## 10.2 Why PRE Is the Main Model Input

The final system must decide whether feeding is needed **before food is released**.

Therefore:

- PRE video = main behavioural input for the future appetite classifier.
- FEED video = evidence of actual feeding response.
- POST video = evidence of behaviour after food has been provided.

FEED and POST should not be used as if they were information available to the real-time pre-feeding decision.

## 10.3 Detection Dataset Use

For the **guppy detector only**, frames may be taken from PRE, FEED, and POST because the detector's task is simply to locate guppies.

This gives useful variation:

- separated fish,
- grouped fish,
- overlapping fish,
- fish at different tank positions,
- different motion conditions.

---

# 11. Current Feeding Procedure

## 11.1 Standard Portion

The available scale cannot accurately measure the current small feed portion because it is below 1 g.

Therefore, the research currently uses a repeatable standard portion called:

```text
P1 = standard small feeding portion
```

The same practical scoop/pinch method should be used as consistently as possible.

Do not invent gram values that were not measured.

If a better estimate is required later, multiple identical P1 portions can be weighed together and the total divided by the number of portions.

## 11.2 Current Observation

Across the first **5 sessions**, the guppies consumed the complete portion each time.

Therefore:

```text
Residual Feed Score = 0
```

for those sessions.

This does **not** prove that all five sessions represent the same appetite state. A small portion may be fully eaten under several different levels of feeding motivation.

---

# 12. Session Naming and File Naming

## 12.1 Session ID Pattern

Use:

```text
SYYYY-MM-DD-<DAYPART>-<SESSION_NUMBER>
```

Examples:

```text
S2026-10-07-AM-01
S2026-10-07-EVE-02
S2026-10-07-NIGHT-03
```

Use day-part names consistently.

## 12.2 Video File Pattern

Because each session is already divided into phases:

```text
<SESSION_ID>_PRE.mp4
<SESSION_ID>_FEED.mp4
<SESSION_ID>_POST.mp4
```

Example:

```text
S2026-10-07-AM-01_PRE.mp4
S2026-10-07-AM-01_FEED.mp4
S2026-10-07-AM-01_POST.mp4
```

Do not use unclear names such as `video1.mp4`, `newvideo.mp4`, or `final2.mp4`.

---

# 13. Data Logging

The workbook originally contained detailed sheets. The current practical rule is to avoid unnecessary repeated manual entry.

## 13.1 Sheets Used During Data Collection

### Session_Log
One row per feeding session.

Minimum useful fields:

- Session ID
- Date/time
- Group ID
- Fish count
- Previous feeding time or hours since previous feeding
- Feed portion ID (`P1`)
- Session usable? Yes/No
- Short notes

Camera resolution, FPS, camera view, and lighting do not need to be retyped every session if they are unchanged. Record changes only when they occur.

### Video_Log
One row per video file.

Minimum useful fields:

- Video ID / filename
- Session ID
- Phase (`PRE`, `FEED`, `POST`)
- Duration
- Quality
- Usable? Yes/No
- Exclusion reason, if any

### Feeding_Response
One row per feeding session.

Useful fields:

- Session ID
- standard portion (`P1`)
- latency to first visible feeding response
- active feeding duration if measurable
- response score
- residual feed score
- observed notes

## 13.2 Sheets Used Later

### Segment_Labels
Filled later after PRE videos are processed into windows and behavioural features are calculated.

### Model_Experiments
One row for each meaningful model-training run.

Record:

- data version,
- detector model,
- image size,
- train/validation/test sessions,
- detector metrics,
- appetite-model metrics,
- latency,
- notes.

---

# 14. Feeding Response Scores

## 14.1 Response Score

Current simple observation scale:

| Score | Meaning |
|---:|---|
| 0 | little or no visible feeding response |
| 1 | weak response |
| 2 | normal/moderate response |
| 3 | fast/strong group response |

This is a project-defined observation scale and must be applied consistently.

## 14.2 Residual Feed Score

| Score | Meaning |
|---:|---|
| 0 | no visible food left |
| 1 | very small amount left |
| 2 | noticeable amount left |
| 3 | a lot of food left |

Residual feed should be checked at a consistent time if this metric is used formally.

The first five sessions currently have residual score 0.

---

# 15. Ground Truth and Appetite Labels

## 15.1 Important Rule

Do **not** define appetite only from time since the previous feeding.

For example, do not assume:

```text
12 hours since last feeding = automatically High Appetite
```

Time since feeding is useful context, but it is not direct proof.

## 15.2 Label Evidence

A future appetite / feeding-motivation label should consider evidence such as:

- time since previous feeding,
- PRE behavioural features,
- latency to feeding response,
- how many fish rapidly approach food,
- feeding-zone crowding,
- time taken to consume the standard portion,
- residual feed,
- unusual environmental or fish behaviour.

## 15.3 Current Class Plan

The proposal originally considered:

```text
Low / Medium / High
```

The current implementation should begin with:

```text
High feeding motivation
Low feeding motivation
```

The Medium class should be added only if the collected data supports a clear and repeatable intermediate condition.

## 15.4 Current Limitation

The first 5 sessions are not enough to train or claim a final appetite classifier.

All 5 sessions also had the complete P1 portion eaten, so label diversity has not yet been demonstrated.

For now, the correct development priority is:

```text
YOLO detector
→ ByteTrack
→ feature extraction
→ more independent sessions
→ appetite classifier later
```

---

# 16. Frame Extraction

## 16.1 Do Not Label Every Frame

At 30 FPS, an 8-minute session contains many thousands of highly similar frames.

The detector does not need every frame.

## 16.2 Pilot Sampling Plan

A practical sampling plan is:

| Phase | Duration | Approx. sampling | Approx. frames/session |
|---|---:|---:|---:|
| PRE | 3 min | every 8–10 s | ~18–22 |
| FEED | 2 min | every ~8 s | ~15 |
| POST | 3 min | every 8–10 s | ~18–22 |

Approximate total: **~50–60 frames per session**.

With 5 sessions this gives roughly **250–300 candidate images**.

A first detector dataset target of roughly **250–400 good, diverse annotated images** is reasonable for the pilot model.

## 16.3 Frame Selection Rules

Prefer diversity over quantity.

Include examples with:

- fish near the top,
- fish near the bottom,
- fish near the tank edge,
- grouped fish,
- separated fish,
- overlapping fish,
- different swimming directions,
- different feeding phases,
- difficult but usable lighting/reflection conditions.

Remove or exclude frames that are:

- badly blurred,
- strongly obstructed,
- nearly exact duplicates,
- unusable due to camera movement.

---

# 17. Image Cropping

Because the camera is fixed, apply the same ROI crop automatically to all frames from that fixed setup.

Keep the original extracted frames unchanged and save cropped versions separately.

Example structure:

```text
frames/
  S01_PRE/
    frame_000.jpg

cropped_frames/
  S01_PRE/
    frame_000.jpg
```

Do not crop or resize images again after final annotation unless the annotations are regenerated for the new image geometry.

---

# 18. CVAT Annotation Specification

## 18.1 Annotation Tool

CVAT.

## 18.2 Detector Class

Only one object class is required:

```text
0 = guppy
```

Do not create YOLO classes for:

- hungry,
- full,
- high appetite,
- low appetite,
- male,
- female,
- PRE,
- FEED,
- POST.

These are not object classes for the detector.

## 18.3 Box Rules

For every frame:

- annotate every clearly visible real guppy,
- use one bounding box per visible fish,
- keep boxes reasonably tight around the visible fish, including tail,
- if 3 fish are clearly visible, create 3 boxes,
- if 7 fish are clearly visible, create 7 boxes,
- do not guess the location of hidden fish,
- if two fish overlap but are still visually distinguishable, create two boxes,
- annotate a partly visible fish if enough is visible to identify it confidently,
- ignore a tiny unclear tail/body fragment,
- do not annotate reflections in the side glass.

## 18.4 Annotation Quality Check

Before exporting, review frames for:

- missed visible fish,
- accidental reflection labels,
- boxes that are too loose,
- boxes that cut off obvious parts of the fish,
- merged boxes around multiple fish,
- inconsistent treatment of partial fish.

---

# 19. Dataset Splitting and Leakage Prevention

This is a critical research rule.

Frames from the same feeding session are highly related. They must not be randomly divided across train and test sets.

## 19.1 Current 5-Session Pilot Split

For the current pilot detector:

| Sessions | Split |
|---|---|
| Session 1 | Train |
| Session 2 | Train |
| Session 3 | Train |
| Session 4 | Validation |
| Session 5 | Test |

All PRE, FEED, and POST frames from a session stay in the same split.

For example:

```text
Session 5 PRE   → Test
Session 5 FEED  → Test
Session 5 POST  → Test
```

Do not do:

```text
Session 5 PRE   → Train
Session 5 FEED  → Validation
Session 5 POST  → Test
```

## 19.2 Later Dataset

When more sessions are available, use a session/day-isolated split, approximately 70/15/15 if suitable.

The exact percentages are less important than ensuring that complete sessions/days are isolated.

---

# 20. Detection Model

## 20.1 Model

Primary detector:

```text
YOLOv8n
```

Reason:

- lightweight,
- suitable for custom fine-tuning,
- supported by the proposal,
- more suitable for later edge deployment than larger variants.

## 20.2 Pilot Training Configuration

Initial training configuration:

```text
model: yolov8n.pt
epochs: ~50
batch: ~8 (adjust for hardware)
image size: start at 960 for the current small fish appearance
class: guppy only
```

`imgsz=960` is a current practical choice because the guppies occupy a small part of the full frame. Later, compare with 640 for faster edge inference.

## 20.3 Output

The key trained artifact is:

```text
best.pt
```

## 20.4 Detector Evaluation

Evaluate on the held-out test session using:

- precision,
- recall,
- mAP@0.5,
- visual inspection.

Visually inspect:

- missed fish,
- false detections from reflections,
- overlapping fish,
- fish near tank borders,
- fast movement,
- partial occlusion.

---

# 21. Tracking

## 21.1 Tracker

Primary tracker:

```text
ByteTrack
```

## 21.2 Purpose

The tracker turns frame-by-frame detections into movement trajectories.

Example:

```text
Frame t:
Fish ID 1 → x1, y1
Fish ID 2 → x2, y2

Frame t+1:
Fish ID 1 → x1', y1'
Fish ID 2 → x2', y2'
```

Perfect long-term individual identity is not required for the first version because the main target is **group-level appetite behaviour**.

ID switches are still a quality issue, but they do not automatically invalidate group-level measurements.

---

# 22. Behavioural Feature Extraction

Behaviour features are calculated mainly from **PRE videos**.

## 22.1 PRE Segmentation

Divide each 3-minute PRE video into six 30-second windows:

```text
00:00–00:30
00:30–01:00
01:00–01:30
01:30–02:00
02:00–02:30
02:30–03:00
```

Each window produces one feature row.

With 5 sessions:

```text
5 PRE videos × 6 windows = 30 feature rows
```

However, these are still only **5 independent feeding sessions**, not 30 independent experiments.

## 22.2 Coordinate Normalization

Normalize tracked positions by the ROI dimensions:

```text
x_norm = x / ROI_width
y_norm = y / ROI_height
```

This makes features less dependent on raw pixel size.

## 22.3 Planned Features

### A. Average Swimming Speed

Estimate average movement speed from tracked centre-point displacement over time.

Prefer normalized distance per second instead of only raw pixels/frame.

### B. Upper-Zone Occupancy

Measure the fraction of fish observations located in the predefined upper region of the tank.

Because the camera uses a front/side view, this feature is physically interpretable.

### C. Feeding-Zone Occupancy

Define a fixed ROI around the normal feeding location.

Measure the fraction of fish observations within this area.

### D. Group Spacing / Density

Calculate mean pairwise distance between visible fish.

Smaller distance can indicate tighter group formation.

Use either spacing or a derived density measure consistently; avoid including redundant versions unless model analysis justifies them.

### E. Direction-Change Rate

Estimate how often fish movement direction changes within a segment.

The exact angle/change threshold is a pilot parameter and should be finalized after visual validation.

### F. Visibility / Detection Quality Metadata

Record or derive:

- mean number of visible/detected fish,
- low-confidence periods,
- high-occlusion periods.

Segments with poor tracking quality should be flagged rather than silently treated as reliable data.

---

# 23. Behaviour Feature Validation

Before training the appetite classifier, manually inspect a small sample of videos and compare the calculated values with what is visible.

Validate whether:

- higher calculated speed really corresponds to faster motion,
- feeding-zone occupancy matches visible fish presence in the zone,
- upper-zone occupancy matches visible position,
- group spacing decreases when fish visibly gather,
- direction-change rate rises when movement becomes more irregular/search-like.

A classifier cannot correct features that were calculated incorrectly.

---

# 24. Appetite Classifier

## 24.1 Planned Model

Primary model:

```text
Random Forest
```

Reason:

- works well with small tabular feature datasets,
- handles nonlinear relationships,
- supports feature-importance analysis,
- is easier to explain than an end-to-end video classifier,
- matches the proposal methodology.

## 24.2 Input

One feature vector per PRE segment, for example:

```text
[
  avg_speed,
  upper_zone_occupancy,
  feeding_zone_occupancy,
  mean_group_distance,
  direction_change_rate
]
```

## 24.3 Output

Initial intended output:

```text
High feeding motivation
Low feeding motivation
```

Medium remains optional and should be added only if the data supports it.

## 24.4 Current Training Gate

Do **not** claim a final Random Forest appetite model until enough independent sessions with meaningful label variation have been collected.

The current 5 sessions are sufficient for:

- detector development,
- tracker development,
- feature-extraction development,
- pilot visual comparisons.

They are not yet strong evidence for a final appetite classifier.

A practical future target is **20–30+ independent feeding sessions**, if safe and feasible, with naturally different responses.

---

# 25. Baselines

## 25.1 System Baseline

Fixed-schedule automatic feeding.

Comparison:

```text
Timer system:
"It is feeding time, so feed."

AquaSense:
"Current fish behaviour provides enough evidence to recommend feeding."
```

## 25.2 Model Baseline

A simple single-feature or rule-based decision, such as feeding-zone occupancy above a threshold.

Compare this with the multi-feature Random Forest.

---

# 26. Evaluation Metrics

## 26.1 Detection

- Precision
- Recall
- mAP@0.5
- visual error review

## 26.2 Appetite Classification

When enough labelled data exists:

- Accuracy
- Precision per class
- Recall per class
- F1-score per class
- Macro F1
- Confusion matrix

The confusion matrix is important for showing which appetite states are confused.

## 26.3 Behaviour Feature Quality

Manual comparison of automated features against selected video samples.

## 26.4 Latency

Measure end-to-end time from completed input observation/window to appetite/feeding decision.

The proposal includes a target of under 2 seconds on Raspberry Pi 4, but this must be treated as a **target**, not a result, until it is measured.

## 26.5 Feeding Decision Performance

Measure whether the system:

- recommends/feeds when feeding is justified,
- avoids unnecessary repeated feeding,
- behaves better than a fixed timer under comparable conditions.

## 26.6 Food Waste

The proposal planned residual feed measurement. In the current pilot, visible residual feed is recorded using a simple score because the food quantity is too small for the available scale.

A more precise waste method may be added later if practical.

## 26.7 Usability

The final app can be evaluated with the System Usability Scale (SUS).

The proposal uses ~68 as a general acceptable benchmark.

---

# 27. End-to-End System Architecture

```text
iPhone / camera
      ↓
Python vision service
      ↓
YOLOv8n detector
      ↓
ByteTrack
      ↓
Behaviour feature extractor
      ↓
Random Forest appetite classifier
      ↓
Feeding decision / safety rules
      ↓
Feeder controller / servo
      ↓
Spring Boot backend
      ↓
Database
      ↓
Flutter application
```

The feeding component also shares feeding-event information with the wider AquaSense platform.

---

# 28. Software Responsibilities

## 28.1 Python AI Service

Responsible for:

- camera/video input,
- ROI crop,
- guppy detection,
- tracking,
- feature extraction,
- appetite inference,
- confidence/quality metadata,
- sending processed results to the backend.

## 28.2 Spring Boot Backend

Responsible for:

- REST APIs,
- authentication/authorization,
- feeding-event history,
- appetite-result history,
- device status,
- manual-control requests,
- communication with the app,
- shared AquaSense integration.

## 28.3 Flutter App

Minimum useful progress-version screens:

### Dashboard

- current appetite/feeding-motivation result,
- confidence if available,
- last analysed time,
- last feeding time,
- camera/edge-device status,
- feeder connection/status.

### Controls

- manual feeding command,
- enable/disable automatic feeding.

### History

- previous appetite results,
- feeding events,
- automatic/manual source,
- portion ID / amount if available,
- alerts or failures.

---

# 29. Database Decision

The original documents are inconsistent:

- the proposal presentation lists **Firebase**,
- the individual report later describes **Azure App Service + Azure SQL**.

This must be finalized before the next formal architecture update.

Until then, database access should be kept behind backend service/repository interfaces so that the AI pipeline does not depend directly on the database product.

---

# 30. Feeder Safety Rules

Automatic feeding must fail safe.

Minimum rules:

1. Do not feed if a valid appetite result cannot be produced.
2. Do not repeatedly feed because the same prediction is received several times.
3. Use a configurable feeding cooldown / minimum safe interval.
4. Allow automatic feeding to be disabled.
5. Keep manual control available.
6. Stop automatic actuation if camera/AI/device health is invalid.
7. Log every feeding command.
8. If there is no physical feedback sensor, display **"feeder command sent"** rather than falsely claiming that food release was verified.

The proposal also includes a watchdog/fail-safe concept for the edge controller.

---

# 31. Application Alert Rules

Potential alerts:

- camera/edge device offline,
- feeder controller offline,
- feeding command failed,
- abnormal repeated appetite state,
- system processing failure.

A **low food stock** alert must not be claimed unless hardware exists that can actually measure or infer remaining food.

---

# 32. Current Data Status

As of 2026-10-12:

- Experimental group: 7 guppies.
- Camera: iPhone 12.
- View: fixed front/side view.
- Recording: 1080p, 30 FPS.
- Sessions collected: 5 across two days.
- Videos per session: 3 (`PRE`, `FEED`, `POST`).
- Total current videos: 15.
- Session duration: 3 min PRE + 2 min FEED + 3 min POST.
- Feed portion: same standard portion `P1` for the 5 sessions.
- Residual feed: 0 for all 5 sessions; all visible food was consumed.
- Frame extraction: started.
- ROI cropping: started/tested.
- CVAT annotation: started.
- CVAT class: `guppy` only.
- Detector training: next major step.
- ByteTrack: planned after detector validation.
- Behaviour features: planned after tracking.
- Final Random Forest appetite classifier: not ready; more independent sessions required.

---

# 33. Current CVAT / Annotation Progress

A CVAT task has been created for cropped frames.

The shown pilot task contains 24 frames in one annotation batch, and annotation has started.

The correct rule is:

> Annotate every clearly visible real fish in the frame, even if the number changes from frame to frame.

Therefore:

```text
3 visible fish → 3 boxes
5 visible fish → 5 boxes
6 visible fish → 6 boxes
7 visible fish → 7 boxes
```

Do not force the annotation count to equal the known total fish count.

---

# 34. Recommended Repository Structure

```text
aquasense-feeding/
│
├── README.md
├── RESEARCH_SPEC.md
│
├── data/
│   ├── raw_videos/
│   │   ├── S2026-10-07-AM-01/
│   │   │   ├── S2026-10-07-AM-01_PRE.mp4
│   │   │   ├── S2026-10-07-AM-01_FEED.mp4
│   │   │   └── S2026-10-07-AM-01_POST.mp4
│   │   └── ...
│   │
│   ├── extracted_frames/
│   ├── cropped_frames/
│   ├── annotations/
│   ├── detector_dataset/
│   │   ├── images/
│   │   │   ├── train/
│   │   │   ├── val/
│   │   │   └── test/
│   │   ├── labels/
│   │   │   ├── train/
│   │   │   ├── val/
│   │   │   └── test/
│   │   └── data.yaml
│   │
│   └── features/
│       └── behaviour_features.csv
│
├── scripts/
│   ├── extract_frames.py
│   ├── crop_frames.py
│   ├── train_detector.py
│   ├── test_detector.py
│   ├── track_video.py
│   ├── extract_features.py
│   └── train_appetite_model.py
│
├── models/
│   ├── detector/
│   └── appetite/
│
├── backend/
│   └── spring-boot-service/
│
├── mobile/
│   └── flutter_app/
│
├── hardware/
│   └── feeder/
│
├── experiments/
│   ├── detector_runs/
│   ├── appetite_runs/
│   └── metrics/
│
└── docs/
    ├── data_collection_log.xlsx
    ├── diagrams/
    └── presentation_evidence/
```

---

# 35. Dataset Versioning

Every meaningful dataset change should have a version.

Example:

```text
D1 = first 5 sessions, 7 guppies, current camera setup
D2 = additional sessions under same setup
D3 = only if fish group/camera/setup changes
```

Record for every model run:

- dataset version,
- train sessions,
- validation sessions,
- test sessions,
- preprocessing version,
- crop version,
- model version.

---

# 36. Model Experiment Naming

Example:

```text
DET-V1-D1-YOLOv8n-960
DET-V2-D2-YOLOv8n-640
APP-V1-D2-RF-BINARY
```

This makes it easier to reproduce results for the report and presentation.

---

# 37. Progress Presentation Minimum Demonstration

A strong progress presentation does not require the final commercial system.

The minimum useful evidence is:

1. Real aquarium and fixed camera setup.
2. Real self-collected PRE/FEED/POST videos.
3. Data/session log.
4. Cropped frames.
5. CVAT bounding-box annotations.
6. Custom-trained YOLOv8n detector.
7. Detector result on a held-out session.
8. ByteTrack running on a real video.
9. Preliminary movement/behaviour feature CSV.
10. Simple Flutter/backend screen showing the latest result/history, if time allows.

If the appetite classifier is not scientifically ready, say so clearly and show detector/tracking/feature progress instead of forcing unreliable labels.

---

# 38. Current Immediate Work Plan

## Phase A — Finish Detector Dataset

- continue extracting diverse frames,
- crop to fixed tank ROI,
- annotate approximately 250–400 good frames,
- keep Session 5 completely held out from training.

## Phase B — Train Detector

- export Ultralytics YOLO detection labels from CVAT,
- create session-isolated train/val/test folders,
- create `data.yaml`,
- train YOLOv8n,
- save `best.pt`,
- report precision, recall, mAP@0.5,
- visually inspect errors.

## Phase C — Add Tracking

- run ByteTrack on held-out video,
- save track centre positions,
- inspect ID stability and missed fish.

## Phase D — Feature Extraction

- use PRE videos,
- create 30-second windows,
- calculate normalized movement and occupancy features,
- validate the features manually.

## Phase E — Continue Data Collection

- continue safe, consistent sessions,
- record feeding-response evidence,
- collect enough independent variation before training the final appetite model.

## Phase F — Appetite Model

- finalize label rules,
- start with binary High/Low feeding motivation,
- train Random Forest,
- evaluate with session-isolated data,
- compare against single-feature baseline.

## Phase G — Application / Feeder Integration

- expose result through Spring Boot,
- show it in Flutter,
- add manual controls and history,
- add safe feeder control only after prediction logic is reliable.

---

# 39. Research Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Fish appear small in full frame | missed detections | crop fixed ROI; start detector training at larger input size such as 960 |
| Glass reflections | false detections | crop side glass; control room lighting; do not annotate reflections |
| Fish overlap | missed/merged detections and ID switches | include crowded FEED frames in detector training; evaluate group-level features |
| Too few independent sessions | overfitting / weak appetite claims | continue data collection; do not count segments as independent sessions |
| All food consumed in every session | weak label variation | use response timing/behaviour evidence; do not intentionally overfeed |
| Medium appetite is unclear | unreliable 3-class model | begin with High/Low binary classification |
| Camera position changes | feature inconsistency | keep phone fixed; create a new dataset version if setup changes |
| Random frame split | data leakage | split by whole session/day |
| Feed mass cannot be measured | poor portion metadata | use fixed portion ID `P1`; do not invent grams |
| Servo command fails | fish may not actually receive food | log command separately from verified feeding; add feedback hardware if required |
| Database design inconsistent | integration confusion | finalize Firebase vs Azure SQL before next formal architecture update |
| Low-food alert without sensor | false functionality | remove/disable until hardware supports it |

---

# 40. Differences Between Original Proposal and Current Implementation

| Topic | Original proposal/report | Current implementation decision |
|---|---|---|
| Camera angle | ~45° from top in methodology | fixed front/side view close to perpendicular to glass |
| Recording duration | 10 min PRE + 5 min FEED + 10 min POST | 3 min PRE + 2 min FEED + 3 min POST |
| Feed amount | example of 0.5 g appears in proposal methodology | no fixed 0.5 g; use repeatable standard portion `P1` because exact mass is not measurable with current scale |
| Appetite classes | Low / Medium / High planned | start with High/Low; Medium only if data supports it |
| High label | proposal discussed long fasting-based baseline | current spec does not assign High only from elapsed time; feeding response must support labels |
| Database | Firebase in presentation; Azure SQL in later report | unresolved; must be finalized |
| Detector image size | not fixed as final research result | start around 960 because fish are small; later compare 640 for edge speed |
| Food waste | dried/weighed residual feed trial proposed | pilot currently uses residual score; precision method may be revised |
| Growth comparison | short 7-day system benchmark discussed | not a main progress-stage success criterion |
| Low food alert | included in requirements | do not claim unless a real sensor/measurement method exists |

These changes should be documented as pilot-based methodology refinement rather than hidden.

---

# 41. Acceptance Criteria

## 41.1 Detector Stage

The detector stage is considered ready to move forward when:

- training/validation/test are split by session,
- test frames come from an unseen session,
- the model detects guppies reliably enough for tracking,
- reflections are not commonly detected as fish,
- precision/recall/mAP are reported,
- difficult frames are manually reviewed.

The proposal target of mAP@0.5 ≥ 85% can remain a target, but results must be reported honestly even if lower.

## 41.2 Tracking Stage

Ready when:

- detected fish receive usable track IDs,
- centre coordinates can be exported,
- group-level motion remains measurable even when IDs switch sometimes.

## 41.3 Feature Stage

Ready when:

- PRE videos produce repeatable 30-second feature rows,
- calculated values match manual visual inspection,
- tracking failures are flagged.

## 41.4 Appetite Stage

Ready when:

- label rules are written before final training,
- enough independent sessions exist,
- train/test are session-isolated,
- binary model performance is reported using F1/confusion matrix,
- results outperform or meaningfully compare with the simple baseline.

## 41.5 System Stage

Ready when:

- camera/video input works,
- detector works,
- tracker works,
- features are calculated,
- appetite result is produced,
- feeding decision follows safety rules,
- backend receives the result,
- Flutter app displays status/history,
- feeder command is logged safely.

---

# 42. Unresolved Decisions

The following points still need a final decision or more data:

1. Final appetite ground-truth rule.
2. Final number of appetite classes.
3. Final minimum number of independent sessions.
4. Final feature set after pilot analysis.
5. Final direction-change threshold.
6. Final feeding-zone ROI coordinates.
7. Final Raspberry Pi model size/input size.
8. Final database: Firebase vs Azure SQL.
9. Final feeder feedback mechanism.
10. Whether residual feed will remain a visual score or use a more precise method.
11. Whether the final system uses exactly the same camera as data collection or a dedicated Raspberry Pi camera.

---

# 43. Source Traceability

This specification is based on the following project material:

## Group Proposal Presentation

**File:** `proposal presentation final.pdf`

Important source areas:

- AquaSense problem and solution overview.
- Guppy-selection rationale.
- Individual component: Smart appetite-based feeding system.
- Original technology plan: YOLOv8/v11, ByteTrack, OpenCV/Python, Random Forest, Raspberry Pi, servo, Flutter/React Native, Spring Boot, Firebase.
- Original validation concept: record pre-feeding behaviour, predict appetite, give standard feed portion, observe actual feeding response, compare prediction with actual response.

## Individual Proposal Report

**File:** `IT23158986_v5.pdf`

Important source areas:

- introduction and problem context,
- literature review and research gap,
- objectives,
- design/development methodology,
- self-collected guppy video dataset,
- behavioural features,
- original camera and feeding protocol,
- YOLOv8n edge strategy,
- baseline and evaluation metrics,
- session-isolated data splitting,
- complete component architecture,
- functional/non-functional requirements,
- commercialization/budget,
- WBS and Gantt chart.

## Working Research Plan

**File:** `Guppy Feeding Research Plan.txt`

Important current working decisions:

- train detector before final appetite classifier,
- one detector class: `guppy`,
- frame extraction instead of annotating all video frames,
- session-isolated split,
- YOLOv8n → ByteTrack → features → Random Forest pipeline,
- PRE video as the main appetite-model input,
- need more independent sessions before claiming High/Low classifier performance.

## Research Data Workbook

**File:** `guppy_research_data_collection_template.xlsx`

Contains working sheets for:

- Session Log,
- Video Log,
- Feeding Response,
- Segment Labels,
- Model Experiments.

The daily manual logging process has been simplified in this specification to reduce unnecessary overhead.

---

# 44. Final Research Pipeline

```text
REAL GUPPY TANK
      ↓
Fixed iPhone 12 front/side video
      ↓
PRE / FEED / POST session videos
      ↓
Frame extraction + fixed ROI crop
      ↓
CVAT annotations (guppy only)
      ↓
YOLOv8n guppy detector
      ↓
ByteTrack
      ↓
Normalized trajectories
      ↓
30-second PRE windows
      ↓
Behavioural features
(speed, upper zone, feeding zone, spacing, direction changes)
      ↓
Validated feeding-motivation labels
      ↓
Random Forest
      ↓
High / Low feeding motivation
      ↓
Safety-aware feeding decision
      ↓
Servo feeder command
      ↓
Spring Boot backend
      ↓
Database / history
      ↓
Flutter application
```

---

# 45. Core Rule for the Research

The project should not be judged by how many AI models or app screens are built.

The core research contribution is:

> **A reproducible experiment showing whether measurable pre-feeding guppy behaviour can support an explainable feeding-motivation classification and safe demand-based feeding decision.**

Every design choice—video collection, annotation, tracking, feature extraction, model training, feeder control, and application design—should support that question.
