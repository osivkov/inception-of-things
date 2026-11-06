
.DEFAULT_GOAL := help

SERVER := osivkovS
WORKER := osivkovSW

define kubectl
vagrant ssh $(SERVER) -c "sudo k3s kubectl $(1)"
endef

.PHONY: help keys prepare check up test status halt destroy \
        cluster nodes node-info pods system-pods \
        deployments services ingress events \
        k3s-status logs-server logs-worker \
        watch cluster-check

help:
	@echo '=== P1: Infrastructure ==='
	@echo 'make up             - Start and provision VMs'
	@echo 'make test           - Run verification script'
	@echo 'make status         - Show Vagrant VM status'
	@echo 'make halt           - Stop VMs'
	@echo 'make destroy        - Delete VMs and disks'
	@echo ''
	@echo '=== Kubernetes ==='
	@echo 'make cluster        - Full cluster overview'
	@echo 'make nodes          - Show nodes and IPs'
	@echo 'make node-info      - Describe all nodes'
	@echo 'make pods           - Show all pods'
	@echo 'make system-pods    - Show kube-system pods'
	@echo 'make deployments    - Show deployments'
	@echo 'make services       - Show services'
	@echo 'make ingress        - Show ingress resources'
	@echo 'make events         - Show Kubernetes events'
	@echo 'make watch          - Watch node status'
	@echo ''
	@echo '=== Diagnostics ==='
	@echo 'make k3s-status     - Check K3s services'
	@echo 'make logs-server    - Show server logs'
	@echo 'make logs-worker    - Show worker logs'
	@echo 'make cluster-check  - Run cluster health checks'

# ==================================================
# Infrastructure
# ==================================================

keys:
	@if [ ! -f confs/cluster_key ]; then \
		rm -f confs/cluster_key.pub; \
		ssh-keygen -q -t ed25519 -N '' -f confs/cluster_key; \
	fi
	@ssh-keygen -y -f confs/cluster_key > confs/cluster_key.pub

prepare:
	bash ../scripts/prepare.sh p1

check:
	bash ../scripts/check.sh p1

up: keys
	$(MAKE) prepare
	$(MAKE) check
	vagrant up --provider=libvirt
	$(MAKE) test

test:
	bash scripts/verify.sh

status:
	vagrant status

halt:
	vagrant halt

destroy:
	vagrant destroy -f

# ==================================================
# Kubernetes
# ==================================================

cluster:
	$(call kubectl,cluster-info)
	$(call kubectl,get nodes -o wide)
	$(call kubectl,get pods -A)

nodes:
	$(call kubectl,get nodes -o wide)

node-info:
	$(call kubectl,describe nodes)

pods:
	$(call kubectl,get pods -A -o wide)

system-pods:
	$(call kubectl,get pods -n kube-system -o wide)

deployments:
	$(call kubectl,get deployments -A)

services:
	$(call kubectl,get services -A)

ingress:
	$(call kubectl,get ingress -A)

events:
	$(call kubectl,get events -A --sort-by=.metadata.creationTimestamp)

watch:
	vagrant ssh $(SERVER) -c "sudo k3s kubectl get nodes -w"

# ==================================================
# K3s Diagnostics
# ==================================================

k3s-status:
	@echo '=== K3s Server ==='
	vagrant ssh $(SERVER) -c "systemctl is-active k3s"
	@echo '=== K3s Worker ==='
	vagrant ssh $(WORKER) -c "systemctl is-active k3s-agent"

logs-server:
	vagrant ssh $(SERVER) -c "sudo journalctl -u k3s -n 50 --no-pager"

logs-worker:
	vagrant ssh $(WORKER) -c "sudo journalctl -u k3s-agent -n 50 --no-pager"

# ==================================================
# Cluster Health
# ==================================================

cluster-check:
	@echo '=== Vagrant ==='
	vagrant status
	@echo ''
	@echo '=== K3s Services ==='
	$(MAKE) k3s-status
	@echo ''
	@echo '=== Kubernetes Nodes ==='
	$(call kubectl,get nodes -o wide)
	@echo ''
	@echo '=== Kubernetes System Pods ==='
	$(call kubectl,get pods -n kube-system)
	@echo ''
	@echo '=== Kubernetes Events ==='
	$(call kubectl,get events -A --sort-by=.metadata.creationTimestamp)
