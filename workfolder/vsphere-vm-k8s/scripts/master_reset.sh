#!/bin/sh
# Tear down the control plane created by master_init.sh (best effort).
# Env: SSH_USER NODE_NAME
set -u

echo "== [$NODE_NAME] kubeadm reset"
sudo kubeadm reset -f || true
sudo rm -rf /etc/cni/net.d /var/lib/etcd
USER_HOME=$(getent passwd "$SSH_USER" | cut -d: -f6)
sudo rm -rf "$USER_HOME/.kube"
echo "== [$NODE_NAME] control plane removed"
