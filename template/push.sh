#!/usr/bin/env bash
#
# Push the "Python EDA Notebooks" template and set the metadata Coder Agents
# route on (QUICKSTART step 5). Needs `coder login` first.
#
#   ./template/push.sh
#
# Idempotent: each run creates a new template version.

set -euo pipefail
cd "$(dirname "$0")"

NAME="${NAME:-python-eda}"
# <=128 chars. Coder Agents pick a template from this + the top of README.md.
DESC="Python data analysis and EDA notebooks. VS Code + Jupyter, pandas, matplotlib. Use for weather/time series analysis."

coder whoami >/dev/null 2>&1 || { echo "not logged in: coder login https://coder.<domain>" >&2; exit 1; }
coder templates push "$NAME" -d . --yes
coder templates edit "$NAME" --display-name "Python EDA Notebooks" \
  --description "$DESC" --icon /icon/jupyter.svg --yes
coder templates list
