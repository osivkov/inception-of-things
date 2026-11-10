
#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="192.168.56.110"

echo "[SERVER] Installing K3s..."

# Install K3s only if the service is not installed.
if ! systemctl cat k3s >/dev/null 2>&1; then
    curl -sfL \
        --retry 5 \
        --retry-all-errors \
        --connect-timeout 10 \
        --max-time 120 \
        https://get.k3s.io | \
    INSTALL_K3S_EXEC="server \
        --node-ip ${SERVER_IP} \
        --advertise-address ${SERVER_IP} \
        --flannel-iface eth1 \
        --write-kubeconfig-mode 644 \
        --disable traefik \
        --disable servicelb \
        --disable metrics-server" \
    sh -
fi

echo "[SERVER] Starting K3s..."

systemctl enable --now k3s

echo "[SERVER] Waiting for K3s node readiness..."

for i in $(seq 1 60); do
    if k3s kubectl --request-timeout=10s \
        wait --for=condition=Ready \
        node --all --timeout=5s >/dev/null 2>&1; then

        if k3s kubectl get nodes --no-headers | grep -q ' Ready '; then
            echo "[SERVER] K3s server is Ready."
            k3s kubectl get nodes -o wide
            exit 0
        fi
    fi

    sleep 2
done

echo "[ERROR] K3s server did not become Ready."

systemctl status k3s --no-pager || true
journalctl -u k3s -n 50 --no-pager || true

exit 1
