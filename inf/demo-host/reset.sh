#!/usr/bin/env bash
#
# Reset between video takes: destroy the demo host + remove it from the runtime
# inventory, leaving a clean slate. Idempotent — safe to run if nothing's up.
#
#   ./inf/demo-host/reset.sh
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$HERE/../ansible" && pwd)"
NS="${OLYMPUS_NAMESPACE:-olympus}"
REL="${OLYMPUS_RELEASE:-olympus}"

( cd "$ANSIBLE_DIR" && ansible cp -b -m shell -a "
  kubectl --kubeconfig=/etc/kubernetes/admin.conf -n ${NS} exec deploy/${REL}-olympus -- sh -lc '
    if [ -f /tmp/demo-host/terraform.tfstate ]; then
      cd /tmp/demo-host && terraform destroy -auto-approve >/tmp/tf-destroy.log 2>&1 && echo destroyed || { echo destroy-FAILED; tail -5 /tmp/tf-destroy.log; }
    else echo \"no state — nothing to destroy\"; fi
    olympus-inventory --store /var/lib/olympus/inventory.json remove-host --name demo-host 2>/dev/null || echo \"demo-host not in inventory\"
  '" -o )
echo "✓ reset complete (host destroyed + removed from inventory)"
