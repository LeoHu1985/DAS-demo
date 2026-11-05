#!/bin/sh
# Prepare a cloned Ubuntu VM as a Kubernetes node (idempotent, safe to retry).
# Env: SSH_USER VM_PASSWORD NODE_NAME NODE_IP K8S_VERSION
#      NETWORK_CIDR GATEWAY DNS_SERVER
#      MASTER_NAME MASTER_IP WORKER1_NAME WORKER1_IP WORKER2_NAME WORKER2_IP WORKER3_NAME WORKER3_IP WORKER4_NAME WORKER4_IP
set -eu
trap 'echo "ERROR: node_prepare.sh failed (exit $?)" >&2' EXIT

SUDOERS_FILE=/etc/sudoers.d/90-dap-k8s
KEYRING=/etc/apt/keyrings/kubernetes-apt-keyring.gpg
APT="apt-get -y -q -o DPkg::Lock::Timeout=600"
export DEBIAN_FRONTEND=noninteractive

echo "== [$NODE_NAME] enabling passwordless sudo for $SSH_USER (removed on uninstall)"
printf '%s\n' "$VM_PASSWORD" | sudo -S -p '' sh -c \
  "echo '$SSH_USER ALL=(ALL) NOPASSWD:ALL' > $SUDOERS_FILE && chmod 0440 $SUDOERS_FILE"

echo "== [$NODE_NAME] hostname and /etc/hosts"
sudo hostnamectl set-hostname "$NODE_NAME"
sudo sed -i '/# BEGIN DAP-K8S/,/# END DAP-K8S/d' /etc/hosts
printf '# BEGIN DAP-K8S\n%s %s\n%s %s\n%s %s\n%s %s\n%s %s\n# END DAP-K8S\n' \
  "$MASTER_IP" "$MASTER_NAME" "$WORKER1_IP" "$WORKER1_NAME" "$WORKER2_IP" "$WORKER2_NAME" "$WORKER3_IP" "$WORKER3_NAME" "$WORKER4_IP" "$WORKER4_NAME" \
  | sudo tee -a /etc/hosts >/dev/null

echo "== [$NODE_NAME] pinning static network config so it survives reboots"
NIC=$(ip -o -4 addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2; exit}')
[ -n "$NIC" ] || NIC=ens192
MAC=$(cat "/sys/class/net/$NIC/address")
PREFIX=${NETWORK_CIDR#*/}
printf 'network: {config: disabled}\n' | sudo tee /etc/cloud/cloud.cfg.d/99-dap-k8s-network.cfg >/dev/null
printf 'preserve_hostname: true\n' | sudo tee /etc/cloud/cloud.cfg.d/99-dap-k8s-hostname.cfg >/dev/null
printf 'network:\n  version: 2\n  ethernets:\n    %s:\n      match:\n        macaddress: "%s"\n      set-name: %s\n      dhcp4: false\n      addresses: [%s/%s]\n      routes:\n        - to: 0.0.0.0/0\n          via: %s\n      nameservers:\n        addresses: [%s]\n' \
  "$NIC" "$MAC" "$NIC" "$NODE_IP" "$PREFIX" "$GATEWAY" "$DNS_SERVER" \
  | sudo tee /etc/netplan/50-cloud-init.yaml >/dev/null
sudo chmod 600 /etc/netplan/50-cloud-init.yaml

# Clones share the template's machine-id; give each node its own (once).
if [ ! -f /etc/dap-k8s-machine-id ]; then
  echo "== [$NODE_NAME] regenerating machine-id"
  sudo rm -f /etc/machine-id /var/lib/dbus/machine-id
  sudo systemd-machine-id-setup
  sudo touch /etc/dap-k8s-machine-id
fi

echo "== [$NODE_NAME] disabling swap"
sudo swapoff -a
sudo sed -i -E 's@^([^#].*[[:space:]]swap[[:space:]].*)$@#DAP-K8S#\1@' /etc/fstab

echo "== [$NODE_NAME] kernel modules and sysctl"
printf 'overlay\nbr_netfilter\n' | sudo tee /etc/modules-load.d/dap-k8s.conf >/dev/null
sudo modprobe overlay
sudo modprobe br_netfilter
printf 'net.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward = 1\n' \
  | sudo tee /etc/sysctl.d/99-dap-k8s.conf >/dev/null
sudo sysctl --system >/dev/null

echo "== [$NODE_NAME] installing containerd"
sudo $APT update
sudo $APT install ca-certificates curl gpg apt-transport-https containerd sshpass conntrack socat
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

echo "== [$NODE_NAME] installing kubeadm/kubelet/kubectl v$K8S_VERSION"
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/Release.key" \
  | sudo gpg --dearmor --yes -o "$KEYRING"
echo "deb [signed-by=$KEYRING] https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
sudo $APT update
sudo $APT install kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
echo "KUBELET_EXTRA_ARGS=--node-ip=$NODE_IP" | sudo tee /etc/default/kubelet >/dev/null
sudo systemctl enable --now kubelet

trap - EXIT
echo "== [$NODE_NAME] node preparation complete"
