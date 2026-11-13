# Workspace: Python EDA notebooks

You work in `/home/coder/workspace`. The user views results in VS Code
(Jupyter extension), so finished work is an executed `.ipynb` there.

## Layout
- `data/`       raw data, e.g. `data/<city>.csv` (lower-case city name)
- `notebooks/`  notebook sources (`.py`) and built notebooks (`.ipynb`)

## Installed
Python 3.12 (`python3`), pandas, numpy, matplotlib, jupytext, nbconvert.
Don't `pip install` other libraries; there is no seaborn, plotly or statsmodels.

## Notebooks: never write .ipynb JSON by hand
1. Write `notebooks/<name>.py` as plain Python. Start each cell with
   `# %%`, or `# %% [markdown]` for a markdown cell (lines prefixed `# `).
2. Run `nb-build notebooks/<name>.py`. It creates `notebooks/<name>.ipynb`,
   executes it and saves the outputs. If it says FAILED, fix the `.py` and re-run.
3. Read data with paths relative to `notebooks/`: `../data/<city>.csv`.
4. Show charts with matplotlib in the cell (no `plt.savefig` needed, no `plt.show()` needed).

## Weather data
Weather comes from the weather MCP tools: `history`, `forecast`,
`current_weather` (named `weather_history` etc. when served through the MCP
gateway). Coder calls them for you; they are NOT reachable from this workspace, so don't
curl any weather API. Save a tool result to `data/` exactly as returned,
including the `#` comment lines. The last line is a checksum
(`# rows=<n> sum_<var>=<total>`): after saving, verify the row count and
sums with pandas (`pd.read_csv(path, comment="#")`) before analysing.

For an exploratory analysis notebook, use the `eda-notebook` skill.
