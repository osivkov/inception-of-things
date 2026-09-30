#!/usr/bin/env bash

set -euo pipefail

SERVER_IP="192.168.56.110"

curl -sfL --connect-timeout 10 --max-time 120 https://get.k3s.io | \
  INSTALL_K3S_EXEC="server --node-ip ${SERVER_IP} --advertise-address ${SERVER_IP} --write-kubeconfig-mode 644" sh -

timeout 30s kubectl --request-timeout=20s get nodes -o wide || true
