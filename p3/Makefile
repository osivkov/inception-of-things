.DEFAULT_GOAL := help

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

CONTEXT ?= k3d-iot
KUBECTL := kubectl --context=$(CONTEXT)

APP_DIR := app/one-more-cup
IMAGE ?= osivkov/one-more-cup
VERSION ?= v1
PLATFORM ?= linux/amd64

install:
	sudo bash scripts/install.sh

install-helm:
	bash ../bonus/scripts/install-helm.sh

up:
	bash scripts/up.sh
	$(MAKE) verify

bonus-setup:
	bash ../bonus/scripts/up.sh --setup-only

bonus-up:
	bash ../bonus/scripts/up.sh
	$(MAKE) verify

stop:
	k3d cluster stop iot

status:
	k3d cluster list
	$(KUBECTL) get nodes
	$(KUBECTL) -n argocd get application playground
	@$(KUBECTL) -n argocd get application playground \
		-o jsonpath='Source: {.spec.source.repoURL}{"\n"}Path: {.spec.source.path}{"\n"}Revision: {.status.sync.revision}{"\n"}'
	@$(KUBECTL) -n dev get deployment playground \
		-o jsonpath='Image: {.spec.template.spec.containers[0].image}{"\n"}'
	$(KUBECTL) -n dev get deployments,pods,services
	@if $(KUBECTL) get namespace gitlab >/dev/null 2>&1; then \
		$(KUBECTL) -n gitlab get pods,pvc,services,ingresses; \
	fi

verify:
	$(KUBECTL) -n argocd wait application/playground \
		--for=jsonpath='{.status.sync.status}'=Synced --timeout=300s
	$(KUBECTL) -n argocd wait application/playground \
		--for=jsonpath='{.status.health.status}'=Healthy --timeout=300s
	$(KUBECTL) -n dev rollout status deployment/playground --timeout=180s
	@echo "Checking the application inside its container..."
	@$(KUBECTL) -n dev exec deployment/playground -- \
		wget -q -T 10 -O - http://127.0.0.1:8888/healthz | grep -x 'ok'
	@$(KUBECTL) -n dev exec deployment/playground -- \
		wget -q -T 10 -O - http://127.0.0.1:8888/version.json | \
		python3 -c 'import json,sys; v=json.load(sys.stdin)["version"]; assert v in ("v1","v2"), v; print("Application version:", v)'
	@echo "PASS: Argo CD status, rollout and container HTTP checks."

source-p3:
	$(KUBECTL) apply -f confs/argocd-application.yaml
	$(KUBECTL) -n argocd annotate application playground \
		argocd.argoproj.io/refresh=hard --overwrite
	$(MAKE) verify

source-bonus:
	$(KUBECTL) -n gitlab rollout status deployment/gitlab --timeout=600s
	$(KUBECTL) apply -f ../bonus/confs/argocd-application.yaml
	$(KUBECTL) -n argocd annotate application playground \
		argocd.argoproj.io/refresh=hard --overwrite
	$(MAKE) verify

ui:
	$(KUBECTL) -n argocd port-forward svc/argocd-server 9090:443

app:
	$(KUBECTL) -n dev rollout status deployment/playground --timeout=180s
	$(KUBECTL) -n dev port-forward svc/playground 8888:8888

# This is the initial password, not necessarily the current password.
password:
	@$(KUBECTL) -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 --decode
	@echo

# Build the application image from local source files.
image-build:
	test -f "$(APP_DIR)/releases/$(VERSION).json"
	docker build --platform "$(PLATFORM)" \
		--build-arg APP_VERSION="$(VERSION)" \
		-t "$(IMAGE):$(VERSION)" "$(APP_DIR)"

# Build and run the container smoke checks.
image-test: image-build
	cd "$(APP_DIR)" && \
		sh scripts/smoke-container.sh "$(IMAGE):$(VERSION)" "$(VERSION)" 18088

# Publish the image only after the smoke checks pass.
image-push: image-test
	docker push "$(IMAGE):$(VERSION)"

help:
	@echo "Run these commands from the p3 directory."
	@echo ""
	@echo "Installation:"
	@echo "  make install		Install Docker, k3d and kubectl"
	@echo "  make install-helm	Install Helm for the bonus"
	@echo ""
	@echo "Startup:"
	@echo "  make up			Start P3 and select the GitHub source"
	@echo "  make bonus-setup	Start GitLab before creating an API token"
	@echo "  make bonus-up		Start the bonus and select the GitLab source"
	@echo "  make stop			Stop the shared cluster without deleting it"
	@echo ""
	@echo "Inspection:"
	@echo "  make status		Show source, revision, image and workloads"
	@echo "  make verify		Check application readiness and HTTP responses"
	@echo ""
	@echo "Access in Debian; keep the command running:"
	@echo "  make app			Application: http://localhost:8888"
	@echo "  make ui			Argo CD: https://localhost:9090"
	@echo "  make password		Print the initial Argo CD admin password"
	@echo ""
	@echo "Switch an existing installation:"
	@echo "  make source-p3		Select GitHub and verify the application"
	@echo "  make source-bonus	Select GitLab and verify the application"
	@echo ""
	@echo "P3 and bonus share the same cluster and Application."
	@echo "Host-browser access also requires an SSH tunnel to Debian."

.PHONY: help install install-helm up bonus-setup bonus-up stop \
	status verify ui app password source-p3 source-bonus  image-build \
	image-test image-push