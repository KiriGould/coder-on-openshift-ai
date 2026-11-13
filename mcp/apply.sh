#!/usr/bin/env bash
#
# Build and deploy the weather MCP server, then put it behind the MCP gateway.
#
#   ./apply.sh              server + MCP gateway + registration + Route (QUICKSTART step 3)
#   DIRECT=1 ./apply.sh     server only; Coder calls its Service directly
#                           (Appendix: clusters without Connectivity Link)
#
# Idempotent: safe to re-run; a re-run rebuilds the image and rolls it out.

set -euo pipefail
cd "$(dirname "$0")"

NS=mcp-servers

if [ -z "${DIRECT:-}" ]; then
  # Fail early and clearly: without the operator, every apply below errors
  # with "no matches for kind" and it is not obvious why.
  if ! oc api-resources --api-group=mcp.kuadrant.io -o name | grep -q mcpgatewayextensions; then
    echo "MCP gateway CRDs (mcp.kuadrant.io) not found." >&2
    echo "Install Red Hat Connectivity Link 1.5+: oc apply -f mcp/00-rhcl-operator.yaml" >&2
    echo "(the MaaS setup installs it too), or run DIRECT=1 $0." >&2
    exit 1
  fi
fi

echo "==> weather mcp server"
oc apply -f 02-weather-mcp.yaml
# Binary build from mcp/weather/: no registry credentials, no CI needed.
oc get bc/weather-mcp -n "$NS" >/dev/null 2>&1 || {
  oc new-build --name=weather-mcp --binary --strategy=docker -n "$NS"
  oc patch bc/weather-mcp -n "$NS" --type=merge \
    -p '{"spec":{"strategy":{"dockerStrategy":{"dockerfilePath":"Containerfile"}}}}'
}
oc start-build weather-mcp --from-dir=weather --follow -n "$NS"
# Picks up a rebuilt :latest on re-runs (and recovers the first rollout,
# which starts before the image exists).
oc rollout restart deploy/weather-mcp -n "$NS"
oc rollout status deploy/weather-mcp -n "$NS" --timeout=180s

if [ -n "${DIRECT:-}" ]; then
  echo
  echo "    MCP endpoint for Coder (direct, in-cluster):"
  echo "      http://weather-mcp.${NS}.svc.cluster.local:8080/mcp"
  echo
  exit 0
fi

# ---- MCP gateway (mcp-gateway-guide phases 2-4, Track B) -------------------
DOMAIN="${DOMAIN:-$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')}"
[ -n "$DOMAIN" ] || { echo "could not read the ingress domain; set DOMAIN=" >&2; exit 1; }
MCP_HOSTNAME="mcp.${DOMAIN}"
# Use the Gateway API class the cluster already has: openshift-default (MaaS
# setups) or data-science-gateway-class (created by OpenShift AI).
if [ -z "${GATEWAY_CLASS:-}" ]; then
  for c in openshift-default data-science-gateway-class; do
    oc get gatewayclass "$c" >/dev/null 2>&1 && { GATEWAY_CLASS=$c; break; }
  done
fi
[ -n "${GATEWAY_CLASS:-}" ] || { echo "no GatewayClass found (oc get gatewayclass); set GATEWAY_CLASS=" >&2; exit 1; }
echo "==> using GatewayClass ${GATEWAY_CLASS}"
render() { sed -e "s|MCP_HOSTNAME|${MCP_HOSTNAME}|g" -e "s|GATEWAY_CLASS|${GATEWAY_CLASS}|g" "$1"; }

echo "==> gateway"
render 01-gateway.yaml | oc apply -f -
oc wait gateway/mcp-gateway -n gateway-system --for=condition=Programmed --timeout=180s

echo "==> registration"
oc apply -f 03-gateway-registration.yaml

echo "==> route"
render 04-gateway-route.yaml | oc apply -f -

echo "==> waiting for the registration"
oc wait mcpserverregistration/weather-mcp -n "$NS" --for=condition=Ready --timeout=180s || true

echo
echo "    MCP endpoint for Coder:  https://${MCP_HOSTNAME}/mcp"
echo
echo "    oc get mcpgatewayextension -n mcp-system    # READY True"
echo "    oc get mcpsr -n ${NS}                  # weather-mcp READY True"
echo "    ./scripts/mcp-check.sh                    # tools/list + a real tools/call"
echo
