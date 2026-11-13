# The EDA notebook, cell by cell

The notebook the agent builds in step 7, written out so you can **copy and paste**
it yourself: to check the agent's numbers, to show the result before a live run, or
to build it without an agent. It's the tested reference notebook
(`analysis/eda.py`), with paths set for a Coder workspace.

## How to use it

1. Get the data into `~/workspace/data/` (the agent does this in step 7.3). Or copy
   the reference CSVs from this repo into the workspace:

   ```bash
   for c in amsterdam madrid oslo; do
     coder ssh <workspace> -- "mkdir -p ~/workspace/data && cat > ~/workspace/data/$c.csv" < analysis/data/$c.csv
   done
   ```

2. Open **VS Code (notebooks)** on the workspace. In the Explorer, right-click
   `notebooks` → **New File…** → `my-eda.ipynb`. VS Code opens it as a notebook.
3. Click **Select Kernel** (top right) → **Python 3.12**.
4. For each block below: **+ Code** (or **+ Markdown** for the headings), paste,
   then **Run All** at the end. Each code cell runs on its own once the cells above it
   have run.

No pandas or matplotlib install is needed: the workspace image has them.

---

**Markdown cell**

```markdown
# Weather EDA: Amsterdam, Madrid, Oslo (monthly, 2020–2024)

Monthly weather from the `weather_history` tool, saved in `../data/<city>.csv`.
```

**Code cell 1**

```python
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

DATA = Path("../data")      # the notebook lives in notebooks/, the CSVs in data/
CITIES = ["amsterdam", "madrid", "oslo"]
# Fixed categorical order: a city keeps its color in every chart.
COLORS = {"amsterdam": "#2a78d6", "madrid": "#eb6834", "oslo": "#1baf7a"}
INK, MUTED, GRID = "#1f1f1e", "#6b6a64", "#e6e5e0"
plt.rcParams.update({
    "figure.facecolor": "#fcfcfb", "axes.facecolor": "#fcfcfb",
    "axes.edgecolor": GRID, "axes.labelcolor": MUTED, "axes.titlecolor": INK,
    "xtick.color": MUTED, "ytick.color": MUTED, "axes.grid": True,
    "grid.color": GRID, "grid.linewidth": 0.6, "axes.spines.top": False,
    "axes.spines.right": False, "lines.linewidth": 2, "figure.dpi": 110,
})
```

**Markdown cell**

```markdown
## 1. Load and validate against the checksum trailer
The tool's last line is `# rows=<n> sum_<var>=<total>`. A mismatch means
rows were dropped or mangled while the CSV was copied into the file.
```

**Code cell 2**

```python
def load(city: str) -> pd.DataFrame:
    path = DATA / f"{city}.csv"
    trailer = path.read_text().strip().splitlines()[-1].lstrip("# ").split()
    expected = dict(kv.split("=") for kv in trailer)
    df = pd.read_csv(path, comment="#")
    assert len(df) == int(expected["rows"]), f"{city}: {len(df)} rows, expected {expected['rows']}"
    for col in df.columns[1:]:
        got, want = round(df[col].sum(), 1), float(expected[f"sum_{col}"])
        assert abs(got - want) < 0.15, f"{city}: sum_{col} {got} != {want}"
    df["period"] = pd.to_datetime(df["period"])
    df["city"] = city
    return df

df = pd.concat([load(c) for c in CITIES], ignore_index=True)
df["month"] = df["period"].dt.month
print("checksums OK:", {c: len(df[df.city == c]) for c in CITIES})
df.head()
```

**Markdown cell**

```markdown
## 2. Summary statistics
```

**Code cell 3**

```python
summary = df.groupby("city")[["temperature_mean", "precipitation"]].agg(["mean", "min", "max", "std"]).round(1)
summary
```

**Markdown cell**

```markdown
## 3. Time series
Two panels, one measure each (no dual axis).
```

**Code cell 4**

```python
fig, axes = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
for city in CITIES:
    d = df[df.city == city]
    axes[0].plot(d.period, d.temperature_mean, color=COLORS[city], label=city.title())
    axes[1].plot(d.period, d.precipitation, color=COLORS[city], label=city.title())
axes[0].set_title("Monthly mean temperature (°C)", loc="left")
axes[1].set_title("Monthly precipitation (mm)", loc="left")
axes[0].legend(frameon=False, ncols=3, loc="upper left")
fig.tight_layout()
```

**Markdown cell**

```markdown
## 4. Seasonal profile (month-of-year average)
```

**Code cell 5**

```python
season = df.groupby(["city", "month"])[["temperature_mean", "precipitation"]].mean()
fig, axes = plt.subplots(1, 2, figsize=(10, 3.8))
for city in CITIES:
    s = season.loc[city]
    axes[0].plot(s.index, s.temperature_mean, color=COLORS[city], marker="o", markersize=4, label=city.title())
    axes[1].plot(s.index, s.precipitation, color=COLORS[city], marker="o", markersize=4, label=city.title())
for ax, title in zip(axes, ["Temperature by month (°C)", "Precipitation by month (mm)"]):
    ax.set_title(title, loc="left")
    ax.set_xticks(range(1, 13), list("JFMAMJJASOND"))
axes[0].legend(frameon=False)
fig.tight_layout()
```

**Markdown cell**

```markdown
## 5. Distributions
```

**Code cell 6**

```python
fig, axes = plt.subplots(1, 2, figsize=(10, 3.6))
# Same bin edges for every city, so the steps line up and compare.
tbins = range(int(df.temperature_mean.min()) - 1, int(df.temperature_mean.max()) + 3, 2)
pbins = range(0, int(df.precipitation.max()) + 21, 20)
for city in CITIES:
    d = df[df.city == city]
    axes[0].hist(d.temperature_mean, bins=tbins, histtype="step", linewidth=2, color=COLORS[city], label=city.title())
    axes[1].hist(d.precipitation, bins=pbins, histtype="step", linewidth=2, color=COLORS[city], label=city.title())
axes[0].set_title("Monthly mean temperature (°C)", loc="left")
axes[1].set_title("Monthly precipitation (mm)", loc="left")
axes[0].set_ylabel("months")
axes[0].legend(frameon=False)
fig.tight_layout()
```

**Markdown cell**

```markdown
## 6. Most unusual months
Anomaly = a month's temperature minus that city's 5-year mean for the same calendar month.
```

**Code cell 7**

```python
df["temp_anomaly"] = df.temperature_mean - df.groupby(["city", "month"]).temperature_mean.transform("mean")
top = (df.assign(abs_anom=df.temp_anomaly.abs()).nlargest(5, "abs_anom")
         [["city", "period", "temperature_mean", "temp_anomaly"]].round(2))
top["period"] = top.period.dt.strftime("%Y-%m")
top
```

**Markdown cell**

```markdown
## 7. Findings
```

**Code cell 8**

```python
lines = [         "| City | Rows | Sum temp (trailer) | Mean °C | Coldest month | Warmest month | Wettest month | Total precip 2020–24 (mm) |",
         "|---|---|---|---|---|---|---|---|"]
names = dict(zip(range(1, 13), "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()))
for city in CITIES:
    d, s = df[df.city == city], season.loc[city]
    lines.append(f"| {city.title()} | {len(d)} | {d.temperature_mean.sum():.1f} | {d.temperature_mean.mean():.1f} "
                 f"| {names[s.temperature_mean.idxmin()]} {s.temperature_mean.min():.1f} °C "
                 f"| {names[s.temperature_mean.idxmax()]} {s.temperature_mean.max():.1f} °C "
                 f"| {names[s.precipitation.idxmax()]} {s.precipitation.max():.0f} mm | {d.precipitation.sum():.0f} |")
lines += ["", "Most unusual months (temperature vs. that city's 5-year mean for the month):", "",
          "| City | Month | °C | Anomaly °C |", "|---|---|---|---|"]
lines += [f"| {r.city.title()} | {r.period} | {r.temperature_mean:.2f} | {r.temp_anomaly:+.2f} |" for r in top.itertuples()]
print("\n".join(lines))
```

---

## What you should see

- Cell 1: nothing (setup).
- Cell 2: `checksums OK: {'amsterdam': 60, 'madrid': 60, 'oslo': 60}` and the first rows.
- Cells 3–6: a summary table, then three charts (time series, seasonal profile, distributions).
- Cell 7: the five most unusual months, Oslo January 2024 first (−7.89 °C, −5.28 °C).
- Cell 8: the findings table. It should match [results.md](results.md).

If cell 2 fails with an assertion, a CSV doesn't match its checksum line: re-fetch it.
