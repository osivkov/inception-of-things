#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

grep -q "osivkovS" /etc/hosts || cat >> /etc/hosts <<EOT
192.168.56.110 osivkovS
192.168.56.111 osivkovSW
EOT

apt-get update -y
apt-get install -y curl ca-certificates openssh-client

swapoff -a || true
sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab || true

install -d -m 700 /home/vagrant/.ssh
cp /tmp/cluster_key /home/vagrant/.ssh/id_ed25519
cp /tmp/cluster_key.pub /home/vagrant/.ssh/id_ed25519.pub
cat /tmp/cluster_key.pub >> /home/vagrant/.ssh/authorized_keys

chmod 600 /home/vagrant/.ssh/id_ed25519 /home/vagrant/.ssh/authorized_keys
chown -R vagrant:vagrant /home/vagrant/.ssh

cat > /home/vagrant/.ssh/config <<CFG
Host 192.168.56.*
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
CFG
chmod 600 /home/vagrant/.ssh/config
chown vagrant:vagrant /home/vagrant/.ssh/config