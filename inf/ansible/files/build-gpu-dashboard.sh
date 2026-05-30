#!/usr/bin/env bash
# Build the gpu-dashboard image on the worker node. Mirror of
# build-slurm-dashboard.sh for the sibling gpu-watch repo.
#
# Env:
#   GPU_WATCH_REPO_URL  - e.g. https://github.com/01p5/gpu-watch.git
#   GPU_WATCH_REF       - branch or SHA to clone
#   IMAGE_TAG           - tag for the built image (default "dev")
set -euxo pipefail

IMAGE_TAG="${IMAGE_TAG:-dev}"

rm -rf /opt/gpu-watch-src
git clone --depth 1 --branch "${GPU_WATCH_REF}" "${GPU_WATCH_REPO_URL}" /opt/gpu-watch-src
NEW_SHA="$(git -C /opt/gpu-watch-src rev-parse HEAD)"

EXISTING_SHA="$(docker image inspect "gpu-dashboard:${IMAGE_TAG}" --format '{{ index .Config.Labels "gpu.commit" }}' 2>/dev/null || true)"
if [ "${EXISTING_SHA:-}" = "${NEW_SHA}" ] && ctr -n k8s.io images ls -q | grep -q "gpu-dashboard:${IMAGE_TAG}"; then
  echo "[build-gpu-dashboard] image already at ${NEW_SHA}, skipping"
  exit 0
fi

cd /opt/gpu-watch-src
docker build -t "gpu-dashboard:${IMAGE_TAG}" \
  --label "gpu.commit=${NEW_SHA}" .
docker save "gpu-dashboard:${IMAGE_TAG}" -o /tmp/gpu-dashboard-image.tar
ctr -n k8s.io images import /tmp/gpu-dashboard-image.tar
rm -f /tmp/gpu-dashboard-image.tar
echo "[build-gpu-dashboard] done at ${NEW_SHA} ($(date -u))"
