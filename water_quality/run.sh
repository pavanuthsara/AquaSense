#!/usr/bin/env bash
# Run the forecasting pipeline with the local venv.
# macOS: XGBoost needs libomp. If Homebrew's libomp is unavailable, fall back to
# the copy bundled inside scikit-learn's wheel.
set -euo pipefail
cd "$(dirname "$0")"
SKLEARN_DYLIBS=$(.venv/bin/python -c "import sklearn, os; print(os.path.join(os.path.dirname(sklearn.__file__), '.dylibs'))")
DYLD_FALLBACK_LIBRARY_PATH="$SKLEARN_DYLIBS" exec .venv/bin/python forecast.py "$@"
