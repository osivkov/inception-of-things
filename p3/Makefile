.DEFAULT_GOAL := help

.PHONY: help install up stop status ui app

help:
	@echo "make install — install Docker, k3d and kubectl"
	@echo "make up      — start the cluster and configure Argo CD"
	@echo "make stop    — stop the cluster without deleting it"
	@echo "make status  — show cluster and application status"
	@echo "make ui      — forward Argo CD to https://localhost:9090"
	@echo "make app     — forward the application to http://localhost:8888"

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
