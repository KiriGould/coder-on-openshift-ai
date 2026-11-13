#!/usr/bin/env bash
# Workspace entrypoint: fix up identity and TLS trust before handing over.
set -eu

# --- 1. give the arbitrary OpenShift UID a real passwd entry ---------------
# Without this, `id -un` fails, git reports "unable to look up current user",
# and the Coder agent logs "get current user: ... requires cgo or $USER set"
# every 10s and never reports healthy.
if ! whoami >/dev/null 2>&1; then
  if [ -w /etc/passwd ]; then
    echo "coder:x:$(id -u):0:Coder workspace user:/home/coder:/bin/bash" >> /etc/passwd
  else
    echo "WARNING: uid $(id -u) has no passwd entry and /etc/passwd is not" \
         "writable; git and ssh will misbehave." >&2
  fi
fi
export HOME=/home/coder

# --- 2. trust the OpenShift service CA ------------------------------------
# The KServe model serves HTTPS with a cert signed by the cluster's service
# CA, which is not in the default trust store. Python, curl and git would
# fail certificate verification against in-cluster HTTPS services.
#
# A COMBINED bundle, not just the service CA: pointing SSL_CERT_FILE at
# service-ca.crt alone would replace the system roots and break TLS to
# everywhere else (PyPI, git remotes...).
SA_DIR=/var/run/secrets/kubernetes.io/serviceaccount
SYS_CA=/etc/pki/tls/certs/ca-bundle.crt
COMBINED=/tmp/ca-bundle-combined.crt

if [ -r "$SA_DIR/service-ca.crt" ] && [ -r "$SYS_CA" ]; then
  cat "$SYS_CA" "$SA_DIR/service-ca.crt" > "$COMBINED" 2>/dev/null || true
  if [ -s "$COMBINED" ]; then
    export SSL_CERT_FILE="$COMBINED"
    export REQUESTS_CA_BUNDLE="$COMBINED"   # requests ignores SSL_CERT_FILE
    export CURL_CA_BUNDLE="$COMBINED"
  fi
fi

exec "$@"
