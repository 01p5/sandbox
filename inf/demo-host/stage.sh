#!/usr/bin/env bash
#
# Stage the demo-host terraform stack INTO the dashboard pod, where the
# terraform agent (and the sync endpoint) operate. Run once per video session
# (the pod's /tmp survives until a pod restart). Reads the cluster via the
# sandbox ansible inventory + admin.conf on the control plane.
#
#   ./inf/demo-host/stage.sh
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$HERE/../ansible" && pwd)"
NS="${OLYMPUS_NAMESPACE:-olympus}"
REL="${OLYMPUS_RELEASE:-olympus}"

B64="$(base64 -w0 "$HERE/main.tf")"
( cd "$ANSIBLE_DIR" && ansible cp -b -m shell -a "
  kubectl --kubeconfig=/etc/kubernetes/admin.conf -n ${NS} exec deploy/${REL}-olympus -- sh -lc '
    mkdir -p /tmp/demo-host && echo ${B64} | base64 -d > /tmp/demo-host/main.tf && echo staged: && head -1 /tmp/demo-host/main.tf
  '" -o )
echo "✓ staged at /tmp/demo-host in the dashboard pod"
