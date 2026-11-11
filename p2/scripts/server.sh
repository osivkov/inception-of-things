#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
SERVER_IP="192.168.56.110"

apt-get update
apt-get install -y curl ca-certificates

# detect the interface that holds the private IP (eth1, enp0s8, ...)
IFACE=$(ip -o -4 addr show | awk -v ip="$SERVER_IP" '$4 ~ "^"ip"/" {print $2}')

if ! command -v k3s >/dev/null 2>&1; then
  curl -fsSL --retry 5 --retry-delay 3 https://get.k3s.io |
    INSTALL_K3S_VERSION="v1.37.2+k3s1" \
    INSTALL_K3S_EXEC="server --node-ip ${SERVER_IP} --advertise-address ${SERVER_IP} --flannel-iface ${IFACE} --write-kubeconfig-mode 644" \
    sh -
fi
systemctl start k3s

# wait for the API and the node to become ready
timeout 300s bash -c '
  until k3s kubectl --request-timeout=10s get nodes >/dev/null 2>&1; do sleep 3; done
  k3s kubectl wait --for=condition=Ready nodes --all --timeout=240s
'

k3s kubectl get nodes -o wide

# deploy applications and HTTP routes
for app in app1 app2 app3; do
  k3s kubectl apply -f "/home/vagrant/confs/${app}.yaml"
done
k3s kubectl apply -f /home/vagrant/confs/ingress.yaml

for app in app1 app2 app3; do
  k3s kubectl rollout status "deployment/${app}" --timeout=180s
done
