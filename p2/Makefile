
.DEFAULT_GOAL := help

IP := 192.168.56.110

define kubectl
vagrant ssh -c "sudo k3s kubectl $(1)"
endef

.PHONY: help prepare check up test status halt destroy \
	cluster nodes pods system-pods deployments services \
	ingress ingress-details replicas endpoints \
	events k3s-status logs \
	curl-app1 curl-app2 curl-default http-test \
	all-checks

help:
	@echo '=== P2: Infrastructure ==='
	@echo 'make up               - Start VM and run tests'
	@echo 'make test             - Run verify.sh'
	@echo 'make status           - Vagrant status'
	@echo 'make halt             - Stop VM'
	@echo 'make destroy          - Delete VM and disk'
	@echo ''
	@echo '=== Kubernetes ==='
	@echo 'make cluster          - Cluster overview'
	@echo 'make nodes            - Show nodes'
	@echo 'make pods             - Show all pods'
	@echo 'make system-pods      - System pods'
	@echo 'make deployments      - All deployments'
	@echo 'make services         - All services'
	@echo 'make ingress          - Ingress rules'
	@echo 'make ingress-details  - Describe ingress'
	@echo 'make replicas         - App replica counts'
	@echo 'make endpoints        - Service endpoints'
	@echo 'make events           - Kubernetes events'
	@echo ''
	@echo '=== HTTP Routing ==='
	@echo 'make curl-app1        - Test app1.com'
	@echo 'make curl-app2        - Test app2.com'
	@echo 'make curl-default     - Test default app3'
	@echo 'make http-test        - Test HTTP routing'
	@echo ''
	@echo '=== Diagnostics ==='
	@echo 'make k3s-status       - K3s service status'
	@echo 'make logs             - Last 50 K3s logs'
	@echo 'make all-checks       - Run all checks'

# ==================================================
# Infrastructure
# ==================================================

prepare:
	bash ../scripts/prepare.sh p2

check:
	bash ../scripts/check.sh p2

up:
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

pods:
	$(call kubectl,get pods -A -o wide)

system-pods:
	$(call kubectl,get pods -n kube-system -o wide)

deployments:
	$(call kubectl,get deployments -A)

services:
	$(call kubectl,get services -A)

ingress:
	$(call kubectl,get ingress -A -o wide)

ingress-details:
	$(call kubectl,describe ingress -A)

replicas:
	$(call kubectl,get deployments -A)

endpoints:
	$(call kubectl,get endpointslices -A)

events:
	$(call kubectl,get events -A --sort-by=.metadata.creationTimestamp)

# ==================================================
# K3s Diagnostics
# ==================================================

k3s-status:
	vagrant ssh -c "systemctl is-active k3s"

logs:
	vagrant ssh -c "sudo journalctl -u k3s -n 50 --no-pager"

# ==================================================
# HTTP Host Routing
# ==================================================

curl-app1:
	curl -fsS -H "Host: app1.com" http://$(IP)/

curl-app2:
	curl -fsS -H "Host: app2.com" http://$(IP)/

curl-default:
	curl -fsS -H "Host: unknown.example" http://$(IP)/

http-test:
	@echo '=== APP1 ==='
	$(MAKE) curl-app1
	@echo ''
	@echo '=== APP2 ==='
	$(MAKE) curl-app2
	@echo ''
	@echo '=== DEFAULT APP3 ==='
	$(MAKE) curl-default

# ==================================================
# Full Overview
# ==================================================

all-checks:
	$(MAKE) test
	$(MAKE) cluster
	$(MAKE) deployments
	$(MAKE) services
	$(MAKE) ingress
	$(MAKE) replicas
	$(MAKE) endpoints
	$(MAKE) http-test
