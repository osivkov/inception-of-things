#!/bin/bash
set -euo pipefail

IFACE=$(ip -o -4 addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2}')

until [ -s /vagrant/confs/node-token ]; do sleep 2; done
TOKEN=$(cat /vagrant/confs/node-token)

curl -sfL https://get.k3s.io | K3S_URL="https://192.168.56.110:6443" K3S_TOKEN="$TOKEN" \
  INSTALL_K3S_EXEC="agent --node-ip=${NODE_IP} --flannel-iface=${IFACE}" sh -
