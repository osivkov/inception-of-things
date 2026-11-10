
LIBVIRT := virsh -c qemu:///system
.DEFAULT_GOAL := help

SERVER := osivkovS
WORKER := osivkovSW

# Number of clean deployment cycles.
# Override with: make stress RUNS=10
RUNS ?= 10

define kubectl
vagrant ssh $(SERVER) -c "sudo k3s kubectl $(1)"
endef

.PHONY: help keys network prepare check up test \
        status halt destroy reset fresh stress \
        cluster nodes node-info pods system-pods \
        deployments services ingress events watch \
        k3s-status logs-server logs-worker cluster-check

# ==================================================
# Help
# ==================================================

help:
	@echo ''
	@echo '=============================================='
	@echo '  P1 - Vagrant / libvirt / K3s'
	@echo '=============================================='
	@echo ''
	@echo 'INFRASTRUCTURE'
	@echo '  make up             Start/provision VMs and verify'
	@echo '  make prepare        Prepare KVM and libvirt network'
	@echo '  make check          Check host environment'
	@echo '  make keys           Generate P1 SSH cluster keys'
	@echo '  make network        Create/start iotnet network'
	@echo '  make status         Show Vagrant VM status'
	@echo '  make halt           Stop P1 VMs'
	@echo '  make destroy        Destroy P1 VMs and disks'
	@echo ''
	@echo 'CLEAN DEPLOYMENT'
	@echo '  make reset          Remove P1 VMs, network and state'
	@echo '  make fresh          Reset and deploy P1 from zero'
	@echo '  make stress         Run 10 clean deployment cycles'
	@echo '  make stress RUNS=3  Run 3 clean deployment cycles'
	@echo ''
	@echo 'KUBERNETES'
	@echo '  make cluster        Full cluster overview'
	@echo '  make nodes          Show cluster nodes and IPs'
	@echo '  make node-info      Describe all nodes'
	@echo '  make pods           Show pods in all namespaces'
	@echo '  make system-pods    Show kube-system pods'
	@echo '  make deployments    Show all deployments'
	@echo '  make services       Show all services'
	@echo '  make ingress        Show ingress resources'
	@echo '  make events         Show cluster events'
	@echo '  make watch          Watch node status'
	@echo ''
	@echo 'DIAGNOSTICS'
	@echo '  make test           Run P1 verification script'
	@echo '  make cluster-check  Show cluster health overview'
	@echo '  make k3s-status     Check K3s systemd services'
	@echo '  make logs-server    Show last 50 server log lines'
	@echo '  make logs-worker    Show last 50 worker log lines'
	@echo ''
	@echo 'EXAMPLES'
	@echo '  make fresh'
	@echo '  make stress RUNS=10'
	@echo '  make nodes'
	@echo '  make cluster-check'
	@echo ''

# ==================================================
# Infrastructure
# ==================================================

keys:
	@if [ ! -f confs/cluster_key ]; then \
		rm -f confs/cluster_key.pub; \
		ssh-keygen -q -t ed25519 -N '' -f confs/cluster_key; \
	fi
	@ssh-keygen -y -f confs/cluster_key > confs/cluster_key.pub

network:
	@$(LIBVIRT) net-info iotnet >/dev/null 2>&1 || \
		$(LIBVIRT) net-define confs/iotnet.xml
	@$(LIBVIRT) net-autostart iotnet
	@$(LIBVIRT) net-info iotnet | grep -q 'Active: *yes' || \
		$(LIBVIRT) net-start iotnet

prepare:
	bash ../scripts/prepare.sh p1

check:
	bash ../scripts/check.sh p1

up: keys
	$(MAKE) prepare
	$(MAKE) check
	vagrant up --provider=libvirt --provision
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
# Clean Deployment / Stress Testing
# ==================================================

reset: keys
	bash scripts/reset.sh

fresh: reset
	$(MAKE) up

stress:
	@case "$(RUNS)" in \
		''|*[!0-9]*|0) \
			echo "ERROR: RUNS must be a positive integer"; \
			exit 1 ;; \
	esac
	@set -e; \
	i=1; \
	while [ "$$i" -le "$(RUNS)" ]; do \
		echo ""; \
		echo "=========================================="; \
		echo " P1 CLEAN DEPLOYMENT $$i / $(RUNS)"; \
		echo "=========================================="; \
		if $(MAKE) fresh; then \
			echo "PASS: deployment $$i / $(RUNS)"; \
		else \
			echo "FAIL: deployment $$i / $(RUNS)"; \
			exit 1; \
		fi; \
		i=$$((i + 1)); \
	done
	@echo ''
	@echo 'All deployment cycles passed.'

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
