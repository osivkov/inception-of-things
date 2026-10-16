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
