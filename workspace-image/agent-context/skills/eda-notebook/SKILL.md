---
name: eda-notebook
description: Build an exploratory data analysis (EDA) Jupyter notebook from CSV time series in data/, e.g. weather data per city. Use when asked to explore, summarise, chart or build an EDA notebook or workbench.
---

# EDA notebook

Goal: an executed `notebooks/eda.ipynb` the user opens in VS Code.

## Steps
1. Make sure the data is in `data/` and passes its checksum (see AGENTS.md).
   If data is missing, fetch it with the weather `history` tool first; prefer
   `frequency: "monthly"` (daily data for years is over the row limit).
2. Read the skeleton: `read_skill_file("eda-notebook", "template.py")`.
3. Write `notebooks/eda.py` from it. Fill in `CITIES` and the variable
   names that are actually in the CSV header. Keep these sections, each a
   `# %% [markdown]` heading plus one `# %%` code cell:
   1. Load + validate checksums
   2. Summary statistics (`groupby("city").agg(["mean","min","max","std"])`)
   3. Time series, one panel per variable (never two y-axes on one chart)
   4. Seasonal profile: mean per calendar month, x ticks J..D
   5. Distributions: histograms with the same bins for every city
   6. Most unusual months: value minus that city's mean for the same calendar month; top 5 by absolute size
   7. Findings: a CODE cell that computes and prints each finding with an
      f-string (e.g. `print(f"Madrid is {diff:.1f} °C warmer than Oslo")`).
      Never type a number into markdown yourself: retyped numbers drift.
4. Run `nb-build notebooks/eda.py`. On FAILED, read the error, fix, re-run.
5. Reply with the notebook path and the findings, quoting the numbers exactly
   as section 7 printed them. Tell the user to open
   **VS Code (notebooks)** in the workspace and open `notebooks/eda.ipynb`.

## Style
- One color per city, the same in every chart (template's `COLORS`).
- Titles say the unit, e.g. "Monthly precipitation (mm)".
- Keep it short: no extra libraries, no models or forecasts unless asked.
- Units: say what a number is. A 5-year total is not "per year"; divide by 5.
