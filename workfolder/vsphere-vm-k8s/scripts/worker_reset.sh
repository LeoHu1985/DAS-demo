#!/bin/sh
# Remove this worker from the cluster and reset kubeadm state (best effort).
# Env: SSH_USER VM_PASSWORD NODE_NAME MASTER_IP
set -u

SSHPASS="$VM_PASSWORD"
export SSHPASS

echo "== [$NODE_NAME] removing node object from the control plane"
sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  "$SSH_USER@$MASTER_IP" \
  "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf delete node $NODE_NAME --ignore-not-found" || true

echo "== [$NODE_NAME] kubeadm reset"
sudo kubeadm reset -f || true
sudo rm -rf /etc/cni/net.d
echo "== [$NODE_NAME] worker removed"
