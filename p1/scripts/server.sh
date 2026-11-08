#!/usr/bin/env bash

set -euo pipefail

SERVER_IP="192.168.56.110"

if ! systemctl cat k3s >/dev/null 2>&1; then
  curl -sfL --retry 5 --retry-all-errors --connect-timeout 10 --max-time 120 \
    https://get.k3s.io | \
    INSTALL_K3S_EXEC="server --node-ip ${SERVER_IP} --advertise-address ${SERVER_IP} --write-kubeconfig-mode 644" sh -
fi

systemctl enable --now k3s

for i in $(seq 1 60); do
  if k3s kubectl --request-timeout=10s get nodes -o wide; then
    exit 0
  fi
  sleep 2
done

echo "ERROR: k3s server did not become ready"
systemctl status k3s --no-pager || true
journalctl -u k3s -n 50 --no-pager || true
exit 1
