#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="192.168.56.110"
WORKER_IP="192.168.56.111"

TOKEN=""
for i in $(seq 1 60); do
  TOKEN="$(sudo -u vagrant ssh -o BatchMode=yes -o ConnectTimeout=5 vagrant@${SERVER_IP} 'sudo cat /var/lib/rancher/k3s/server/node-token' 2>/dev/null || true)"
  if [ -n "$TOKEN" ]; then break; fi
  sleep 2
done

if [ -z "$TOKEN" ]; then
  echo "ERROR: could not fetch k3s node-token from server"
  exit 1
fi

curl -sfL --retry 5 --retry-all-errors --connect-timeout 10 --max-time 120 \
  https://get.k3s.io | \
  K3S_URL="https://${SERVER_IP}:6443" \
  K3S_TOKEN="${TOKEN}" \
  INSTALL_K3S_EXEC="agent --node-ip ${WORKER_IP}" sh -

systemctl enable --now k3s-agent

for i in $(seq 1 60); do
  if systemctl is-active --quiet k3s-agent; then
    exit 0
  fi
  sleep 2
done

echo "ERROR: k3s agent did not become ready"
systemctl status k3s-agent --no-pager || true
journalctl -u k3s-agent -n 50 --no-pager || true
exit 1
