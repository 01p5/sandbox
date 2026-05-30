#!/usr/bin/env bash
# Build the Olympus dashboard image on the worker and import it into the
# k8s.io containerd namespace so kubelet can run it with pullPolicy=Never.
# Run by Ansible via the `script` module with OLYMPUS_REPO_URL,
# OLYMPUS_REPO_REF and IMAGE_TAG in the environment.
set -euxo pipefail

# Always clone fresh so re-runs pick up new commits on the same ref.
rm -rf /opt/olympus-src
git clone --depth 1 --branch "${OLYMPUS_REPO_REF}" "${OLYMPUS_REPO_URL}" /opt/olympus-src
NEW_SHA="$(git -C /opt/olympus-src rev-parse HEAD)"

# Fast-path: image already built from this commit + imported into k8s.io.
EXISTING_SHA="$(docker image inspect "olympus/dashboard:${IMAGE_TAG}" --format '{{ index .Config.Labels "olympus.commit" }}' 2>/dev/null || true)"
if [ "${EXISTING_SHA:-}" = "${NEW_SHA}" ] && ctr -n k8s.io images ls -q | grep -q "olympus/dashboard:${IMAGE_TAG}"; then
  echo "[build] image already at ${NEW_SHA}, skipping"
  exit 0
fi

cd /opt/olympus-src
docker build -t "olympus/dashboard:${IMAGE_TAG}" \
  --label "olympus.commit=${NEW_SHA}" \
  --build-arg INSTALL_LLM_STACK=1 .
docker save "olympus/dashboard:${IMAGE_TAG}" -o /tmp/olympus-image.tar
ctr -n k8s.io images import /tmp/olympus-image.tar
rm -f /tmp/olympus-image.tar
echo "[build] done at ${NEW_SHA} ($(date -u))"
