#!/usr/bin/env bash
# Control-plane node: kubeadm init + Calico, deploy the Olympus dashboard
# as a NodePort, then bring up the webfront TLS reverse proxy in front of
# it. The worker (which builds the image) joins separately.
set -euxo pipefail
exec > >(tee -a /var/log/olympus-bootstrap.log) 2>&1
echo "[olympus] control-plane $(date -u)"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/common.sh"

# Let the host-network nginx reach the NodePort via 127.0.0.1.
sysctl -w net.ipv4.conf.all.route_localnet=1
echo 'net.ipv4.conf.all.route_localnet=1' >/etc/sysctl.d/99-route-localnet.conf

# --- control plane ---
kubeadm init \
  --apiserver-advertise-address="${MASTER_IP}" \
  --pod-network-cidr="${POD_CIDR}" \
  --token "${JOIN_TOKEN}" \
  --token-ttl 0

export KUBECONFIG=/etc/kubernetes/admin.conf
install -d -m 0755 /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config

# --- CNI ---
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml
for _ in $(seq 1 60); do kubectl get --raw='/healthz' >/dev/null 2>&1 && break; sleep 5; done

# --- helm ---
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# --- chart source (no build here; the worker builds + imports the image) ---
rm -rf /opt/olympus-src
git clone --depth 1 --branch "${OLYMPUS_REPO_REF}" "${OLYMPUS_REPO_URL}" /opt/olympus-src

# --- namespace + optional provider-key secret ---
kubectl create namespace "${OLYMPUS_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
secret_args=()
[ -n "${OPENAI_API_KEY}" ]    && secret_args+=(--from-literal=openai_api_key="${OPENAI_API_KEY}")
[ -n "${ANTHROPIC_API_KEY}" ] && secret_args+=(--from-literal=anthropic_api_key="${ANTHROPIC_API_KEY}")
if [ "${#secret_args[@]}" -gt 0 ]; then
  kubectl -n "${OLYMPUS_NAMESPACE}" create secret generic "${OLYMPUS_RELEASE}-secrets" \
    "${secret_args[@]}" --dry-run=client -o yaml | kubectl apply -f -
fi

# --- deploy dashboard (NodePort; kubeadm has no built-in LoadBalancer).
#     Pod stays Pending until the worker joins + the image is imported;
#     control-plane taint keeps it scheduled on the worker. ---
helm upgrade --install "${OLYMPUS_RELEASE}" /opt/olympus-src/infra/k8s/charts/olympus \
  --namespace "${OLYMPUS_NAMESPACE}" \
  --set image.repository=olympus/dashboard \
  --set image.tag="${IMAGE_TAG}" \
  --set image.pullPolicy=Never \
  --set dashboard.router="${OLYMPUS_ROUTER}" \
  --set service.type=NodePort \
  --set service.port=80 \
  --set service.targetPort=8765 \
  --set secrets.sshPrivateKeyKey=""

kubectl -n "${OLYMPUS_NAMESPACE}" patch svc "${OLYMPUS_RELEASE}-olympus" --type merge \
  -p "{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"name\":\"http\",\"port\":80,\"targetPort\":8765,\"nodePort\":${NODE_PORT}}]}}"

# --- TLS front: wait for DNS to point at us, then bring up webfront ---
echo ">>> waiting for ${DNS_HOSTNAME} to resolve to ${PUBLIC_IP}"
for _ in $(seq 1 60); do
  resolved="$(getent hosts "${DNS_HOSTNAME}" | awk '{print $1}' | head -1 || true)"
  [ "${resolved}" = "${PUBLIC_IP}" ] && { echo ">>> DNS ready"; break; }
  sleep 10
done

WF=/opt/webfront
rm -rf "$WF"; cp -r "$HERE/../webfront" "$WF"
printf '%s:%s\n' "${DNS_HOSTNAME}" "${NODE_PORT}" > "$WF/domains.conf"
( cd "$WF" && CERTBOT_EMAIL="${CERTBOT_EMAIL}" CERTBOT_STAGING="${CERTBOT_STAGING}" docker compose up -d )

cat >/etc/motd <<MOTD

  Olympus AWS demo — kubeadm (2 nodes) + TLS front
  URL:        https://${DNS_HOSTNAME}/
  NodePort:   http://127.0.0.1:${NODE_PORT}/   (internal, behind nginx)
  kubeconfig: export KUBECONFIG=/etc/kubernetes/admin.conf
  Log:        /var/log/olympus-bootstrap.log
  Webfront:   cd /opt/webfront && docker compose logs -f

MOTD
echo "[olympus] control-plane done $(date -u)"
