
import pandas as pd
import joblib
from pathlib import Path
from sklearn.ensemble import RandomForestClassifier

# =====================================
# CONFIGURATION
# =====================================

FEATURES_FILE = "output/behavior_features.csv"
LABELS_FILE = "data_collection/session_labels.csv"

MODEL_DIR = Path("models")
MODEL_DIR.mkdir(parents=True, exist_ok=True)

# First experiment: predict feeding response
# Later change to "appetite_label" when
# reliable High and Low labels are available.
TARGET = "response_score"

FEATURE_COLUMNS = [
    "avg_speed_norm_per_sec",
    "upper_zone_pct",
    "mean_group_distance_norm",
    "direction_change_fraction"
]

# =====================================
# LOAD DATASETS
# =====================================

features = pd.read_csv(FEATURES_FILE)
labels = pd.read_csv(LABELS_FILE)

# Use only the first 180 seconds of PRE
features = features[features["start_sec"] < 180]

# One feature row per feeding session
session_features = (
    features.groupby("session_id")[FEATURE_COLUMNS]
    .mean()
    .reset_index()
)

# Ensure each session has only one label
if labels["session_id"].duplicated().any():
    raise ValueError("Duplicate session IDs in labels file")

# Join behaviour with actual feeding response
dataset = session_features.merge(
    labels[["session_id", TARGET]],
    on="session_id",
    how="left",
    validate="one_to_one"
)

# Remove uncertain or missing labels
dataset[TARGET] = dataset[TARGET].replace(
    {"Unknown": pd.NA, "": pd.NA}
)

dataset = dataset.dropna(
    subset=FEATURE_COLUMNS + [TARGET]
)

# Validate the recorded scores
if TARGET == "feeding_response_score":
    dataset[TARGET] = pd.to_numeric(
        dataset[TARGET],
        errors="raise"
    )

    if not dataset[TARGET].isin([0, 1, 2, 3]).all():
        raise ValueError("Scores must be 0, 1, 2 or 3")

    dataset[TARGET] = dataset[TARGET].astype(int)

print("\nDataset:")
print(dataset)

print("\nClass distribution:")
print(dataset[TARGET].value_counts())

# =====================================
# CHECK DATASET
# =====================================

if dataset.empty:
    raise SystemExit("No valid labelled data available")

if dataset[TARGET].nunique() < 2:
    raise SystemExit(
        "\nOnly one target class is available.\n"
        "Random Forest cannot learn class differences.\n"
        "Collect more varied feeding responses."
    )

if len(dataset) < 20:
    print(
        "\nWARNING: Very small dataset."
        "\nTraining is for a pipeline demonstration only."
        "\nDo not report training accuracy as test accuracy."
    )

# =====================================
# TRAIN RANDOM FOREST
# =====================================

X = dataset[FEATURE_COLUMNS]
y = dataset[TARGET]

model = RandomForestClassifier(
    n_estimators=100,
    max_depth=4,
    random_state=42,
    class_weight="balanced"
)

model.fit(X, y)

# =====================================
# SAVE MODEL
# =====================================

model_path = MODEL_DIR / "random_forest_v1.joblib"

joblib.dump(
    {
        "model": model,
        "feature_columns": FEATURE_COLUMNS,
        "target": TARGET
    },
    model_path
)

print("\nRandom Forest training completed!")
print(f"Saved model: {model_path}")

print("\nFeature importance:")

for feature, importance in zip(
    FEATURE_COLUMNS,
    model.feature_importances_
):
    print(f"{feature}: {importance:.4f}")

print(
    "\nThese are preliminary feature importances."
    "\nThey are not reliable with only five sessions."
)
