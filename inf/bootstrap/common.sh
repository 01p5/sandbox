# Shared prereqs for both kubeadm roles. Sourced (not executed) by
# control-plane.sh / worker.sh, so it runs under their `set -e` and
# inherits the exported env (K8S_VERSION, etc.). Installs containerd +
# docker + the kubeadm/kubelet/kubectl stack and prepares the kernel for
# Kubernetes networking.
echo "[olympus] common prereqs $(date -u)"
export DEBIAN_FRONTEND=noninteractive

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

apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gpg git docker.io
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
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet
echo "[olympus] common prereqs done $(date -u)"
