#!/usr/bin/env bash
#
# Capture the reference data exactly as the agent sees it: verbatim
# weather `history` tool results. Run the server first (QUICKSTART Appendix):
#   PORT=18080 python mcp/weather/server.py
#
#   ./analysis/capture.sh [MCP_URL]

set -euo pipefail
cd "$(dirname "$0")"
URL="${1:-http://localhost:18080/mcp}"
H=(-H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')

for city in Amsterdam Madrid Oslo; do
  f="data/$(echo "$city" | tr '[:upper:]' '[:lower:]').csv"
  curl -s "${H[@]}" "$URL" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{
    \"name\":\"history\",\"arguments\":{\"city\":\"${city}\",\"start_date\":\"2020-01-01\",
    \"end_date\":\"2024-12-31\",\"frequency\":\"monthly\",
    \"variables\":[\"temperature_mean\",\"precipitation\"]}}}" \
    | sed -n -e 's/^data: //p' -e t -e '/^{/p' | jq -jr '.result.content[0].text' > "$f"
  echo "$f: $(tail -1 "$f")"
done
