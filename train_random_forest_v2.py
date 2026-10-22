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

# Convert latency metric to float safely
df["latency_first_response_sec"] = pd.to_numeric(
    df["latency_first_response_sec"], errors="coerce"
)

# FIX 1: Mask latency for PRE phase
# Latency doesn't exist before food is dropped. Setting to 0.0 forces the model
# to evaluate computer vision metrics (speed, upper zone) during PRE anticipation.
df.loc[df["phase"] == "PRE", "latency_first_response_sec"] = 0.0

# 3. Define feature matrix X and target y
feature_cols = [
    "phase_encoded",
    "avg_speed_norm_per_sec",
    "upper_zone_pct",
    "feeding_zone_pct",
    "mean_group_distance_norm",
    "direction_change_fraction",
    "mean_visible_fish",
    "tracking_coverage_pct",
    "latency_first_response_sec",
]

X = df[feature_cols].copy()
X = X.apply(pd.to_numeric, errors="coerce")

# Impute missing values with column median
X = X.fillna(X.median())

y = df["target"]
groups = df["session_id"]

# 4. GroupKFold Cross-Validation (split strictly by session_id)
unique_sessions = df["session_id"].nunique()
gkf = GroupKFold(n_splits=unique_sessions)

y_true_all = []
y_pred_all = []
session_eval_results = []
feature_importances = np.zeros(len(feature_cols))

print(f"Starting Group Cross-Validation across {unique_sessions} sessions...\n")

for fold, (train_idx, test_idx) in enumerate(gkf.split(X, y, groups)):
    X_train, X_test = X.iloc[train_idx], X.iloc[test_idx]
    y_train, y_test = y.iloc[train_idx], y.iloc[test_idx]
    held_out_session = groups.iloc[test_idx].iloc[0]

    # FIX 2 & 3: Constrain trees and enforce class balancing
    rf = RandomForestClassifier(
        n_estimators=100,
        max_depth=3,             # Prevents trees from memorizing static session bounds
        min_samples_leaf=5,      # Forces generalization across multiple segments
        class_weight="balanced", # Heavily penalizes misclassifying the minority 'Low' class
        random_state=42
    )
    rf.fit(X_train, y_train)

    # Accumulate feature importances across cross-validation folds
    feature_importances += rf.feature_importances_ / unique_sessions

    # Segment-level predictions
    preds = rf.predict(X_test)
    probs = rf.predict_proba(X_test)
    acc = accuracy_score(y_test, preds)

    # FIX 4: Session-Level Probability Averaging
    # Average the predicted probabilities across all 10s segments in the held-out session
    target_class_idx = 1 if len(rf.classes_) > 1 else 0
    mean_prob = probs[:, target_class_idx].mean() if probs.shape[1] > 1 else probs.mean()
    session_true_label = y_test.iloc[0]
    session_pred_label = 1 if mean_prob >= 0.5 else 0

    session_true_str = label_encoder.inverse_transform([session_true_label])[0]
    session_pred_str = label_encoder.inverse_transform([session_pred_label])[0]

    print(f"Fold {fold+1} [Held-out: {held_out_session}]: "
          f"Segment Acc = {acc * 100:.1f}% | "
          f"Session True: {session_true_str} -> Pred: {session_pred_str}")

    y_true_all.extend(y_test)
    y_pred_all.extend(preds)
    session_eval_results.append((session_true_label, session_pred_label))

# 5. Segment-Level Performance Report
print("\n" + "=" * 50)
print("OVERALL SEGMENT-LEVEL PERFORMANCE")
print("=" * 50)
target_names = [str(c) for c in label_encoder.classes_]
print(classification_report(y_true_all, y_pred_all, target_names=target_names))

# 6. Session-Level Consensus Report
session_trues, session_preds = zip(*session_eval_results)
correct_sessions = sum(np.array(session_trues) == np.array(session_preds))
session_acc = correct_sessions / unique_sessions

print("=" * 50)
print(f"SESSION-LEVEL ACCURACY: {session_acc * 100:.1f}% ({correct_sessions}/{unique_sessions} Sessions Correct)")
print("=" * 50)

# 7. Feature Importance Ranking
print("=" * 50)
print("FEATURE IMPORTANCE RANKING")
print("=" * 50)
importance_df = pd.DataFrame({
    "Feature": feature_cols,
    "Importance": feature_importances
}).sort_values(by="Importance", ascending=False)

for _, row in importance_df.iterrows():
    print(f"{row['Feature']:<30} : {row['Importance'] * 100:.2f}%")