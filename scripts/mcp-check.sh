#!/usr/bin/env bash
#
# Prove the MCP gateway works end to end (QUICKSTART step 3):
# initialize -> tools/list -> a REAL tools/call.
#
#   ./scripts/mcp-check.sh                       # gateway: https://mcp.<domain>/mcp
#                                                # no gateway (DIRECT=1): port-forwards to the Service
#   MCP_URL=http://localhost:18080/mcp TOOL=current_weather ./scripts/mcp-check.sh
#
# tools/call matters: it is the only request the broker hair-pins back
# through the Gateway, so a wrong privateHost passes everything else.

set -euo pipefail

if [ -z "${MCP_URL:-}" ]; then
  if gw=$(oc get route mcp -n gateway-system -o jsonpath='{.spec.host}' 2>/dev/null) && [ -n "$gw" ]; then
    MCP_URL="https://${gw}/mcp"
  else
    # DIRECT=1 mode: the server is in-cluster only, so tunnel to its Service.
    oc port-forward -n mcp-servers svc/weather-mcp 18089:8080 >/dev/null 2>&1 &
    PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 3
    MCP_URL=http://localhost:18089/mcp
    TOOL="${TOOL:-current_weather}"      # no gateway, so no weather_ prefix
  fi
fi
TOOL="${TOOL:-weather_current_weather}"
H=(-H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')

# Responses may come back as SSE ("data: {...}"); keep just the JSON.
body() { sed -n -e 's/^data: //p' -e t -e '/^{/p'; }

echo "==> initialize   ${MCP_URL}"
hdrs=$(mktemp)
curl -sk -D "$hdrs" -o /dev/null "${H[@]}" "$MCP_URL" -d '{"jsonrpc":"2.0","id":1,"method":"initialize",
  "params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"mcp-check","version":"1"}}}'
SID=$(grep -i '^mcp-session-id:' "$hdrs" | tr -d '\r' | awk '{print $2}' || true)
[ -n "$SID" ] && H+=(-H "mcp-session-id: $SID") && echo "    session $SID"
curl -sk -o /dev/null "${H[@]}" "$MCP_URL" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'

echo "==> tools/list"
curl -sk "${H[@]}" "$MCP_URL" -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | body | jq -r '.result.tools[].name' | sed 's/^/    /'

echo "==> tools/call ${TOOL}(city=Amsterdam)"
out=$(curl -sk "${H[@]}" "$MCP_URL" -d "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",
  \"params\":{\"name\":\"${TOOL}\",\"arguments\":{\"city\":\"Amsterdam\"}}}" | body)
rm -f "$hdrs"
# A tool error comes back as a result with isError=true -- not a pass.
if echo "$out" | jq -e '(.result.isError // false) == false and .result.content[0].text' >/dev/null 2>&1; then
  echo "    $(echo "$out" | jq -r '.result.content[0].text')"
  echo "OK"
else
  echo "    $out" >&2
  echo "tools/call failed." >&2
  echo "  tools/list shows only discover_tools/select_tools -> the server speaks the 2026 protocol only; see QUICKSTART troubleshooting" >&2
  echo "  tools/list shows the weather_* tools -> check the extension's privateHost (mcp/01-gateway.yaml)" >&2
  exit 1
fi
