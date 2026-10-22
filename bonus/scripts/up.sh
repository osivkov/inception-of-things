#!/usr/bin/env bash
set -euo pipefail

BONUS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(dirname -- "$BONUS_DIR")"

# Start the cluster and Argo CD without selecting the P3 application source.
SKIP_APPLICATION=true bash "$PROJECT_DIR/p3/scripts/up.sh"

# Use the intended cluster for every command.
KUBECTL=(kubectl --context=k3d-iot)

# Create the namespace before its resources.
"${KUBECTL[@]}" apply -f "$BONUS_DIR/confs/namespace.yaml"

# Prepare persistent storage and GitLab settings.
"${KUBECTL[@]}" apply -f "$BONUS_DIR/confs/storage.yaml"
"${KUBECTL[@]}" apply -f "$BONUS_DIR/confs/gitlab-config.yaml"

# Deploy GitLab and configure HTTP access.
"${KUBECTL[@]}" apply -f "$BONUS_DIR/confs/gitlab-deployment.yaml"
"${KUBECTL[@]}" apply -f "$BONUS_DIR/confs/gitlab-service.yaml"
"${KUBECTL[@]}" apply -f "$BONUS_DIR/confs/gitlab-ingress.yaml"

# Wait until GitLab can serve requests.
"${KUBECTL[@]}" -n gitlab rollout status \
  deployment/gitlab --timeout=600s

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
