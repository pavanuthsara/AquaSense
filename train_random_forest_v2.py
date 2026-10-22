import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder
from sklearn.model_selection import GroupKFold
from sklearn.metrics import classification_report, accuracy_score

# 1. Load dataset containing features + labels
df = pd.read_csv("output/poc_features.csv")

# 2. Encode categorical features and target labels
phase_encoder = LabelEncoder()
df["phase_encoded"] = phase_encoder.fit_transform(df["phase"].astype(str))

label_encoder = LabelEncoder()
df["target"] = label_encoder.fit_transform(df["appetite_label"].astype(str))

# Convert latency metric to float (safely converting any missing/empty values to NaN)
df["latency_first_response_sec"] = pd.to_numeric(
    df["latency_first_response_sec"], errors="coerce"
)

# 3. Define feature columns (including latency_first_response_sec)
feature_cols = [
    "phase_encoded",
    "avg_speed_norm_per_sec",
    "upper_zone_pct",
    "feeding_zone_pct",
    "mean_group_distance_norm",
    "direction_change_fraction",
    "mean_visible_fish",
    "tracking_coverage_pct",
    "latency_first_response_sec",  # Newly added feeding latency feature
]

# Ensure numeric types and impute missing values (if any exist) with column median
X = df[feature_cols].copy()
X = X.apply(pd.to_numeric, errors="coerce")
X = X.fillna(X.median())

y = df["target"]
groups = df["session_id"]

# 4. GroupKFold Cross-Validation (split strictly by session_id)
unique_sessions = df["session_id"].nunique()
gkf = GroupKFold(n_splits=unique_sessions)

y_true_all = []
y_pred_all = []
feature_importances = np.zeros(len(feature_cols))

print(f"Starting Group Cross-Validation across {unique_sessions} sessions...\n")

for fold, (train_idx, test_idx) in enumerate(gkf.split(X, y, groups)):
    X_train, X_test = X.iloc[train_idx], X.iloc[test_idx]
    y_train, y_test = y.iloc[train_idx], y.iloc[test_idx]
    held_out_session = groups.iloc[test_idx].iloc[0]

    # Train Random Forest
    rf = RandomForestClassifier(
        n_estimators=100,
        max_depth=4,  # Shallow depth prevents overfitting on small PoC datasets
        random_state=42
    )
    rf.fit(X_train, y_train)

    # Accumulate feature importances across cross-validation folds
    feature_importances += rf.feature_importances_ / unique_sessions

    # Predict on unseen session
    preds = rf.predict(X_test)
    acc = accuracy_score(y_test, preds)
    print(f"Fold {fold+1} [Held-out: {held_out_session}]: Accuracy = {acc * 100:.1f}%")

    y_true_all.extend(y_test)
    y_pred_all.extend(preds)

# 5. Overall Performance Evaluation
print("\n" + "=" * 45)
print("OVERALL MODEL PERFORMANCE")
print("=" * 45)
target_names = [str(c) for c in label_encoder.classes_]
print(classification_report(y_true_all, y_pred_all, target_names=target_names))

# 6. Feature Importance Breakdown
print("=" * 45)
print("FEATURE IMPORTANCE RANKING")
print("=" * 45)
importance_df = pd.DataFrame({
    "Feature": feature_cols,
    "Importance": feature_importances
}).sort_values(by="Importance", ascending=False)

for _, row in importance_df.iterrows():
    print(f"{row['Feature']:<30} : {row['Importance'] * 100:.2f}%")
    