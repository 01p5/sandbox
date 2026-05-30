#!/usr/bin/env bash
# Common node prereqs for a kubeadm cluster. Run by Ansible via the
# `script` module with K8S_VERSION in the environment. Installs containerd
# + docker + the kubeadm/kubelet/kubectl stack and prepares the kernel for
# Kubernetes networking. Safe to re-run.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# apt resilience: the regional EC2 mirror sometimes serves out-of-sync
# indexes. Treat `update` as best-effort (the install is the real gate),
# and fall back to the canonical archive mirror after a couple of misses.
aptq() {
  if [ "$1" = update ]; then apt-get update -y || true; return 0; fi
  for i in $(seq 1 6); do
    apt-get "$@" && return 0
    echo "[apt] retry $i: $*"
    [ "$i" -ge 2 ] && sed -i 's#https\?://[a-z0-9.-]*\.ec2\.archive\.ubuntu\.com/ubuntu#http://archive.ubuntu.com/ubuntu#g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
    apt-get update -y || true
    sleep 15
  done
  return 1
}

# kernel modules + sysctls k8s networking needs
cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay || true
modprobe br_netfilter || true

cat >/etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# kubelet refuses to start with swap on (EC2 Ubuntu has none, but be safe)
swapoff -a || true

aptq update
aptq install -y apt-transport-https ca-certificates curl gpg git docker.io docker-compose-v2
systemctl enable --now docker

# containerd configured for the systemd cgroup driver (kubeadm requirement)
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# kubeadm / kubelet / kubectl from pkgs.k8s.io
install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list
aptq update
aptq install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet
echo "[prereqs] done $(date -u)"
