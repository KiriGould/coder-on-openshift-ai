"""Weather MCP server backed by Open-Meteo (free, no API key).

Three tools:

  current_weather(city)                       now
  forecast(city, days)                        next 1-16 days
  history(city, start_date, end_date, ...)    past, as a compact CSV time series

`history` is what makes time series analysis possible. It returns CSV rather
than prose because the agent's next move is to save it to a file in the
workspace and load it with pandas -- and because every row costs prompt
tokens on a small, locally hosted model. Aggregation (daily -> monthly, ...)
happens here, server-side, so five years of monthly data is 60 rows (~600
tokens), not 1,800 daily ones.

The CSV ends with a `# rows=... sum=...` trailer. The agent copies the tool
result into a file token by token; the trailer lets it (or you) check that
the file it wrote is the data it was given.
"""

import csv
import io
import os
from collections import OrderedDict
from datetime import date, timedelta
from typing import Literal

import httpx
from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError

GEOCODE = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST = "https://api.open-meteo.com/v1/forecast"
ARCHIVE = "https://archive-api.open-meteo.com/v1/archive"

# The archive (ERA5 reanalysis) starts in 1940 and trails today by ~5 days.
ARCHIVE_START = date(1940, 1, 1)
ARCHIVE_LAG_DAYS = 6

# Above this, the tool refuses and asks the model to coarsen the frequency.
# Coder leaves ~9k prompt tokens on a 40k-context model, and the data passes
# through that budget twice: once as the tool result, once when the agent
# writes it to a file. 240 rows of one variable is ~1.5k tokens each way.
MAX_ROWS = int(os.environ.get("MAX_ROWS", "240"))

# Friendly name -> (Open-Meteo daily variable, how to aggregate, unit).
VARIABLES = {
    "temperature_mean": ("temperature_2m_mean", "mean", "°C"),
    "temperature_max": ("temperature_2m_max", "mean", "°C"),
    "temperature_min": ("temperature_2m_min", "mean", "°C"),
    "precipitation": ("precipitation_sum", "sum", "mm"),
    "wind_max": ("wind_speed_10m_max", "mean", "km/h"),
    "sunshine_hours": ("sunshine_duration", "sum_hours", "h"),
}

# WMO weather interpretation codes, as returned in `weather_code`.
WMO = {
    0: "clear sky", 1: "mainly clear", 2: "partly cloudy", 3: "overcast",
    45: "fog", 48: "freezing fog",
    51: "light drizzle", 53: "drizzle", 55: "heavy drizzle",
    56: "freezing drizzle", 57: "heavy freezing drizzle",
    61: "light rain", 63: "rain", 65: "heavy rain",
    66: "freezing rain", 67: "heavy freezing rain",
    71: "light snow", 73: "snow", 75: "heavy snow", 77: "snow grains",
    80: "light showers", 81: "showers", 82: "violent showers",
    85: "snow showers", 86: "heavy snow showers",
    95: "thunderstorm", 96: "thunderstorm with hail", 99: "severe thunderstorm with hail",
}

# Literal types become JSON-schema enums, so the model sees the valid values
# in the tool schema instead of having to guess them from the docstring.
Frequency = Literal["daily", "weekly", "monthly", "yearly"]
Variable = Literal["temperature_mean", "temperature_max", "temperature_min",
                   "precipitation", "wind_max", "sunshine_hours"]

mcp = MCPServer("weather")
http = httpx.Client(timeout=30)


def _get(url: str, params: dict) -> dict:
    try:
        r = http.get(url, params=params)
    except httpx.HTTPError as e:
        raise ToolError(f"weather service unreachable: {e}") from e
    if r.status_code != 200:
        # Open-Meteo explains bad requests in a `reason` field; pass it on so
        # the model can correct its own arguments.
        try:
            reason = r.json().get("reason", r.text)
        except ValueError:
            reason = r.text
        raise ToolError(f"weather service said: {reason}")
    return r.json()


def _locate(city: str) -> dict:
    hits = _get(GEOCODE, {"name": city, "count": 1}).get("results")
    if not hits:
        # ToolError, not ValueError: the SDK passes its message to the model,
        # which can then ask the user to clarify. Anything else reaches the
        # model as a bare "Error executing tool forecast".
        raise ToolError(f"no place called {city!r}")
    return hits[0]


def _where(p: dict) -> str:
    return ", ".join(x for x in (p["name"], p.get("admin1"), p.get("country")) if x)


def _date(s: str, name: str) -> date:
    try:
        return date.fromisoformat(s)
    except ValueError:
        raise ToolError(f"{name} must be YYYY-MM-DD, got {s!r}") from None


def _bucket(day: str, frequency: str) -> str:
    """The period a YYYY-MM-DD day belongs to, as a sortable label."""
    if frequency == "daily":
        return day
    if frequency == "monthly":
        return day[:7]
    if frequency == "yearly":
        return day[:4]
    # weekly: label by the Monday that starts the ISO week.
    d = date.fromisoformat(day)
    return (d - timedelta(days=d.weekday())).isoformat()


def _aggregate(values: list, how: str):
    present = [v for v in values if v is not None]
    if not present:
        return None
    if how == "mean":
        return round(sum(present) / len(present), 2)
    if how == "sum":
        return round(sum(present), 1)
    if how == "sum_hours":  # sunshine_duration arrives in seconds
        return round(sum(present) / 3600, 1)
    raise AssertionError(how)


@mcp.tool()
def current_weather(city: str) -> str:
    """Current temperature, conditions and wind for a city, e.g. "Amsterdam"."""
    p = _locate(city)
    c = _get(FORECAST, {
        "latitude": p["latitude"], "longitude": p["longitude"], "timezone": "auto",
        "current": "temperature_2m,apparent_temperature,weather_code,wind_speed_10m",
    })["current"]
    return (f"{_where(p)} at {c['time']}: {WMO.get(c['weather_code'], 'unknown')}, "
            f"{c['temperature_2m']}°C (feels like {c['apparent_temperature']}°C), "
            f"wind {c['wind_speed_10m']} km/h")


@mcp.tool()
def forecast(city: str, days: int = 7) -> str:
    """Daily forecast for a city as CSV: date, conditions, min/mean/max °C,
    precipitation (mm) and chance of rain (%). days is 1-16."""
    days = max(1, min(days, 16))
    p = _locate(city)
    d = _get(FORECAST, {
        "latitude": p["latitude"], "longitude": p["longitude"], "timezone": "auto",
        "forecast_days": days,
        "daily": "weather_code,temperature_2m_min,temperature_2m_mean,temperature_2m_max,"
                 "precipitation_sum,precipitation_probability_max",
    })["daily"]
    out = io.StringIO()
    out.write(f"# {_where(p)}, forecast\n")
    w = csv.writer(out, lineterminator="\n")
    w.writerow(["date", "conditions", "temperature_min", "temperature_mean",
                "temperature_max", "precipitation", "rain_chance"])
    for i, day in enumerate(d["time"]):
        w.writerow([day, WMO.get(d["weather_code"][i], "unknown"),
                    d["temperature_2m_min"][i], d["temperature_2m_mean"][i],
                    d["temperature_2m_max"][i], d["precipitation_sum"][i],
                    d["precipitation_probability_max"][i]])
    return out.getvalue()


@mcp.tool()
def history(city: str, start_date: str, end_date: str,
            frequency: Frequency = "monthly",
            variables: list[Variable] = ["temperature_mean"]) -> str:  # noqa: B006 (never mutated)
    """Historical weather for a city as a CSV time series, for analysis.

    start_date / end_date: YYYY-MM-DD, from 1940-01-01 up to about 6 days ago.
    frequency: daily | weekly | monthly | yearly. Values are aggregated from
      daily data: temperatures and wind are averaged, precipitation and
      sunshine are summed.
    variables: any of temperature_mean, temperature_max, temperature_min,
      precipitation, wind_max, sunshine_hours. Default: temperature_mean.

    Ask for as few variables and as coarse a frequency as the question needs;
    the result is row-limited, and the error says how to narrow the request. Save the CSV to a file before
    analysing it. The last line is a checksum: `# rows=<n> sum_<var>=<total>`.
    """
    # The SDK validates against the enums, but keep these checks: they turn
    # a schema error into a message the model can act on.
    variables = list(dict.fromkeys(variables)) or ["temperature_mean"]
    unknown = [v for v in variables if v not in VARIABLES]
    if unknown:
        raise ToolError(f"unknown variable(s) {unknown}; choose from {list(VARIABLES)}")
    if frequency not in ("daily", "weekly", "monthly", "yearly"):
        raise ToolError("frequency must be daily, weekly, monthly or yearly")

    start, end = _date(start_date, "start_date"), _date(end_date, "end_date")
    latest = date.today() - timedelta(days=ARCHIVE_LAG_DAYS)
    start, end = max(start, ARCHIVE_START), min(end, latest)
    if start > end:
        raise ToolError(f"no data in that range; the archive covers "
                        f"{ARCHIVE_START} to {latest}")

    # Refuse BEFORE calling upstream: cheaper, and the message tells the model
    # exactly how to fix the call.
    days = (end - start).days + 1
    rows = {"daily": days, "weekly": days / 7, "monthly": days / 30.44,
            "yearly": days / 365.25}[frequency]
    if rows > MAX_ROWS:
        raise ToolError(f"{frequency} data for {start}..{end} is ~{int(rows)} rows, "
                        f"over the {MAX_ROWS}-row limit; use a coarser frequency "
                        f"or a shorter range")

    p = _locate(city)
    daily = _get(ARCHIVE, {
        "latitude": p["latitude"], "longitude": p["longitude"], "timezone": "auto",
        "start_date": start.isoformat(), "end_date": end.isoformat(),
        "daily": ",".join(VARIABLES[v][0] for v in variables),
    })["daily"]

    buckets: "OrderedDict[str, dict[str, list]]" = OrderedDict()
    for i, day in enumerate(daily["time"]):
        b = buckets.setdefault(_bucket(day, frequency), {v: [] for v in variables})
        for v in variables:
            b[v].append(daily[VARIABLES[v][0]][i])

    out = io.StringIO()
    units = ", ".join(f"{v} {VARIABLES[v][2]}" for v in variables)
    out.write(f"# {_where(p)} ({p['latitude']:.2f}, {p['longitude']:.2f}), "
              f"{frequency}, {start}..{end}; units: {units}; source: Open-Meteo ERA5\n")
    w = csv.writer(out, lineterminator="\n")
    w.writerow(["period", *variables])
    sums = {v: 0.0 for v in variables}
    for period, vals in buckets.items():
        row = [_aggregate(vals[v], VARIABLES[v][1]) for v in variables]
        for v, x in zip(variables, row):
            sums[v] += x or 0
        w.writerow([period, *("" if x is None else x for x in row)])
    out.write(f"# rows={len(buckets)} "
              + " ".join(f"sum_{v}={sums[v]:.1f}" for v in variables) + "\n")
    return out.getvalue()


class ClassicProtocolOnly:
    """Refuse the 2026-07-28 protocol era; serve the classic one only.

    The SDK speaks both eras. The MCP gateway in Connectivity Link 1.5
    (mcp-gateway 1.0.2) negotiates the newest era with an upstream and then
    publishes its tools ONLY to clients on that era. Coder Agents (2.39) and
    most clients use the classic initialize-and-session protocol, so through
    the gateway they would see no weather tools at all -- only the gateway's
    discover_tools/select_tools. Answering 2026-era requests with
    "unsupported version" makes the gateway fall back to the classic
    protocol, and every client sees the tools.

    Set MCP_ALLOW_2026=1 to serve both eras again once the gateway and your
    clients handle the new one.
    """

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http":
            version = dict(scope["headers"]).get(b"mcp-protocol-version", b"").decode()
            if version >= "2026":
                body = (b'{"jsonrpc":"2.0","id":null,"error":{"code":-32602,'
                        b'"message":"unsupported protocol version ' + version.encode() +
                        b'; supported: 2025-11-25, 2025-06-18, 2025-03-26"}}')
                await send({"type": "http.response.start", "status": 400,
                            "headers": [(b"content-type", b"application/json")]})
                await send({"type": "http.response.body", "body": body})
                return
        await self.app(scope, receive, send)


if __name__ == "__main__":
    import uvicorn

    # Bind 0.0.0.0: the default 127.0.0.1 is unreachable from the Service,
    # and also switches on DNS-rebinding checks that reject the gateway's
    # Host header. Stateless: the gateway may send each call on a fresh
    # connection, and there is no per-session state worth keeping.
    app = mcp.streamable_http_app(stateless_http=True, host="0.0.0.0")
    if os.environ.get("MCP_ALLOW_2026") != "1":
        app = ClassicProtocolOnly(app)
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
