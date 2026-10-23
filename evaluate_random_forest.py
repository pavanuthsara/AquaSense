"""Evaluate appetite classification using held-out sessions, and save evidence.

Default: refit the live PRE training recipe in leave-one-session-out CV.
Optional --kind session-v3 evaluates the retrospective PRE/FEED/POST recipe.
--mode held-out scores a saved live model only on demonstrably new sessions.
"""

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.base import clone
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import accuracy_score, balanced_accuracy_score, classification_report, confusion_matrix
from sklearn.model_selection import LeaveOneGroupOut
from sklearn.pipeline import make_pipeline

from live_behavior import FEATURE_COLUMNS, MODEL_FORMAT, feature_frame
from train_live_rf import build_pipeline, prepare_training_data, validate_cv_sessions


LABELS = ["HIGH", "LOW"]


def prepare_session_v3(raw):
    metrics = ["avg_speed_norm_per_sec", "upper_zone_pct", "feeding_zone_pct", "mean_group_distance_norm"]
    required = ["session_id", "phase", "appetite_label", "latency_first_response_sec"] + metrics
    missing = set(required) - set(raw.columns)
    if missing:
        raise ValueError(f"Missing columns for session-v3: {sorted(missing)}")
    df = raw.dropna(subset=["session_id"]).copy()
    df["session_id"] = df["session_id"].astype(str).str.strip()
    df["phase"] = df["phase"].astype("string").str.strip().str.upper()
    df["appetite_label"] = df["appetite_label"].astype("string").str.strip().str.upper()
    df = df[df["appetite_label"].isin(LABELS) & (df["session_id"] != "")]
    for name in metrics + ["latency_first_response_sec"]:
        df[name] = pd.to_numeric(df[name], errors="coerce").replace([np.inf, -np.inf], np.nan)
    rows = []
    for session, group in df.groupby("session_id"):
        if group["appetite_label"].nunique() != 1:
            raise ValueError(f"Conflicting appetite labels in session {session}")
        if not {"PRE", "FEED", "POST"}.issubset(set(group["phase"])):
            raise ValueError(f"Session-v3 needs PRE, FEED, POST for session {session}; do not pad future phases.")
        row = {"session_id": session, "appetite_label": group["appetite_label"].iloc[0]}
        row["latency_first_response_sec"] = group["latency_first_response_sec"].median()
        for phase in ("PRE", "FEED", "POST"):
            for metric in metrics:
                row[f"{phase}_{metric}"] = group.loc[group["phase"] == phase, metric].mean()
        rows.append(row)
    if not rows:
        raise ValueError("No labeled complete sessions found.")
    data = pd.DataFrame(rows)
    columns = [name for name in data.columns if name not in ("session_id", "appetite_label")]
    # Original v3 uses constant zero imputation, not a globally learned median.
    model = make_pipeline(SimpleImputer(strategy="constant", fill_value=0, keep_empty_features=True),
                          RandomForestClassifier(n_estimators=50, max_depth=2, class_weight="balanced", random_state=42))
    return data, data[columns], model


def prediction_rows(model, X, data, fold, baseline_label):
    probabilities = model.predict_proba(X)
    index = {str(label): i for i, label in enumerate(model.classes_)}
    predicted = model.classes_[probabilities.argmax(axis=1)]
    result = pd.DataFrame({
        "session_id": data["session_id"].to_numpy(),
        "true_label": data["appetite_label"].to_numpy(),
        "predicted_label": predicted,
        "p_HIGH": probabilities[:, index["HIGH"]],
        "p_LOW": probabilities[:, index["LOW"]],
        "baseline_label": baseline_label,
        "fold": fold,
    })
    for name in ("source_row", "segment_id", "phase", "start_sec", "end_sec"):
        if name in data:
            result[name] = data[name].to_numpy()
    return result


def aggregate_sessions(predictions):
    rows = []
    for session, group in predictions.groupby("session_id"):
        p_high, p_low = group[["p_HIGH", "p_LOW"]].mean()
        rows.append({
            "session_id": session, "true_label": group["true_label"].iloc[0],
            "predicted_label": "HIGH" if p_high >= p_low else "LOW",
            "p_HIGH": p_high, "p_LOW": p_low,
            "baseline_label": group["baseline_label"].iloc[0],
            "fold": int(group["fold"].iloc[0]), "n_windows": len(group),
        })
    return pd.DataFrame(rows)


def classification_metrics(predictions, column="predicted_label"):
    actual, predicted = predictions["true_label"], predictions[column]
    report = classification_report(actual, predicted, labels=LABELS, output_dict=True, zero_division=0)
    return {
        "accuracy": float(accuracy_score(actual, predicted)),
        "balanced_accuracy": float(balanced_accuracy_score(actual, predicted)) if actual.nunique() == 2 else None,
        "macro_f1": report["macro avg"]["f1-score"],
        "per_class": {label: report[label] for label in LABELS},
        "confusion_matrix": confusion_matrix(actual, predicted, labels=LABELS).tolist(),
        "matrix_order": LABELS,
    }


def cross_validate(data, X, pipeline):
    validate_cv_sessions(data)
    splits, predictions, importances = [], [], []
    for fold, (train, test) in enumerate(LeaveOneGroupOut().split(X, data["appetite_label"], data["session_id"]), 1):
        train_ids = sorted(data.iloc[train]["session_id"].unique().tolist())
        test_ids = sorted(data.iloc[test]["session_id"].unique().tolist())
        assert set(train_ids).isdisjoint(test_ids)
        model = clone(pipeline).fit(X.iloc[train], data.iloc[train]["appetite_label"])
        # Same window-level majority baseline for each held-out session.
        dummy = DummyClassifier(strategy="most_frequent").fit(X.iloc[train], data.iloc[train]["appetite_label"])
        baseline = str(dummy.predict(X.iloc[test[:1]])[0])
        predictions.append(prediction_rows(model, X.iloc[test], data.iloc[test], fold, baseline))
        splits.append({"fold": fold, "train_sessions": train_ids, "test_sessions": test_ids,
                       "train_rows": len(train), "test_rows": len(test)})
        importances.append(model[-1].feature_importances_)
        print(f"Fold {fold}: held out {test_ids[0]} ({len(test)} rows)")
    importance = pd.DataFrame({"feature": X.columns, "mean_importance": np.mean(importances, axis=0),
                               "std_importance": np.std(importances, axis=0)})
    return pd.concat(predictions, ignore_index=True), splits, importance.sort_values("mean_importance", ascending=False)


def evaluate_saved_model(bundle, data, X):
    if bundle.get("format") != MODEL_FORMAT or bundle.get("feature_columns") != FEATURE_COLUMNS:
        raise ValueError("Use a live PRE bundle exported by train_live_rf.py.")
    trained = bundle.get("training_session_ids")
    if not trained:
        raise ValueError("This older bundle has no training session IDs. Re-export with train_live_rf.py before testing NEW sessions.")
    overlap = set(trained) & set(data["session_id"])
    if overlap:
        raise ValueError(f"Test sessions overlap training: {sorted(overlap)}. Use --mode cv for the current training CSV.")
    model = bundle["model"]
    if set(model.classes_) != set(LABELS):
        raise ValueError("Saved model must contain both HIGH and LOW classes.")
    predictions = prediction_rows(model, X, data, 1, "")
    return predictions, [{"fold": 1, "train_sessions": trained,
                          "test_sessions": sorted(data["session_id"].unique().tolist()),
                          "train_rows": None, "test_rows": len(data)}], None


def save_outputs(output, predictions, splits, importance, metadata, kind, include_baseline):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from sklearn.metrics import ConfusionMatrixDisplay

    sessions = aggregate_sessions(predictions)
    levels = {"segment": predictions, "session": sessions} if kind == "live-pre" else {"session": sessions}
    summary = {"metadata": metadata, "evaluation": {}, "splits": splits}
    report_lines = ["Random Forest appetite evaluation", json.dumps(metadata, indent=2)]
    fig, axes = plt.subplots(1, len(levels), figsize=(6 * len(levels), 5), squeeze=False)
    for axis, (level, rows) in zip(axes[0], levels.items()):
        metrics = classification_metrics(rows)
        summary["evaluation"][level] = metrics
        if include_baseline:
            metrics["majority_baseline"] = classification_metrics(rows, "baseline_label")
        matrix = pd.DataFrame(metrics["confusion_matrix"], index=LABELS, columns=LABELS)
        matrix.index.name = "actual / predicted"
        matrix.to_csv(output / f"{level}_confusion_matrix.csv")
        ConfusionMatrixDisplay(matrix.to_numpy(), display_labels=LABELS).plot(ax=axis, colorbar=False, cmap="Blues")
        axis.set_title(f"Held-out {level} predictions")
        report_lines += [f"\n{level.upper()} RESULTS", classification_report(rows["true_label"], rows["predicted_label"], labels=LABELS, zero_division=0)]
    fig.tight_layout()
    fig.savefig(output / "confusion_matrices.png", dpi=180)
    plt.close(fig)
    predictions.to_csv(output / ("segment_predictions.csv" if kind == "live-pre" else "predictions.csv"), index=False)
    sessions.to_csv(output / "session_predictions.csv", index=False)
    fold_rows = []
    for fold, group in predictions.groupby("fold"):
        metrics = classification_metrics(group)
        fold_rows.append({"fold": fold, "test_session": group["session_id"].iloc[0], "test_rows": len(group),
                          "accuracy": metrics["accuracy"], "macro_f1": metrics["macro_f1"]})
    pd.DataFrame(fold_rows).to_csv(output / "fold_metrics.csv", index=False)
    if importance is not None:
        importance.to_csv(output / "feature_importances.csv", index=False)
        fig, ax = plt.subplots(figsize=(9, max(3, len(importance) * 0.35)))
        ordered = importance.iloc[::-1]
        ax.barh(ordered["feature"], ordered["mean_importance"], xerr=ordered["std_importance"])
        ax.set_xlabel("Mean impurity importance across training folds (not causal effects)")
        fig.tight_layout()
        fig.savefig(output / "feature_importances.png", dpi=180)
        plt.close(fig)
    (output / "summary.json").write_text(json.dumps(summary, indent=2, allow_nan=False), encoding="utf-8")
    (output / "classification_report.txt").write_text("\n".join(report_lines), encoding="utf-8")
    (output / "methodology.md").write_text(
        "# Evaluation method\n\n" + metadata["protocol"] + "\n\n"
        "Confusion-matrix rows are actual classes; columns are predicted classes. "
        "All rates are fractions from 0 to 1. No deployment model is overwritten. "
        "Session predictions average held-out window probabilities; segment scores "
        "are more relevant to the live 10-second app check. More windows do not create "
        "more independent experimental sessions. A majority-class baseline is reported for CV. "
        "Hyperparameters must be fixed before evaluation; CV used repeatedly to tune "
        "the model is not an untouched final test.\n\n"
        "References: https://scikit-learn.org/stable/modules/cross_validation.html and "
        "https://scikit-learn.org/stable/common_pitfalls.html\n", encoding="utf-8")
    session_metrics = summary["evaluation"]["session"]
    print(f"\nSession accuracy: {session_metrics['accuracy']:.1%}")
    print(f"Session macro F1: {session_metrics['macro_f1']:.3f}")
    print("Session confusion matrix [HIGH, LOW]:", session_metrics["confusion_matrix"])
    if include_baseline:
        print(f"Majority baseline session accuracy: {session_metrics['majority_baseline']['accuracy']:.1%}")


def main():
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--features", type=Path, default=root / "output/poc_features.csv")
    parser.add_argument("--kind", choices=("live-pre", "session-v3"), default="live-pre")
    parser.add_argument("--mode", choices=("cv", "held-out"), default="cv")
    parser.add_argument("--model", type=Path, help="Saved live PRE bundle; required only for --mode held-out")
    parser.add_argument("--output", type=Path, help="New/empty output directory")
    args = parser.parse_args()
    if args.mode == "held-out" and (args.kind != "live-pre" or args.model is None):
        parser.error("--mode held-out requires --kind live-pre and --model")
    if args.mode == "cv" and args.model is not None:
        parser.error("CV refits the training recipe in each fold; omit --model or use --mode held-out")
    try:
        raw = pd.read_csv(args.features)
        raw["source_row"] = np.arange(len(raw)) + 2
        if args.kind == "live-pre":
            data = prepare_training_data(raw)
            X = feature_frame(data.to_dict("records"))
            pipeline = build_pipeline()
        else:
            data, X, pipeline = prepare_session_v3(raw)
        if args.mode == "cv":
            predictions, splits, importance = cross_validate(data, X, pipeline)
        else:
            bundle = joblib.load(args.model)
            predictions, splits, importance = evaluate_saved_model(bundle, data, X)
        output = args.output or root / "output/evaluation/random_forest" / (
            args.kind + "_" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ"))
        if output.exists() and any(output.iterdir()):
            raise ValueError("Output directory is not empty. Choose another --output to preserve previous results.")
        output.mkdir(parents=True, exist_ok=True)
        protocol = (
            "Leave-one-session-out cross-validation. The RF and imputer are refitted "
            "using only training sessions in every fold; no session spans train and test."
            if args.mode == "cv" else
            "Saved-model evaluation on explicitly new session IDs, checked against model training provenance."
        )
        if args.kind == "session-v3":
            protocol += " Retrospective session-v3 includes FEED, POST and response latency; it cannot validate before-feeding predictions."
        metadata = {
            "created_at": datetime.now(timezone.utc).isoformat(), "kind": args.kind, "mode": args.mode,
            "protocol": protocol, "feature_file": str(args.features.resolve()),
            "feature_sha256": hashlib.sha256(args.features.read_bytes()).hexdigest(),
            "input_rows": len(raw), "evaluated_rows": len(data), "sessions": data["session_id"].nunique(),
            "session_class_counts": data.groupby("session_id")["appetite_label"].first().value_counts().to_dict(),
            "features": list(X.columns), "sklearn_version": sklearn.__version__,
            "random_forest_parameters": pipeline[-1].get_params(),
            "numpy_version": np.__version__, "small_dataset_warning": "Results are preliminary; report independent session counts and Low-class recall.",
        }
        if args.model is not None:
            metadata["model_sha256"] = hashlib.sha256(args.model.read_bytes()).hexdigest()
            metadata["random_forest_parameters"] = bundle["model"][-1].get_params()
        save_outputs(output, predictions, splits, importance, metadata, args.kind, args.mode == "cv")
        print(f"Saved evaluation evidence: {output}")
    except (OSError, ValueError, KeyError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
