#!/usr/bin/env bash
set -euo pipefail

BONUS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(dirname -- "$BONUS_DIR")"

# Check Helm before starting the setup.
if ! command -v helm >/dev/null 2>&1; then
  echo "Missing tool: helm. Run bonus/scripts/install-helm.sh first."
  exit 1
fi

# Start the cluster and Argo CD without selecting the P3 application source.
SKIP_APPLICATION=true bash "$PROJECT_DIR/p3/scripts/up.sh"

# Use the intended cluster for every command.
KUBECTL=(kubectl --context=k3d-iot)

# Create the GitLab namespace before installing its resources.
"${KUBECTL[@]}" apply -f "$BONUS_DIR/confs/namespace.yaml"

# Install or update GitLab using our Helm chart.
helm upgrade --install gitlab "$BONUS_DIR/charts/gitlab" \
  --kube-context k3d-iot \
  --namespace gitlab \
  --wait \
  --timeout 10m

# Point Argo CD at the repository hosted by GitLab.
"${KUBECTL[@]}" apply -f "$BONUS_DIR/confs/argocd-application.yaml"

# Request a fresh comparison after GitLab becomes ready.
"${KUBECTL[@]}" -n argocd annotate application playground \
  argocd.argoproj.io/refresh=hard --overwrite

"${KUBECTL[@]}" -n argocd wait application/playground \
  --for=jsonpath='{.status.sync.status}'=Synced \
  --timeout=300s

"${KUBECTL[@]}" -n argocd wait application/playground \
  --for=jsonpath='{.status.health.status}'=Healthy \
  --timeout=300s

"${KUBECTL[@]}" -n gitlab get pods,pvc
"${KUBECTL[@]}" -n argocd get application playground
