#!/usr/bin/env bash
#
# Deploy the Coder control plane on OpenShift.
#
# Idempotent: safe to re-run. Generates the DB password once and reuses it.

set -euo pipefail
cd "$(dirname "$0")"

NS="${NS:-coder}"
# Pinned to the version this quickstart was tested with. Override with
# CODER_VERSION=x.y.z to try a newer one (then re-download the CLI, step 4).
CODER_VERSION="${CODER_VERSION:-2.39.1}"
# The cluster's own ingress domain, e.g. apps.cluster-xxxxx.example.com.
# Override with DOMAIN=... only if Coder should live on a different domain.
DOMAIN="${DOMAIN:-$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')}"
[ -n "$DOMAIN" ] || { echo "could not read the ingress domain; set DOMAIN=" >&2; exit 1; }

oc get namespace "$NS" >/dev/null 2>&1 || oc create namespace "$NS"

# ---- database secret ------------------------------------------------------
# Reuse the existing password if the secret is already there, so re-running
# this script does not orphan the data in the PVC.
if oc get secret coder-db -n "$NS" >/dev/null 2>&1; then
  echo "==> reusing existing coder-db secret"
  PGPASS="$(oc get secret coder-db -n "$NS" -o jsonpath='{.data.password}' | base64 -d)"
else
  echo "==> generating database password"
  # NOT `tr -dc ... </dev/urandom | head -c 32`: head exits after 32 bytes,
  # tr takes SIGPIPE, and `set -o pipefail` then aborts the whole script.
  PGPASS="$(openssl rand -hex 16)"
fi

sed "s|CHANGEME|${PGPASS}|" 01-postgres.yaml | oc apply -f -

# Coder wants a single connection URL rather than discrete fields.
oc create secret generic coder-db-url -n "$NS" \
  --from-literal=url="postgres://coder:${PGPASS}@coder-db.${NS}.svc.cluster.local:5432/coder?sslmode=disable" \
  --dry-run=client -o yaml | oc apply -f -

echo "==> waiting for postgres"
oc rollout status sts/coder-db -n "$NS" --timeout=300s

# ---- ingress CA -------------------------------------------------------------
# Coder reaches the model (https://maas.<domain>) and the MCP gateway
# (https://mcp.<domain>) through Routes. Trust whatever CA signed the
# cluster's ingress certificate; values.yaml mounts it into SSL_CERT_DIR.
echo "==> ingress CA"
oc get configmap default-ingress-cert -n openshift-config-managed \
  -o jsonpath='{.data.ca-bundle\.crt}' > /tmp/ingress-ca.crt
if [ -s /tmp/ingress-ca.crt ]; then
  oc create configmap ingress-ca -n "$NS" --from-file=ca-bundle.crt=/tmp/ingress-ca.crt \
    --dry-run=client -o yaml | oc apply -f -
else
  echo "    (no default-ingress-cert found; assuming a publicly trusted ingress cert)"
fi
rm -f /tmp/ingress-ca.crt

# ---- MCP destination policy ----------------------------------------------
# Coder refuses MCP connections to private IPs unless exempted. The MCP
# gateway is reached at https://mcp.<domain>/mcp, which resolves inside the
# cluster to the ingress address. Resolve it the way a pod would (from the
# router pod, which exists on every OpenShift cluster) and exempt exactly
# those addresses. Override with MCP_ALLOWED_PRIVATE_CIDRS=10.0.0.5/32,...
# or set it to "" to exempt nothing.
if [ -z "${MCP_ALLOWED_PRIVATE_CIDRS+x}" ]; then
  MCP_ALLOWED_PRIVATE_CIDRS=$(oc exec -n openshift-ingress deploy/router-default -- \
      getent ahostsv4 "mcp.${DOMAIN}" 2>/dev/null | awk '{print $1"/32"}' | sort -u | paste -sd, - || true)
fi
echo "==> MCP private CIDRs exempted: ${MCP_ALLOWED_PRIVATE_CIDRS:-none}"

# ---- coder ----------------------------------------------------------------
echo "==> adding helm repo"
helm repo add coder-v2 https://helm.coder.com/v2 >/dev/null 2>&1 || true
helm repo update coder-v2 >/dev/null

echo "==> installing/upgrading coder"
render_values() {
  if [ -n "${MCP_ALLOWED_PRIVATE_CIDRS}" ]; then
    sed -e "s|CODER_DOMAIN|${DOMAIN}|" -e "s|__MCP_CIDRS__|${MCP_ALLOWED_PRIVATE_CIDRS}|" values.yaml
  else
    # nothing to exempt: drop the env entry (its name line and value line)
    sed -e "s|CODER_DOMAIN|${DOMAIN}|" values.yaml | awk '/MCP_CIDRS_LINE/ {skip=2} skip-- > 0 {next} {print}' 
  fi
}
render_values | \
helm upgrade --install coder coder-v2/coder \
  --version "$CODER_VERSION" \
  --namespace "$NS" \
  --values - \
  --wait --timeout 10m

echo "==> creating route"
sed "s|CODER_DOMAIN|${DOMAIN}|" 02-route.yaml | oc apply -f -

echo
echo "    https://coder.${DOMAIN}"
echo
echo "    First run: create the initial admin user in the browser, or"
echo "      oc exec -n ${NS} deploy/coder -- coder login --first-user ..."
echo
