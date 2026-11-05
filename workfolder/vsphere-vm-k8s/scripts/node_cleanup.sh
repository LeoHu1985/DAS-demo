#!/bin/sh
# Revert everything node_prepare.sh changed (best effort, runs on uninstall).
# Env: SSH_USER VM_PASSWORD NODE_NAME
set -u

SUDOERS_FILE=/etc/sudoers.d/90-dap-k8s
APT="apt-get -y -q -o DPkg::Lock::Timeout=600"
export DEBIAN_FRONTEND=noninteractive

echo "== [$NODE_NAME] removing Kubernetes packages and repository"
sudo apt-mark unhold kubelet kubeadm kubectl || true
sudo $APT purge kubelet kubeadm kubectl || true
sudo rm -f /etc/apt/sources.list.d/kubernetes.list /etc/apt/keyrings/kubernetes-apt-keyring.gpg /etc/default/kubelet

echo "== [$NODE_NAME] removing containerd"
sudo systemctl disable --now containerd || true
sudo $APT purge containerd sshpass conntrack socat || true
sudo rm -rf /etc/containerd

echo "== [$NODE_NAME] reverting kernel settings, swap and /etc/hosts"
sudo rm -f /etc/modules-load.d/dap-k8s.conf /etc/sysctl.d/99-dap-k8s.conf
sudo sysctl --system >/dev/null || true
sudo sed -i 's@^#DAP-K8S#@@' /etc/fstab || true
sudo swapon -a || true
sudo sed -i '/# BEGIN DAP-K8S/,/# END DAP-K8S/d' /etc/hosts || true
sudo rm -f /etc/dap-k8s-machine-id /etc/cloud/cloud.cfg.d/99-dap-k8s-network.cfg /etc/cloud/cloud.cfg.d/99-dap-k8s-hostname.cfg

echo "== [$NODE_NAME] removing passwordless sudo"
sudo rm -f "$SUDOERS_FILE"
echo "== [$NODE_NAME] cleanup complete"
