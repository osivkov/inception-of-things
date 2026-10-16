#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Run this script with sudo."
  exit 1
fi


apt-get update
apt-get install -y docker.io curl ca-certificates

systemctl enable --now docker

if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  usermod -aG docker "$SUDO_USER"
fi

K3D_VERSION="v5.9.0"
K3D_ARCH="$(dpkg --print-architecture)"
K3D_URL="https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}"

(
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT
  cd "$workdir"

  curl -fSL --connect-timeout 10 --max-time 120 \
  "${K3D_URL}/k3d-linux-${K3D_ARCH}" \
  -o "k3d-linux-${K3D_ARCH}"

  curl -fSL --connect-timeout 10 --max-time 120\
  "${K3D_URL}/checksums.txt" \
  -o checksums.txt

  grep -E " _dist/k3d-linux-${K3D_ARCH}$" checksums.txt |
    sed 's|_dist/||' > selected-checksums.txt

  sha256sum -c selected-checksums.txt

  install -m 0755 "k3d-linux-${K3D_ARCH}" /usr/local/bin/k3d
)

k3d version

