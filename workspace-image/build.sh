#!/usr/bin/env bash
#
# Build the workspace image into the internal registry (QUICKSTART step 5).
#
#   ./workspace-image/build.sh
#
# Idempotent: creates the BuildConfig once, then (re)builds from this folder.
# Needs the `coder` namespace (coder/deploy.sh creates it).

set -euo pipefail
cd "$(dirname "$0")"
NS="${NS:-coder}"

oc get namespace "$NS" >/dev/null 2>&1 || { echo "namespace $NS not found; run coder/deploy.sh first" >&2; exit 1; }
oc get bc/coder-workspace -n "$NS" >/dev/null 2>&1 || {
  oc new-build --name=coder-workspace --binary --strategy=docker -n "$NS"
  oc patch bc/coder-workspace -n "$NS" --type=merge \
    -p '{"spec":{"strategy":{"dockerStrategy":{"dockerfilePath":"Containerfile"}}}}'
}
# ~10 min the first time (VS Code + extensions); later builds reuse layers.
oc start-build coder-workspace --from-dir=. --follow -n "$NS"
echo
echo "    image: image-registry.openshift-image-registry.svc:5000/${NS}/coder-workspace:latest"
echo "    next:  ./template/push.sh"
