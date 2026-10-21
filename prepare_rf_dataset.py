
import pandas as pd

# Behavioural features from PRE videos
features = pd.read_csv("output/behavior_features.csv")

# Manually checked appetite labels
labels = pd.read_csv("data_collection/session_labels.csv")

# Keep only the first 3 minutes
features = features[features["start_sec"] < 180]

# Numerical features
feature_columns = [
    "avg_speed_norm_per_sec",
    "upper_zone_pct",
    "mean_group_distance_norm",
    "direction_change_fraction"
]

# Create one row per feeding session
session_features = (
    features.groupby("session_id")[feature_columns]
    .mean()
    .reset_index()
)

# Add manually assigned appetite labels
dataset = session_features.merge(
    labels[["session_id", "appetite_label"]],
    on="session_id",
    how="left",
    validate="one_to_one"
)

# Save the combined dataset
dataset.to_csv(
    "output/random_forest_dataset.csv",
    index=False
)

print(dataset)

print("\nAppetite class counts:")
print(dataset["appetite_label"].value_counts(dropna=False))

if dataset["appetite_label"].dropna().nunique() < 2:
    print("\nOnly one appetite class is available.")
    print("Collect more labelled sessions before training Random Forest.")
