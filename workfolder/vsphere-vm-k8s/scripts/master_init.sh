#!/bin/sh
# Initialise the Kubernetes control plane and install the CNI (idempotent).
# Env: SSH_USER NODE_NAME NODE_IP POD_NETWORK_CIDR CNI_MANIFEST_URL
set -eu
trap 'echo "ERROR: master_init.sh failed (exit $?)" >&2' EXIT

ADMIN_CONF=/etc/kubernetes/admin.conf
KUBECTL="sudo kubectl --kubeconfig $ADMIN_CONF"

if sudo test -f "$ADMIN_CONF"; then
  echo "== [$NODE_NAME] control plane already initialised"
else
  echo "== [$NODE_NAME] kubeadm init"
  sudo kubeadm init \
    --apiserver-advertise-address="$NODE_IP" \
    --pod-network-cidr="$POD_NETWORK_CIDR" \
    --node-name="$NODE_NAME"
fi

echo "== [$NODE_NAME] kubeconfig for $SSH_USER"
USER_HOME=$(getent passwd "$SSH_USER" | cut -d: -f6)
sudo mkdir -p "$USER_HOME/.kube"
sudo cp -f "$ADMIN_CONF" "$USER_HOME/.kube/config"
sudo chown -R "$(id -u "$SSH_USER"):$(id -g "$SSH_USER")" "$USER_HOME/.kube"
sudo chmod 600 "$USER_HOME/.kube/config"

echo "== [$NODE_NAME] applying CNI manifest $CNI_MANIFEST_URL"
$KUBECTL apply -f "$CNI_MANIFEST_URL"

echo "== [$NODE_NAME] waiting for control plane to become Ready"
$KUBECTL wait --for=condition=Ready "node/$NODE_NAME" --timeout=600s
$KUBECTL get nodes -o wide

trap - EXIT
echo "== [$NODE_NAME] control plane ready"
