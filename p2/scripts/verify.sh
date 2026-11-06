#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo 'Checking P2 VM and K3s...'
vagrant ssh osivkovS -c 'test "$(hostname)" = osivkovS && ip -o -4 addr show | grep -Eq "inet 192[.]168[.]56[.]110/" && timeout 180 bash -c "until systemctl is-active --quiet k3s; do sleep 3; done" && sudo k3s kubectl wait --for=condition=Ready nodes --all --timeout=120s && test "$(sudo k3s kubectl get nodes --no-headers | wc -l)" -eq 1'

echo 'Checking deployments, replicas and Ingress...'
vagrant ssh osivkovS -c 'for app in app1 app2 app3; do sudo k3s kubectl rollout status deployment/"$app" --timeout=120s; done; test "$(sudo k3s kubectl get deployment app2 -o jsonpath="{.spec.replicas}")" -eq 3; test "$(sudo k3s kubectl get deployment app2 -o jsonpath="{.status.readyReplicas}")" -eq 3; sudo k3s kubectl get deployments,services,ingress -o wide'

echo 'Checking HTTP routing...'
for route in 'app1.com:app1' 'app2.com:app2' 'unknown.example:app3'; do
  host="${route%%:*}"
  app="${route#*:}"
  response="$(curl -fsS --retry 10 --retry-delay 2 --retry-connrefused --max-time 10 -H "Host: $host" http://192.168.56.110/)"
  if [[ "$response" != *"Hello from $app"* ]]; then
    echo "Unexpected response for Host: $host" >&2
    exit 1
  fi
  echo "Host: $host -> $app"
done

echo 'PASS: P2 has three reachable apps, a default route, and three app2 replicas.'
