#!/usr/bin/env bash
set -euo pipefail

P3_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Check required tools and Docker access.
for tool in docker k3d kubectl;do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "Missing tool: $tool"
    exit 1
  fi
done

docker info >/dev/null

# Create the cluster only if it does not exist/

if ! k3d cluster list -o json |
  grep -q '"name": *"iot"'; then
  k3d cluster create --config "$P3_DIR/confs/cluster.yaml"
else
  k3d cluster start iot
fi

# Select the cluster explicity for subsequent commands.

kubectl config use-context k3d-iot

kubectl wait --for=condition=Ready nodes --all --timeout=180s

kubectl apply -f "$P3_DIR/confs/namespaces.yaml"

kubectl apply --server-side \
  -n argocd \
  -f "$P3_DIR/confs/argocd-install.yaml"

# Wait for Argo CD components.

for deployment in $(kubectl -n argocd get deployments -o name); do
  kubectl -n argocd rollout status "$deployment" --timeout=300s
done

kubectl -n argocd rollout status \
  statefulset/argocd-application-controller --timeout=300s

# Let Argo CD deply the application from Git.

kubectl apply -f "$P3_DIR/confs/argocd-application.yaml"

kubectl get applications -n argocd

