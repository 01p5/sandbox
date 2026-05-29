#!/usr/bin/env bash
# Worker node: build the Olympus image locally, import it into the k8s.io
# containerd namespace (so kubelet can run it with pullPolicy=Never), then
# join the cluster. The dashboard pod lands here (control-plane is tainted).
set -euxo pipefail
exec > >(tee -a /var/log/olympus-bootstrap.log) 2>&1
echo "[olympus] worker $(date -u)"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/common.sh"

# --- build + import the dashboard image ---
rm -rf /opt/olympus-src
git clone --depth 1 --branch "${OLYMPUS_REPO_REF}" "${OLYMPUS_REPO_URL}" /opt/olympus-src
cd /opt/olympus-src
docker build -t "olympus/dashboard:${IMAGE_TAG}" --build-arg INSTALL_LLM_STACK=1 .
docker save "olympus/dashboard:${IMAGE_TAG}" -o /tmp/olympus-image.tar
ctr -n k8s.io images import /tmp/olympus-image.tar
rm -f /tmp/olympus-image.tar

# --- wait for the API server, then join ---
for _ in $(seq 1 180); do
  curl -k -s "https://${MASTER_IP}:6443/healthz" >/dev/null 2>&1 && break
  sleep 5
done
kubeadm join "${MASTER_IP}:6443" \
  --token "${JOIN_TOKEN}" \
  --discovery-token-unsafe-skip-ca-verification
echo "[olympus] worker done $(date -u)"
