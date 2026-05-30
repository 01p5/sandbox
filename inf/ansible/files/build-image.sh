#!/usr/bin/env bash
# Build the Olympus dashboard image on the worker and import it into the
# k8s.io containerd namespace so kubelet can run it with pullPolicy=Never.
# Run by Ansible via the `script` module with OLYMPUS_REPO_URL,
# OLYMPUS_REPO_REF and IMAGE_TAG in the environment.
set -euxo pipefail

# Skip the (slow) rebuild if the image is already imported.
if ctr -n k8s.io images ls -q | grep -q "olympus/dashboard:${IMAGE_TAG}"; then
  echo "[build] image already present, skipping"
  exit 0
fi

rm -rf /opt/olympus-src
git clone --depth 1 --branch "${OLYMPUS_REPO_REF}" "${OLYMPUS_REPO_URL}" /opt/olympus-src
cd /opt/olympus-src
docker build -t "olympus/dashboard:${IMAGE_TAG}" --build-arg INSTALL_LLM_STACK=1 .
docker save "olympus/dashboard:${IMAGE_TAG}" -o /tmp/olympus-image.tar
ctr -n k8s.io images import /tmp/olympus-image.tar
rm -f /tmp/olympus-image.tar
echo "[build] done $(date -u)"
