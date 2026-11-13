# Skeleton for notebooks/eda.py -- fill in CITIES and VARS, keep the sections.
# Build with: nb-build notebooks/eda.py

# %% [markdown]
# # Weather EDA: <cities>, monthly <start>–<end>

# %%
from pathlib import Path
import matplotlib.pyplot as plt
import pandas as pd

DATA = Path("../data")
CITIES = ["amsterdam", "madrid", "oslo"]          # file names in data/
VARS = ["temperature_mean", "precipitation"]      # columns in the CSV header
COLORS = dict(zip(CITIES, ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4"]))
plt.rcParams.update({"axes.spines.top": False, "axes.spines.right": False,
                     "axes.grid": True, "grid.color": "#e6e5e0", "lines.linewidth": 2})

# %% [markdown]
# ## 1. Load and validate against the checksum trailer

# %%
def load(city):
    path = DATA / f"{city}.csv"
    trailer = path.read_text().strip().splitlines()[-1].lstrip("# ").split()
    expected = dict(kv.split("=") for kv in trailer)
    df = pd.read_csv(path, comment="#")
    assert len(df) == int(expected["rows"]), f"{city}: wrong row count"
    for v in VARS:
        assert abs(df[v].sum() - float(expected[f"sum_{v}"])) < 0.15, f"{city}: {v} checksum"
    df["period"] = pd.to_datetime(df["period"])
    df["city"] = city
    return df

df = pd.concat([load(c) for c in CITIES], ignore_index=True)
df["month"] = df["period"].dt.month
print("checksums OK")

# %% [markdown]
# ## 2. Summary statistics

# %%
df.groupby("city")[VARS].agg(["mean", "min", "max", "std"]).round(1)

# %% [markdown]
# ## 3. Time series

# %%
fig, axes = plt.subplots(len(VARS), 1, figsize=(10, 3 * len(VARS)), sharex=True, squeeze=False)
for ax, v in zip(axes[:, 0], VARS):
    for c in CITIES:
        d = df[df.city == c]
        ax.plot(d.period, d[v], color=COLORS[c], label=c.title())
    ax.set_title(v, loc="left")
axes[0, 0].legend(frameon=False, ncols=len(CITIES))
fig.tight_layout()

# %% [markdown]
# ## 4. Seasonal profile
# TODO: mean per (city, month); one subplot per variable; ax.set_xticks(range(1, 13), list("JFMAMJJASOND"))

# %% [markdown]
# ## 5. Distributions
# TODO: hist(histtype="step") per city, same bins for every city

# %% [markdown]
# ## 6. Most unusual months
# TODO: anomaly = value - df.groupby(["city", "month"])[v].transform("mean"); top 5 by abs()

# %% [markdown]
# ## 7. Findings
# Computed and printed by code, never typed by hand.

# %%
means = df.groupby("city")[VARS[0]].mean()
years = df.period.dt.year.nunique()
print(f"- Warmest on average: {means.idxmax().title()} at {means.max():.1f} °C, "
      f"{means.max() - means.min():.1f} °C warmer than {means.idxmin().title()}")
# TODO: 2-4 more findings in the same style, e.g. precipitation per year
#       (df.groupby("city").precipitation.sum() / years), the most unusual month
