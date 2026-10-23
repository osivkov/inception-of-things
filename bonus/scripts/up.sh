#!/usr/bin/env bash
set -euo pipefail

# Accept an optional first-install mode.
SETUP_ONLY=false

case "${1:-}" in
  "")
    ;;
  --setup-only)
    SETUP_ONLY=true
    ;;
  *)
    echo "Usage: bash bonus/scripts/up.sh [--setup-only]"
    exit 1
    ;;
esac

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

# Stop here when preparing a fresh GitLab installation.
if [[ "$SETUP_ONLY" == "true" ]]; then
  echo "GitLab is ready at http://localhost:8080"
  echo "Log in and create a personal access token with the api scope."
  echo "Then run: bash bonus/scripts/up.sh"
  exit 0
fi

python3 "$BONUS_DIR/scripts/bootstrap-gitlab.py"

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
