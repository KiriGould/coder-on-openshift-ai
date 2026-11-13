---
display_name: Python EDA Notebooks
description: Python data analysis and EDA notebooks. VS Code + Jupyter, pandas, matplotlib. Use for weather/time series analysis.
icon: /icon/jupyter.svg
---

# Python EDA Notebooks

**Choose this template for** exploratory data analysis of small CSV datasets
(for example weather time series fetched with the `weather_*` tools), charts,
summary statistics, and Jupyter notebooks the user opens in VS Code.

**Not for** web services, building container images, GPU/ML training or
large datasets (2 CPU / 4 GiB by default).

**Provides:** Python 3.12, pandas, numpy, matplotlib, a `python3` Jupyter
kernel, `nb-build` (turns a `# %%` .py file into an executed .ipynb), VS Code
in the browser with the Python and Jupyter extensions. No internet APIs are
needed: data arrives through Coder's MCP tools. All parameters have defaults.

The workspace ships an `AGENTS.md` (conventions: `data/`, `notebooks/`,
never hand-write .ipynb JSON) and an `eda-notebook` skill.

## For admins

Runs on OpenShift's `restricted-v2` SCC with an arbitrary UID; no
ServiceAccount token, no model URL or API key in the workspace. Image:
`workspace-image/` in the quickstart repo. Push with:

    coder templates push python-eda -d template --yes
    coder templates edit python-eda --display-name "Python EDA Notebooks" \
      --description "Python data analysis and EDA notebooks. VS Code + Jupyter, pandas, matplotlib. Use for weather/time series analysis." \
      --icon /icon/jupyter.svg
