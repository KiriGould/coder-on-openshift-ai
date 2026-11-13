#!/usr/bin/env bash
#
# Mint a MaaS API key for Coder (QUICKSTART step 2/5a).
#
#   ./scripts/maas-key.sh            # 30-day key on the qwen25-14b-coder subscription
#   EXPIRES=2h ./scripts/maas-key.sh
#
# Trades your OpenShift login for a long-lived, revocable MaaS key that is
# bound to one subscription (and so to its token rate limit). Coder stores
# the key; the model never sees your OpenShift token.

set -euo pipefail

SUBSCRIPTION="${SUBSCRIPTION:-qwen25-14b-coder}"
EXPIRES="${EXPIRES:-720h}"
NAME="${NAME:-coder-agents}"
DOMAIN="${DOMAIN:-$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')}"
HOST="${MAAS_HOST:-https://maas.${DOMAIN}}"

resp=$(curl -sk -X POST "${HOST}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"${NAME}\",\"expiresIn\":\"${EXPIRES}\",\"subscription\":\"${SUBSCRIPTION}\"}")

key=$(printf '%s' "$resp" | jq -r '.key // empty')
if [ -z "$key" ]; then
  echo "No key returned from ${HOST}/maas-api/v1/api-keys:" >&2
  echo "$resp" >&2
  echo "Is MaaS installed and is the subscription '${SUBSCRIPTION}' applied (oc apply -k model/)?" >&2
  exit 1
fi

echo
echo "  MaaS API key (subscription ${SUBSCRIPTION}, expires in ${EXPIRES}):"
echo
echo "    $key"
echo
echo "  Coder -> Admin settings -> AI -> Providers -> API key"
echo "  Base URL: ${HOST}/llm/qwen25-14b/v1    Model: qwen2.5-14b"
echo
