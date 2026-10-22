import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder
from sklearn.model_selection import LeaveOneOut
from sklearn.metrics import classification_report, accuracy_score

# 1. Load 10-second segment dataset
df = pd.read_csv("output/poc_features.csv")

# Ensure latency metric is numeric
df["latency_first_response_sec"] = pd.to_numeric(
    df["latency_first_response_sec"], errors="coerce"
)

# 2. Pivot & Aggregate Features by Session and Phase
# Computes mean speed, zone percentages, and group distance for PRE, FEED, and POST
metrics = ["avg_speed_norm_per_sec", "upper_zone_pct", "feeding_zone_pct", "mean_group_distance_norm"]

session_features = []

for session_id, group in df.groupby("session_id"):
    row = {"session_id": session_id}
    
    # Ground truth labels & latency (1 value per session)
    row["appetite_label"] = group["appetite_label"].iloc[0]
    row["latency_first_response_sec"] = group["latency_first_response_sec"].dropna().median() if not group["latency_first_response_sec"].dropna().empty else 0.0
    
    # Phase-specific feature aggregation
    for phase in ["PRE", "FEED", "POST"]:
        phase_data = group[group["phase"] == phase]
        for m in metrics:
            val = phase_data[m].mean() if not phase_data.empty else 0.0
            row[f"{phase}_{m}"] = val
            
    session_features.append(row)

sdf = pd.DataFrame(session_features)

# 3. Prepare Feature Matrix X and Target y
label_encoder = LabelEncoder()
y = label_encoder.fit_transform(sdf["appetite_label"].astype(str))

feature_cols = [c for c in sdf.columns if c not in ["session_id", "appetite_label"]]
X = sdf[feature_cols].fillna(0.0)

print(f"Aggregated dataset into {len(sdf)} session summary rows with {len(feature_cols)} phase features.\n")

# 4. Leave-One-Out Cross Validation (1 Session Held-Out per Fold)
loo = LeaveOneOut()

y_true = []
y_pred = []
importances = np.zeros(len(feature_cols))

for fold, (train_idx, test_idx) in enumerate(loo.split(X)):
    X_train, X_test = X.iloc[train_idx], X.iloc[test_idx]
    y_train, y_test = y[train_idx], y[test_idx]
    held_out_session = sdf["session_id"].iloc[test_idx[0]]

    rf = RandomForestClassifier(
        n_estimators=50,
        max_depth=2,               # Extremely shallow depth for 8-session PoC
        class_weight="balanced",   # Balance weight between High (6) and Low (2) sessions
        random_state=42
    )
    rf.fit(X_train, y_train)

    pred = rf.predict(X_test)[0]
    importances += rf.feature_importances_ / len(sdf)

    true_str = label_encoder.inverse_transform([y_test[0]])[0]
    pred_str = label_encoder.inverse_transform([pred])[0]

    print(f"Fold {fold+1} [Held-out: {held_out_session}]: True = {true_str:<4} | Pred = {pred_str:<4} "
          f"[{'CORRECT' if true_str == pred_str else 'WRONG'}]")

    y_true.append(y_test[0])
    y_pred.append(pred)

# 5. Session Evaluation Summary
acc = accuracy_score(y_true, y_pred)
print("\n" + "=" * 50)
print(f"OVERALL SESSION-LEVEL ACCURACY: {acc * 100:.1f}% ({sum(np.array(y_true) == np.array(y_pred))}/{len(sdf)})")
print("=" * 50)

target_names = [str(c) for c in label_encoder.classes_]
print(classification_report(y_true, y_pred, target_names=target_names))

# 6. Feature Importance Breakdown
print("=" * 50)
print("FEATURE IMPORTANCE RANKING (PHASE-AGGREGATED)")
print("=" * 50)
imp_df = pd.DataFrame({"Feature": feature_cols, "Importance": importances}).sort_values(by="Importance", ascending=False)

for _, row in imp_df.iterrows():
    print(f"{row['Feature']:<35} : {row['Importance'] * 100:.2f}%")