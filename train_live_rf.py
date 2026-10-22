"""Evaluate and export a PRE-only, 10-second appetite classifier for live use."""

import argparse
from pathlib import Path

import joblib
import pandas as pd
import sklearn
from sklearn.base import clone
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import balanced_accuracy_score, classification_report
from sklearn.model_selection import LeaveOneGroupOut
from sklearn.pipeline import make_pipeline

from live_behavior import (
    FEATURE_COLUMNS, MODEL_FORMAT, PROCESS_FPS, SEGMENT_SECONDS,
    feature_frame, has_track_data,
)


def main():
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--features", type=Path, default=root / "output/poc_features.csv")
    parser.add_argument("--output", type=Path, default=root / "models/random_forest_live_pre.joblib")
    args = parser.parse_args()

    df = pd.read_csv(args.features)
    required = FEATURE_COLUMNS + [
        "session_id", "phase", "appetite_label", "start_sec", "end_sec",
        "tracking_coverage_pct", "valid_speed_steps",
    ]
    missing = set(required) - set(df.columns)
    if missing:
        parser.error(f"Feature CSV is missing columns: {sorted(missing)}")
    df = df[df["phase"].str.strip().str.upper() == "PRE"].copy()
    df["appetite_label"] = df["appetite_label"].astype("string").str.strip().str.upper()
    df = df[df["appetite_label"].isin(["HIGH", "LOW"])].dropna(subset=["session_id"])
    df = df[(df["end_sec"] - df["start_sec"]) == SEGMENT_SECONDS]
    if df.empty:
        parser.error("No labeled PRE windows with the expected 10-second length were found.")
    df = df[df.apply(lambda row: has_track_data(row.to_dict()), axis=1)].reset_index(drop=True)
    session_labels = df.groupby("session_id")["appetite_label"].agg(["first", "nunique"])
    if (session_labels["nunique"] != 1).any():
        parser.error("Each session must have exactly one appetite label.")
    counts = session_labels["first"].value_counts()
    if set(counts.index) != {"HIGH", "LOW"} or counts.min() < 2:
        parser.error("Need at least two independent PRE sessions for each of HIGH and LOW.")

    X = feature_frame(df.to_dict("records"))
    y = df["appetite_label"]
    groups = df["session_id"]
    pipeline = make_pipeline(
        SimpleImputer(strategy="median", keep_empty_features=True),
        RandomForestClassifier(
            n_estimators=100, max_depth=3, min_samples_leaf=5,
            class_weight="balanced", random_state=42,
        ),
    )
    # Fit imputation inside each fold; never split segments of one session.
    predictions = pd.Series(index=df.index, dtype="object")
    session_predictions = []
    for train, test in LeaveOneGroupOut().split(X, y, groups):
        fold_model = clone(pipeline).fit(X.iloc[train], y.iloc[train])
        probabilities = fold_model.predict_proba(X.iloc[test])
        predictions.iloc[test] = fold_model.classes_[probabilities.argmax(axis=1)]
        session_prediction = fold_model.classes_[probabilities.mean(axis=0).argmax()]
        session_predictions.append((y.iloc[test[0]], session_prediction))
        print(f"Held out {groups.iloc[test[0]]}: true={y.iloc[test[0]]}, predicted={session_prediction}")

    print(f"\nPRE windows: {len(df)}; independent sessions: {len(session_labels)}")
    print("Session labels:", counts.to_dict())
    print("\nHeld-out segment performance:")
    print(classification_report(y, predictions, labels=["HIGH", "LOW"], zero_division=0))
    true_sessions, predicted_sessions = zip(*session_predictions)
    print("Held-out session performance (mean window probabilities):")
    print(classification_report(true_sessions, predicted_sessions, labels=["HIGH", "LOW"], zero_division=0))
    print(f"Session balanced accuracy: {balanced_accuracy_score(true_sessions, predicted_sessions):.1%}")
    print("Small research dataset: these estimates do not establish deployment accuracy.")

    pipeline.fit(X, y)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump({
        "format": MODEL_FORMAT,
        "model": pipeline,
        "feature_columns": FEATURE_COLUMNS,
        "segment_seconds": SEGMENT_SECONDS,
        "process_fps": PROCESS_FPS,
        "phase": "PRE",
        "sklearn_version": sklearn.__version__,
        "training_sessions": len(session_labels),
    }, args.output)
    print(f"Saved live model: {args.output}")


if __name__ == "__main__":
    main()
