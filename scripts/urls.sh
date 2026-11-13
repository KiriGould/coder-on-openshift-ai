#!/usr/bin/env bash
#
# Print every URL in this quickstart, read from the cluster -- including the
# exact values to paste into Coder's admin forms (QUICKSTART step 6).
#
#   ./scripts/urls.sh
#
# Safe to run at any point: parts that aren't deployed yet say so.

set -uo pipefail

MODEL_NS=llm MODEL=qwen25-14b SERVED=qwen2.5-14b
MCP_NS=mcp-servers
CODER_NS=coder
DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}' 2>/dev/null)

ok()   { printf '  \033[32m✓\033[0m %-24s %s\n' "$1" "$2"; }
todo() { printf '  \033[33m·\033[0m %-24s %s\n' "$1" "$2"; }

echo
echo "Open in your browser:"
host=$(oc get route coder -n "$CODER_NS" -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$host" ]; then ok "Coder" "https://$host"; else todo "Coder" "not deployed yet -> step 4"; fi

echo
echo "OpenShift AI endpoints (Coder calls these; you paste them, not open them):"
ready=$(oc get llminferenceservice "$MODEL" -n "$MODEL_NS" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ -n "$ready" ]; then
  model_url="https://maas.${DOMAIN}/${MODEL_NS}/${MODEL}/v1"
  ok "Model via MaaS (6a)" "$model_url   Ready=${ready}"
else
  todo "Model via MaaS (6a)" "not deployed -> step 2, or use your own OpenAI-compatible endpoint (Appendix A)"
fi

gw=$(oc get route mcp -n gateway-system -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$gw" ]; then
  mcp_url="https://$gw/mcp"
  ok "MCP gateway (6b)" "$mcp_url"
elif oc get svc weather-mcp -n "$MCP_NS" >/dev/null 2>&1; then
  mcp_url="http://weather-mcp.${MCP_NS}.svc.cluster.local:8080/mcp"
  ok "MCP server, direct (6b)" "$mcp_url   (no gateway; DIRECT=1 mode)"
else
  todo "MCP gateway (6b)" "not deployed yet -> step 3"
fi

echo
echo "Coder form values:"
echo "  Admin settings -> AI -> Providers -> Add"
echo "      Type: OpenAI Compatible   Name: openshift-ai-maas"
if [ -n "${model_url:-}" ]; then
  echo "      Base URL: ${model_url}"
  echo "      API key:  output of ./scripts/maas-key.sh"
else
  echo "      Base URL: your endpoint, ending in /v1 (e.g. a LiteLLM proxy)   API key: its key"
fi
echo "  Admin settings -> AI -> Models -> Add"
if [ -n "${model_url:-}" ]; then echo "      Model: ${SERVED}   (mark as default)"
else echo "      Model: your endpoint's model name (must support tool calling)"; fi
echo "  Admin settings -> AI -> Coder Agents -> MCP servers -> Add"
echo "      Name: Weather   Transport: streamable_http   Auth: None   Availability: force_on"
echo "      URL: ${mcp_url:-<run again after step 3>}"
echo
