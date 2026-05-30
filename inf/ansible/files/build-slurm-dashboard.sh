#!/usr/bin/env bash
# Build the slurm-dashboard image on the worker node and import it into
# the k8s.io containerd namespace so kubelet can run it with
# pullPolicy=Never. Mirror of build-image.sh, just for the sibling
# slurm-mgr repo.
#
# Env (set by ansible.script):
#   SLURM_MGR_REPO_URL  - e.g. https://github.com/01p5/slurm-mgr.git
#   SLURM_MGR_REF       - branch or SHA to clone
#   IMAGE_TAG           - tag for the built image (default "dev")
set -euxo pipefail

IMAGE_TAG="${IMAGE_TAG:-dev}"

# Always clone fresh so re-runs pick up new commits on the ref.
rm -rf /opt/slurm-mgr-src
git clone --depth 1 --branch "${SLURM_MGR_REF}" "${SLURM_MGR_REPO_URL}" /opt/slurm-mgr-src
NEW_SHA="$(git -C /opt/slurm-mgr-src rev-parse HEAD)"

# Fast-path: image already built from this commit + imported into k8s.io.
EXISTING_SHA="$(docker image inspect "slurm-dashboard:${IMAGE_TAG}" --format '{{ index .Config.Labels "slurm.commit" }}' 2>/dev/null || true)"
if [ "${EXISTING_SHA:-}" = "${NEW_SHA}" ] && ctr -n k8s.io images ls -q | grep -q "slurm-dashboard:${IMAGE_TAG}"; then
  echo "[build-slurm-dashboard] image already at ${NEW_SHA}, skipping"
  exit 0
fi

cd /opt/slurm-mgr-src
docker build -t "slurm-dashboard:${IMAGE_TAG}" \
  --label "slurm.commit=${NEW_SHA}" .
docker save "slurm-dashboard:${IMAGE_TAG}" -o /tmp/slurm-dashboard-image.tar
ctr -n k8s.io images import /tmp/slurm-dashboard-image.tar
rm -f /tmp/slurm-dashboard-image.tar
echo "[build-slurm-dashboard] done at ${NEW_SHA} ($(date -u))"
