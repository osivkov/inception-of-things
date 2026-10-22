#!/usr/bin/env bash
set -euo pipefail

HELM_VERSION="v4.3.1"
HELM_ARCH="$(dpkg --print-architecture)"
HELM_ARCHIVE="helm-${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz"

(
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT
  cd "$workdir"

  # Download the archive and its expected checksum.
  curl -fSL --connect-timeout 10 --max-time 120 \
    "https://get.helm.sh/${HELM_ARCHIVE}" \
    -o "$HELM_ARCHIVE"

  curl -fSL --connect-timeout 10 --max-time 120 \
    "https://get.helm.sh/${HELM_ARCHIVE}.sha256sum" \
    -o "${HELM_ARCHIVE}.sha256sum"

  # Verify the archive before extracting it.
  sha256sum -c "${HELM_ARCHIVE}.sha256sum"

  tar -xzf "$HELM_ARCHIVE"

  # Install the executable where the shell can find it.
  sudo install -m 0755 "linux-${HELM_ARCH}/helm" /usr/local/bin/helm
)

helm version --short
