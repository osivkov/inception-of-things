#!/bin/bash
set -euo pipefail

IFACE=$(ip -o -4 addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2}')

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --node-ip=${NODE_IP} --advertise-address=${NODE_IP} \
  --flannel-iface=${IFACE} --write-kubeconfig-mode=644" sh -

until [ -f /var/lib/rancher/k3s/server/node-token ]; do sleep 2; done
cp /var/lib/rancher/k3s/server/node-token /vagrant/confs/node-token
