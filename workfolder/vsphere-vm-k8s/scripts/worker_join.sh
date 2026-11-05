#!/bin/sh
# Join this node to the cluster using a fresh token from the control plane.
# Env: SSH_USER VM_PASSWORD NODE_NAME MASTER_IP
set -eu
trap 'echo "ERROR: worker_join.sh failed (exit $?)" >&2' EXIT

SSHPASS="$VM_PASSWORD"
export SSHPASS
on_master() {
  sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR "$SSH_USER@$MASTER_IP" "$@"
}

if sudo test -f /etc/kubernetes/kubelet.conf; then
  echo "== [$NODE_NAME] already joined"
else
  echo "== [$NODE_NAME] requesting join command from $MASTER_IP"
  JOIN_CMD=$(on_master "sudo kubeadm token create --ttl 30m --print-join-command")
  echo "== [$NODE_NAME] kubeadm join"
  # shellcheck disable=SC2086
  sudo $JOIN_CMD --node-name "$NODE_NAME"
fi

echo "== [$NODE_NAME] waiting for node to become Ready"
on_master "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf wait --for=condition=Ready node/$NODE_NAME --timeout=600s"

trap - EXIT
echo "== [$NODE_NAME] joined the cluster"
