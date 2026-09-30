#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

SERVER_IP="192.168.56.110"

#Install the tools required to download k3s over HTTPS.

apt-get update
apt-get install -y curl ca-certificates

#Install a single node k3s server on the private network

curl -fSL --connect-timeout 10 --max-time 120 https://get.k3s.io |
	INSTALL_K3S_EXEC="server --node-ip ${SERVER_IP} --advertise-address ${SERVER_IP} \
	--flannel-iface eth1" \
	sh -

#Wait for the API and node to become ready.

timeout 120s bash -c '
	until k3s kubectl --request-timeout=10s get nodes >/dev/null 2>&1; do
		sleep 3
	done

	k3s kubectl wait \
		--for=condition=Ready \
		nodes --all \
		--timeout=90s
'

#Display the resulting node configuration.

k3s kubectl get nodes -o wide
