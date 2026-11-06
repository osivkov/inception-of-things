#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo 'Checking P1 server...'
vagrant ssh osivkovS -c 'test "$(hostname)" = osivkovS && ip -o -4 addr show | grep -Eq "inet 192[.]168[.]56[.]110/" && timeout 180 bash -c "until systemctl is-active --quiet k3s; do sleep 3; done" && command -v kubectl >/dev/null'

echo 'Checking P1 worker...'
vagrant ssh osivkovSW -c 'test "$(hostname)" = osivkovSW && ip -o -4 addr show | grep -Eq "inet 192[.]168[.]56[.]111/" && timeout 180 bash -c "until systemctl is-active --quiet k3s-agent; do sleep 3; done"'

echo 'Checking both Kubernetes nodes...'
vagrant ssh osivkovS -c 'sudo k3s kubectl wait --for=condition=Ready nodes --all --timeout=120s && test "$(sudo k3s kubectl get nodes --no-headers | wc -l)" -eq 2 && sudo k3s kubectl get nodes -o wide'

echo 'PASS: P1 has two passwordless SSH guests and two ready K3s nodes.'
