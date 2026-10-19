.DEFAULT_GOAL := help

.PHONY: help install up stop status ui app

help:
	@echo "make install — install Docker, k3d and kubectl"
	@echo "make up      — start the cluster and configure Argo CD"
	@echo "make stop    — stop the cluster without deleting it"
	@echo "make status  — show cluster and application status"
	@echo "make ui      — forward Argo CD to https://localhost:9090"
	@echo "make app     — forward the application to http://localhost:8888"
	@echo "make password -- print the initial Argo CD admin password"
install:
	sudo bash scripts/install.sh

up:
	bash scripts/up.sh

stop:
	k3d cluster stop iot

status:
	k3d cluster list
	kubectl --context=k3d-iot get applications -n argocd
	kubectl --context=k3d-iot get pods -n dev

ui:
	kubectl --context=k3d-iot -n argocd port-forward svc/argocd-server 9090:443

app:
	kubectl --context=k3d-iot -n dev port-forward svc/playground 8888:8888

# Print the initial admin password generated for this Argo CD installation.
# Secret values use Base64 encoding; decoding does not decrypt them.
# After changing the admin password, this initial value is no longer valid.
password:
	kubectl --context=k3d-iot -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode
	@echo
