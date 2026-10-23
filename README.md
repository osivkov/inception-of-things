# Inception-of-Things (IoT)

This repository contains configurations for the three mandatory environments and the optional GitLab environment from the **Inception-of-Things subject v4.0**. Run the lab inside the external Debian VM. P1 and P2 provision Vagrant guests inside it; P3 and bonus run K3s through K3d and Docker in that same Debian VM.

| Part | Purpose | Entry point |
| --- | --- | --- |
| P1 | Two K3s nodes: controller `osivkovS` and agent `osivkovSW` | Root `Makefile`, `PART=p1` |
| P2 | One K3s server, three web apps, Host-based Traefik Ingress | Root `Makefile`, `PART=p2` |
| P3 | K3d, Argo CD, GitHub-managed One More Cup in `dev` | `p3/Makefile` |
| Bonus | Local GitLab, Helm release, GitLab-managed One More Cup | `bonus/scripts/up.sh` |

See [DEVELOPER.md](DEVELOPER.md) for architecture, configuration, storage and troubleshooting. The source of the single Argo CD Application `argocd/playground` is **either** GitHub (P3) **or** local GitLab (bonus); running one setup after the other changes that source.

## Where commands run

- **Codam host:** edit files, use a browser, and create SSH tunnels. The host has no `sudo`; do not install or launch Vagrant, Docker or K3d there.
- **External Debian VM (`vbox`):** run root Make targets, P3 and bonus commands, Docker, K3d, Helm and `kubectl`. Installation and libvirt preparation require `sudo` on this VM. All unqualified shell blocks below run here.
- **Vagrant guest:** P1/P2 K3s and guest-level `kubectl` commands run through `vagrant ssh` from the Debian VM. P3 and bonus have no Vagrant guest.

The P1/P2 `192.168.56.0/24` libvirt network is private to the Debian VM. From the Codam host, reach P2 through an SSH tunnel to the Debian VM if direct routing is unavailable:

```bash
# Codam host; keep this terminal open. Replace the SSH address.
ssh -L 18080:192.168.56.110:80 osivkov@DEBIAN_VM_ADDRESS
# Codam host, another terminal:
curl -H 'Host: app2.com' http://127.0.0.1:18080/
```

For P3/bonus, start the documented VM-local port forwards, then tunnel their loopback ports from Codam:

```bash
# Codam host; keep this terminal open.
ssh -L 9090:127.0.0.1:9090 -L 8888:127.0.0.1:8888 -L 8080:127.0.0.1:8080 osivkov@DEBIAN_VM_ADDRESS
```

The tunnel alone does not start a Kubernetes Service port forward. Port `8080` is the K3d load balancer mapping used by the GitLab Ingress; `9090` and `8888` need the `make ui` and `make app` commands on the Debian VM. Use free local ports or change the left side of an `-L` mapping.

## Prerequisites

- **Debian VM:** Debian 13 in this setup, internet access for packages and images, sufficient free RAM/disk, and `sudo` for preparation and installation. Run one resource-heavy part at a time; check `free -h` and `df -h /` before starting Vagrant or GitLab.
- **P1/P2:** Vagrant with `vagrant-libvirt`, QEMU/KVM, system libvirt (`qemu:///system`), nested virtualization, `virsh`, and a working `sudo`. The root `Makefile` does **not** install these tools. `scripts/prepare.sh` configures `iotnet` and an Intel EPT workaround (`ept=0`); `scripts/check.sh` checks prerequisites. Stop running libvirt guests before a required KVM module reload. Check `/sys/module/kvm_intel/parameters/ept` for `N` after preparation.
- **P3:** Docker, K3d and kubectl. From `p3`, `make install` installs these with `sudo`; after Docker group membership changes, log out and back into the Debian VM, then verify `docker info`. The installed tool versions are pinned in `p3/scripts/install.sh`.
- **Bonus:** P3 prerequisites plus Helm (`bash bonus/scripts/install-helm.sh` from the repository root) and Python 3. Its GitLab chart requests 2 GiB RAM and permits up to 4 GiB; leave headroom before starting it. A user must create a GitLab personal access token with the `api` scope for bootstrap. Never put it in Git or shell history; the bootstrap script prompts without echo.

P1 needs a local SSH key pair in `p1/confs/cluster_key` and `.pub` before provisioning. From the **Debian VM repository root**, create it only if absent:

```bash
if [ ! -f p1/confs/cluster_key ]; then ssh-keygen -t ed25519 -N '' -f p1/confs/cluster_key; fi
if [ ! -f p1/confs/cluster_key.pub ]; then ssh-keygen -y -f p1/confs/cluster_key > p1/confs/cluster_key.pub; fi
```

These files are ignored by Git. Do not replace an existing private key while a P1 cluster uses it.

## P1: two-node K3s

P1 and P2 both assign `192.168.56.110` to `osivkovS`, so halt one before starting the other.

```bash
# Debian VM, repository root; this starts Vagrant guests. Do not run on a constrained VM.
make up PART=p1
make status PART=p1
cd p1
vagrant ssh osivkovS -c 'sudo k3s kubectl get nodes -o wide'
vagrant ssh osivkovS -c 'sudo systemctl is-active k3s'
vagrant ssh osivkovSW -c 'sudo systemctl is-active k3s-agent'
```

**Expected:** two Vagrant guests, server `192.168.56.110` and worker `192.168.56.111`, both Kubernetes nodes `Ready`, and both services `active`. From `p1` on the Debian VM, `vagrant ssh osivkovS` and `vagrant ssh osivkovSW` should require no guest password. The worker obtains its K3s join token over SSH from the server. A completed `vagrant up` is not proof of two ready nodes.

```bash
# Debian VM, repository root (after returning from p1):
make halt PART=p1
# Later: make up PART=p1
```

A regular `vagrant up` of an existing guest may skip provisioning. After changing P1 scripts, use `cd p1 && vagrant provision` on the Debian VM, then recheck node readiness.

## P2: three apps and Ingress

```bash
# Debian VM, repository root; starts one Vagrant guest.
make up PART=p2
make status PART=p2
cd p2
vagrant ssh osivkovS -c 'sudo k3s kubectl get deployments,services,ingress'
vagrant ssh osivkovS -c 'sudo k3s kubectl get deployment app2'
curl -fsS -H 'Host: app1.com' http://192.168.56.110/
curl -fsS -H 'Host: app2.com' http://192.168.56.110/
curl -fsS -H 'Host: unknown.example' http://192.168.56.110/
```

**Expected:** `app1` serves HTML containing `Hello from app1`, `app2` returns `Hello from app2` and has `3/3` ready replicas, and any other Host returns `Hello from app3`. All three Deployments and Services plus Ingress `apps` are in the guest's `default` namespace. Verify the ingress rules explicitly with `vagrant ssh osivkovS -c 'sudo k3s kubectl describe ingress apps'` from `p2` on the Debian VM.

```bash
# Debian VM, repository root (after returning from p2):
make halt PART=p2
# Later: make up PART=p2
# After manifest/script edits: cd p2 && vagrant provision osivkovS
```

The P2 script assumes the private interface is `eth1`; check the actual guest interface name if the node or routes fail.

## P3: GitHub to Argo CD

```bash
# Debian VM, repository root; install once if required:
cd p3
make install
# Log out/in if Docker group membership was just changed, then return to p3.
docker info
make up
make status
kubectl --context=k3d-iot -n argocd get application playground -o wide
kubectl --context=k3d-iot -n dev get deployment,service,pods
```

**Expected when P3 is selected:** `argocd` and `dev` namespaces, one ready `playground` replica, and Application `Synced/Healthy` with source `https://github.com/osivkov/inception-of-things.git`, branch `main`, path `p3/confs/application`. The checked-in Deployment uses `osivkov/one-more-cup:v2` on port `8888`. The Kubernetes resource is still named `playground`.

In separate Debian VM terminals, from `p3` run `make ui` and `make app`. Open `https://localhost:9090` for Argo CD (`admin` and the locally stored initial password if still valid) and `http://localhost:8888/` for One More Cup. From Codam use the SSH tunnel above. `make password` prints a secret; run it privately only when needed. The Argo CD certificate may be self-signed. Check the release and HTTP health from another Debian VM terminal:

```bash
curl -fsS http://127.0.0.1:8888/version.json
curl -fsS http://127.0.0.1:8888/healthz
```

Expect `{"version":"v2"}` and `ok` for the checked-in v2 manifest. Both `make ui` and `make app` run until Ctrl-C. The app's source and Dockerfile are in `p3/app/one-more-cup/`; its two published Docker Hub tags are `osivkov/one-more-cup:v1` and `osivkov/one-more-cup:v2`. V1 has a green theme and `FIRST BREW / 001` label; v2 has a terracotta theme and `SLOW ROAST / 002` label. Both expose the same timer and task features. Their `/version.json` responses distinguish the releases over HTTP.

To demonstrate GitOps, change the image tag in `p3/confs/application/deployment.yaml` from `v2` to `v1`, commit and push to GitHub `main`, then verify the Application revision, Deployment image, rollout, and `/version.json` response. Repeat with `v2` to show the reverse update. A local edit alone does not update Argo CD.

```bash
# Debian VM, p3 directory:
make stop
# Later: make up  # also selects the GitHub Application source
```

`make up` re-applies the P3 Application definition. If bonus is active, this switches the single Application back to GitHub.

## Bonus: local GitLab

The bonus uses a custom Helm chart, **release `gitlab` in namespace `gitlab`**, and a public GitLab project `osivkov/iot` created by its bootstrap script. It reuses the P3 `dev` Deployment and Service.

```bash
# Debian VM, repository root, only if Helm is missing:
bash bonus/scripts/install-helm.sh
# First setup: creates/starts P3 infrastructure, installs GitLab, then stops before bootstrap.
bash bonus/scripts/up.sh --setup-only
```

Open `http://localhost:8080` in the Debian VM, or use the Codam tunnel. Log in with the GitLab credentials created for this instance; create a personal access token with `api` scope in the GitLab UI. The script does not create the token. Then:

```bash
# Debian VM, repository root:
bash bonus/scripts/up.sh
kubectl --context=k3d-iot -n gitlab get deployment,service,ingress,pvc
kubectl --context=k3d-iot -n argocd get application playground -o wide
kubectl --context=k3d-iot -n dev get deployment,service,pods
```

**Expected:** GitLab Deployment `1/1`, three bound PVCs, GitLab HTTP on `localhost:8080`, and `playground` `Synced/Healthy` from `http://gitlab.gitlab.svc.cluster.local/osivkov/iot.git` at branch `main`, path `.`. The GitLab project's `deployment.yaml` currently selects `osivkov/one-more-cup:v2`; edit and commit that file in GitLab to demonstrate a bonus version update. Editing `bonus/confs/application/deployment.yaml` locally does not change an existing GitLab project. Use `curl -H 'Host: localhost' http://127.0.0.1:8080/` if checking the loopback IP: the Ingress only matches Host `localhost`. `bootstrap-gitlab.py` prompts for the token and seeds two manifests only when the repository is empty. If the project already has commits, inspect its `main` branch yourself; rerunning bootstrap will not update it. The `GITLAB_GROUP` and `GITLAB_PROJECT` environment overrides do not update the hard-coded Argo CD URL.

**Current deployment (checked 2026-10-23):** the active Application source is the local GitLab project. Argo CD reports `Synced/Healthy`; the ready `dev/playground` Pod runs `osivkov/one-more-cup:v2` and serves `{"version":"v2"}` from `/version.json`. Both Docker Hub tags are published.

To switch sources in a **running** cluster without repeating installation, run `make source-p3` or `make source-bonus` from `p3` on the Debian VM. These targets apply the corresponding Application definition and request a hard refresh; confirm `.spec.source.repoURL` afterward. For a stopped cluster, use `make up` from `p3` to start with GitHub or `bash bonus/scripts/up.sh` from the repository root to start with GitLab. Do not run the setup commands concurrently. `--setup-only` leaves the current Application source as it was but still starts P3 and upgrades GitLab.

Stop P3 and bonus together with `cd p3 && make stop` on the Debian VM; this preserves the existing K3d cluster and Docker-backed data while stopped. Restart with the setup command matching the source you want. **Do not delete the cluster or PVCs as a stop procedure.** Back up GitLab data outside the cluster before any migration or destructive operation; see [DEVELOPER.md](DEVELOPER.md#storage-backup-and-restore).
