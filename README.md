# Inception-of-Things

A small Kubernetes lab built in stages: two virtual machines running K3s, three applications behind an Ingress, then GitOps with Argo CD and a local GitLab instance.

| Part | What runs | Start from the repository root |
| --- | --- | --- |
| P1 | A K3s server and agent in two Vagrant VMs | `make -C p1 up` |
| P2 | One VM, three applications and Traefik Ingress | `make -C p2 up` |
| P3 | K3d, Argo CD and One More Cup deployed from GitHub | `make -C p3 up` |
| Bonus | Local GitLab in the P3 cluster | `bash bonus/scripts/up.sh --setup-only` |

This guide covers setup and daily use. For the scripts, component versions, troubleshooting and configuration changes, see [DEVELOPER.md](DEVELOPER.md).

## Where everything runs

The lab has three layers:

```text
Codam computer — Ubuntu 22.04, VirtualBox
└── Debian 13 — the outer VM, where this repository lives
    ├── P1 or P2 — Vagrant VMs using libvirt / QEMU / KVM
    └── P3 and bonus — a K3d cluster in Docker
```

**Run the commands below inside Debian** unless stated otherwise. The Codam computer is used for the editor, terminal and browser. Package installation and libvirt run inside Debian, where `sudo` is available.

P1 and P2 share the server address `192.168.56.110`, so they must run separately. P3 and bonus share the `iot` cluster and the Argo CD Application `playground`; switching between them changes the source of the application manifests.

## Hardware and resource allocation

The Codam computer has an i7-12700T, about 15 GiB RAM and 4 GiB swap. The outer Debian VM has 8 vCPU and 8 GiB RAM, with 2 GiB swap and a root filesystem of roughly 60 GiB. These are the resources of this lab, rather than minimum requirements for every machine.

Each part's allocation comes from the [P1 Vagrantfile](p1/Vagrantfile), [P2 Vagrantfile](p2/Vagrantfile), [K3d configuration](p3/confs/cluster.yaml) and [GitLab Deployment](bonus/charts/gitlab/templates/deployment.yaml):

| Component | CPU | RAM | Disk / persistent data |
| --- | --- | --- | --- |
| P1 `osivkovS` | 2 vCPU | 2048 MiB | Virtual disk from the Vagrant box |
| P1 `osivkovSW` | 1 vCPU | 1024 MiB | A separate disk from the same box |
| P2 `osivkovS` | 3 vCPU | 3072 MiB | Virtual disk from the Vagrant box |
| P3 `iot` | No explicit limit | No explicit limit | K3s data in Docker; 1 server, 0 agents |
| Bonus GitLab | request: 1 CPU; limit: 4 CPU | request: 2 GiB; limit: 4 GiB | PVCs: 1 GiB config, 10 GiB data, 2 GiB logs |

P1 allocates 3 GiB of guest RAM in total; P2 also allocates 3 GiB. Debian and virtualization need additional memory. In P3, K3s, Argo CD and the application share the available resources, with GitLab added for the bonus. GitLab's 2 GiB request applies to its container alone. PVC sizes are requested capacity, not the amount of data already stored.

K3d also creates a load balancer container for the published port. It uses resources from Debian alongside the server container.

P1/P2 disk sizes are not set explicitly in the Vagrantfiles; they depend on the box. Check available memory and disk space before downloading images or starting GitLab:

```bash
free -h
df -h /
```

The inner VMs use memory allocated to the outer Debian VM. Do not add the inner QEMU memory to VirtualBox's host memory a second time. For sequential evaluations, stop the previous part before starting the next one.

## Before the first run

P1/P2 require Vagrant, the `vagrant-libvirt` plugin, QEMU/KVM, libvirt, `virsh`, `make` and the OpenSSH client. They also need access to `qemu:///system` and nested virtualization. This repository does not include an installer for these dependencies.

```bash
vagrant --version
vagrant plugin list
virsh -c qemu:///system list --all
```

P3 installs its dependencies with `make -C p3 install`: Docker, Python 3, k3d and kubectl. The bonus also needs Helm. The first run needs internet access to download packages, the Vagrant box and container images.

> P1/P2 `prepare.sh` changes Intel KVM EPT across the outer Debian VM and persists the setting in `/etc/modprobe.d/iot-kvm.conf`. All active libvirt VMs must be stopped before the KVM module can be reloaded. See the [nested virtualization notes](DEVELOPER.md#nested-virtualization) for details and limitations.

Vagrant manages host-to-guest SSH in both parts. P1 also uses `p1/confs/cluster_key` so the worker can fetch the server's join token over SSH. **Keep existing P1 keys.** In a fresh clone, `make -C p1 up` creates them if they are missing. P2 does not need a separate `cluster_key` pair. These lab keys are separate from personal Git SSH keys.

## P1 — server and worker

From the repository root:

```bash
make -C p1 up
```

This prepares the keys, runs network preparation and environment checks, starts the VMs through libvirt, and runs `make test`. The server uses `192.168.56.110`; the worker uses `192.168.56.111`.

After startup, inspect the lab:

```bash
make -C p1 status
make -C p1 nodes
make -C p1 system-pods
```

Expect both VMs to be `running`, two Kubernetes nodes to be `Ready`, and the system Pods to be healthy. `Completed` is normal for finished installation Jobs. `make -C p1 test` checks SSH, guest names and IPs, K3s services and two Ready nodes; inspect all system Pods separately.

For an interactive SSH session, run `vagrant ssh osivkovS` or `vagrant ssh osivkovSW` from `p1`. Run administrative Kubernetes commands on the server:

```bash
(cd p1 && vagrant ssh osivkovS -c 'sudo k3s kubectl get nodes -o wide')
```

> On the worker, plain `kubectl` may connect to `localhost:8080` and return `connection refused`. Without an administrative kubeconfig, that is expected. Check the agent through `k3s-agent` and the server's node list.

Stop with `make -C p1 halt`; start again with `make -C p1 up`. After editing provisioning scripts, run `vagrant provision` from `p1`, then `make test` in that directory. A regular `up` may skip provisioners on an existing VM.

## P2 — three applications and Ingress

Stop P1 before starting P2:

```bash
make -C p1 halt
make -C p2 up
```

The VM runs three Deployments and three `ClusterIP` Services. Traefik selects an application using the HTTP `Host` header:

| Request | Response | Replicas |
| --- | --- | --- |
| `Host: app1.com` | HTML containing `Hello from app1` | 1 |
| `Host: app2.com` | `Hello from app2` | 3 |
| Any other Host, or a request to the IP | `Hello from app3` | 1 |

```bash
make -C p2 replicas
make -C p2 ingress-details
make -C p2 http-test
```

`make -C p2 test` checks the VM, K3s service and node, application rollouts, three ready app2 replicas and all three HTTP routes. During evaluation, `replicas` and `ingress-details` show the configuration behind those HTTP responses.

You do not need DNS entries to test these names. From Debian:

```bash
curl -H 'Host: app1.com' http://192.168.56.110/
curl -H 'Host: app2.com' http://192.168.56.110/
curl http://192.168.56.110/
```

If the private IP is not reachable from the Codam computer, open an SSH tunnel **on Codam** and leave it running. Replace `DEBIAN_VM_ADDRESS` with the outer VM's address:

```bash
ssh -L 18080:192.168.56.110:80 osivkov@DEBIAN_VM_ADDRESS
```

In another Codam terminal, run `curl -H 'Host: app2.com' http://127.0.0.1:18080/`. Opening `http://127.0.0.1:18080/` in a browser without changing the Host header shows app3, the default route.

Stop with `make -C p2 halt`. After editing manifests, run `vagrant provision osivkovS` from `p2` and repeat `make test`.

## P3 — GitHub and Argo CD

If the tools are not installed yet:

```bash
make -C p3 install
```

If the installer added your user to the Docker group, disconnect from the Debian SSH session and log in again. Then check access and start the cluster:

```bash
docker info
make -C p3 up
make -C p3 status
```

This creates or starts `iot`. Argo CD runs in namespace `argocd`, and One More Cup is deployed in `dev`. The application's resources are named `playground`. Argo CD reads branch `main`, path `p3/confs/application`, from the public [GitHub repository](https://github.com/osivkov/inception-of-things).

A successful startup verifies that the Application is `Synced` and `Healthy`, the Deployment is ready, `/healthz` returns `ok` inside the container, and `/version.json` reports `v1` or `v2`. Repeat these checks with `make -C p3 verify`.

### Open the application and Argo CD

Run these in two separate Debian terminals:

```bash
make -C p3 app
```

```bash
make -C p3 ui
```

Both commands keep running until `Ctrl-C`. The application is at `http://localhost:8888`; Argo CD is at `https://localhost:9090`. The Argo CD username is `admin`. Run `make -C p3 password` to read the initial password; it may no longer work if the password has been changed. The browser may warn about Argo CD's local self-signed certificate.

**Here, `localhost` means Debian.** To use a browser on Codam, also start this tunnel on Codam:

```bash
ssh -L 8888:127.0.0.1:8888 -L 9090:127.0.0.1:9090 osivkov@DEBIAN_VM_ADDRESS
```

Then open the same addresses in the Codam browser. Keep both `make app` and `make ui` running in Debian as well as the tunnel.

### Demonstrate an update from v1 to v2

In `p3/confs/application/deployment.yaml`, change the image from `osivkov/one-more-cup:v1` to `osivkov/one-more-cup:v2`. From the repository root, push the change to GitHub:

```bash
git add p3/confs/application/deployment.yaml
git commit -m "Switch application to v2"
git push origin main
```

Here, `origin` must point to the GitHub repository configured in the Argo CD Application. Check it with `git remote -v`. Pushing only to Vogsphere will not update the application, because Argo CD reads GitHub.

Wait for synchronization, then check the revision, image and HTTP response:

```bash
make -C p3 verify
make -C p3 status
curl -fsS http://127.0.0.1:8888/version.json
```

Keep `make app` running for the `curl` request. The response should contain `"version":"v2"`, allowing for JSON whitespace. A local edit without a push will not reach Argo CD. Switch back to `v1` with another commit to demonstrate the reverse update.

The application is pulled from Docker Hub. Its build sources are not in the current repository tree, so startup depends on the published tags `osivkov/one-more-cup:v1` and `v2`.

Stop the cluster with `make -C p3 stop`. The next `make -C p3 up` selects GitHub as the source again.

## Bonus — local GitLab

The bonus adds GitLab to the same cluster using a local Helm chart. Prepare the installation:

```bash
make -C p3 install-helm
make -C p3 bonus-setup
```

Open `http://localhost:8080` in Debian. For a Codam browser, start this tunnel on Codam: `ssh -L 8080:127.0.0.1:8080 osivkov@DEBIAN_VM_ADDRESS`.

For a new installation, the GitLab username is `root`. Read the initial password inside the container in a private terminal:

```bash
kubectl --context=k3d-iot -n gitlab exec deploy/gitlab -- grep 'Password:' /etc/gitlab/initial_root_password
```

The initial password file is temporary. If it is gone, use the current password. See the [GitLab installation guide](https://docs.gitlab.com/install/docker/installation/) for details.

In GitLab, create a personal access token with the `api` scope. Then run:

```bash
make -C p3 bonus-up
make -C p3 status
```

The script prompts for the token without displaying it, creates the public group `osivkov` and project `iot` if needed, and seeds manifests only into an empty repository. Keep the token out of project files and command arguments.

The Application source becomes `http://gitlab.gitlab.svc.cluster.local/osivkov/iot.git`. To demonstrate a version update, edit `deployment.yaml` and commit it **in that GitLab project**. The local files in `bonus/confs/application/` are only the initial seed; editing them does not overwrite an existing GitLab repository.

Switch sources in a running cluster with:

```bash
make -C p3 source-p3       # GitHub
make -C p3 source-bonus    # GitLab, already installed and bootstrapped
```

`make -C p3 stop` stops P3 and the bonus together while preserving data.

## Stopping and preparing for the next evaluation

| Action | P1 | P2 | P3 and bonus |
| --- | --- | --- | --- |
| Inspect status | `make -C p1 status` | `make -C p2 status` | `make -C p3 status` |
| Stop and preserve data | `make -C p1 halt` | `make -C p2 halt` | `make -C p3 stop` |
| Delete the environment | `make -C p1 destroy` | `make -C p2 destroy` | `k3d cluster delete iot` |

Delete VMs from the clone that created them. After `destroy` or `delete`, check the actual resources:

```bash
virsh -c qemu:///system list --all
k3d cluster list
docker ps -a
docker volume ls
```

The project domains are normally `p1_osivkovS`, `p1_osivkovSW` and `p2_osivkovS`. A fresh clone does not know about an old clone's VMs: an empty local `vagrant status` does not mean libvirt is empty. Keep the old `.vagrant` while its VMs exist. See the [maintenance guide](DEVELOPER.md#cleanup-between-evaluations) for finding leftover disks.

Deleting `iot` removes local GitLab data. The PVC retention annotation used for Helm uninstall does not protect against deletion of the cluster itself. Keep P1 keys. Downloaded Vagrant boxes and Docker images can remain as a cache; to reclaim space, inspect `docker image ls` and remove specific project images.

Start the next part with its usual command: `make -C p1 up`, `make -C p2 up` or `make -C p3 up`. P1/P2 prepare `iotnet` automatically. There is no root Makefile.

## Resources

These references explain the components used in the lab and the concepts covered during evaluation:

| Topic | Reference |
| --- | --- |
| VM lifecycle and provisioning | [Vagrant](https://developer.hashicorp.com/vagrant/docs), [vagrant-libvirt](https://vagrant-libvirt.github.io/vagrant-libvirt/) |
| Server and agent roles, K3s components | [K3s architecture](https://docs.k3s.io/architecture), [requirements](https://docs.k3s.io/installation/requirements) |
| Running K3s in Docker | [k3d configuration files](https://k3d.io/stable/usage/configfile/) |
| Routing HTTP requests to an application | [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) |
| Automated sync, prune and selfHeal | [Argo CD Automated Sync](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/) |
| First GitLab startup | [GitLab container installation](https://docs.gitlab.com/install/docker/installation/) |
| Saving and restoring GitLab | [Backup](https://docs.gitlab.com/administration/backup_restore/backup_gitlab/), [restore](https://docs.gitlab.com/administration/backup_restore/restore_gitlab/) |
