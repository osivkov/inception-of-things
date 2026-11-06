*This project has been created as part of the 42 curriculum by osivkov, iriadyns.*

# Inception-of-Things

## Description

This repository contains our Inception-of-Things project. P1 builds a Kubernetes cluster from two Vagrant VMs: a **server node (control plane)** and a **worker node (K3s agent)**. P2 uses a single server node to run three applications behind an Ingress. P3 moves to a local k3d cluster with Argo CD, and the bonus adds GitLab to that cluster.

Inception-of-Things is a system administration project from the **42 advanced curriculum**. Its goal is to understand Kubernetes through a working lab: provision machines, connect server and agent nodes, route HTTP requests to applications, and deploy versioned workloads from Git.

| Part | What runs | Working directory | Start command |
| --- | --- | --- | --- |
| P1 | A server node and a worker node in two Vagrant VMs | `p1/` | `make up` |
| P2 | One server node, three applications and Traefik Ingress | `p2/` | `make up` |
| P3 | K3d, Argo CD and One More Cup deployed from GitHub | `p3/` | `make up` |
| Bonus | Local GitLab in the P3 cluster | `p3/` | `make bonus-setup`, then `make bonus-up` after token setup |

Use this README to start each part and demonstrate the required behavior. For implementation details and troubleshooting, see [DEVELOPER.md](DEVELOPER.md).

### Contributors

This project was developed by **osivkov** and **iriadyns**.


### Project layout and commands

P1, P2 and P3 each have their own `Makefile`, which provides shortcuts for starting the environment, checking its status and running tests. The targets call the Vagrant, K3s, k3d and Kubernetes commands used by that part. The bonus is managed through `p3/Makefile` and scripts in `bonus/`; it has no separate Makefile.

| Directory | Purpose |
| --- | --- |
| `p1/` | Two Vagrant VMs: a K3s server node and a worker node |
| `p2/` | One K3s server node with three applications and Ingress |
| `p3/` | k3d cluster, Argo CD and application manifests |
| `bonus/` | GitLab Helm chart and bootstrap scripts |
| `scripts/` | Shared libvirt preparation and checks for P1/P2 |

**There is no Makefile at the repository root.** Run `make` inside `p1`, `p2` or `p3`. Each provides `make help` to list its commands. The examples below assume the repository is at `~/inception-of-things`; adjust the `cd` paths if your clone is elsewhere.

## Implementation strategy and algorithm choices

The project is built around provisioning order, HTTP routing and Git reconciliation. Vagrant manages the machines, K3s provides Kubernetes, and Argo CD manages the application state declared in Git.

### Machine provisioning and cluster bootstrap

P1 uses two Debian guests to keep the server node and worker node separate. The server runs the Kubernetes control plane and datastore, while the worker runs the K3s agent and executes workloads assigned to it. The K3s server can also execute workloads. P2 uses one server node because its focus is application routing. Both parts use libvirt and the shared `iotnet` definition, so their guest addresses and networking can be inspected directly during evaluation.

The startup targets prepare local prerequisites before provisioning and run verification afterward. P1 preserves an existing cluster key, installs the server, and lets the worker retrieve its join token over SSH. Token retrieval has a bounded retry loop: the worker joins only after it obtains a token, and provisioning fails if the token remains unavailable. P2 waits for its API and node before applying application manifests and waiting for Deployment rollouts. These readiness checks handle services that become available after their installation command returns.

### HTTP routing and replicas

P2 uses declarative Ingress rules: `app1.com` selects app1, `app2.com` selects app2, and a rule without a Host provides the app3 fallback. Services give each application a stable endpoint while Pods can be replaced. App2 declares three replicas, leaving scheduling and traffic distribution across ready endpoints to Kubernetes and its networking components. App1's HTML is mounted from a ConfigMap so its page can be changed without building a custom nginx image.

### Git reconciliation and version updates

P3 moves the cluster into Docker through k3d, keeping the GitOps exercise separate from VM provisioning. The startup script creates a missing cluster or starts an existing one, then installs Argo CD and applies the Application definition. Argo CD compares the selected Git revision with the resources in `dev` and reconciles differences. Automated sync includes `prune` and `selfHeal`, so Git remains the desired state even after manual cluster edits.

The application update changes the Deployment image tag from `v1` to `v2` in Git. Kubernetes handles the rollout; Argo CD reports synchronization and health. From `p3`, `make status` exposes the image and revision, while `make verify` checks sync, health and the container's HTTP responses. Checking the expected version then makes the update traceable from commit to container.

### Local GitLab bootstrap

The bonus reuses the P3 cluster and changes the Application source to a local GitLab repository. A local Helm chart defines GitLab and its persistent storage. The API bootstrap looks up the group and project, creates missing ones, and seeds manifests only when the repository is empty. This preserves later user commits when the bootstrap is run again. P3 and bonus share one Application, so source switching updates that resource instead of creating two Applications managing the same workload.

## Visual features and user experience

The lab uses a few simple visual elements to make its behavior easy to inspect:

| Feature | How it helps |
| --- | --- |
| P2 app1's HTML page | A light-blue background, a large `Hello from app1` heading and readable spacing make the selected application immediately recognizable in a browser. The page is defined in `p2/confs/app1.yaml`. |
| Distinct app2/app3 responses | Each response names its application, making Host routing and the default route easy to compare in a terminal or browser. |
| Argo CD web UI | Sync and health indicators, the Git revision and the resource view show whether a commit reached the cluster and which resources belong to the application. |
| Application version endpoint | `/version.json` identifies the deployed One More Cup release alongside the browser view, so the update demonstration has an explicit version check. |
| Architecture tree and command tables | The architecture tree separates the physical host, outer VM and inner environments. Command tables keep startup, stopping and deletion easy to distinguish. |

The access instructions below include port-forwards and SSH tunnels so these interfaces can be used from the Codam browser even when the services listen only inside Debian.

## Instructions

There is no compilation step for the infrastructure. Prepare the dependencies, then run the target for the part being evaluated. The application is pulled as a container image; its build sources are not part of the current repository tree.

### Where everything runs

The project runs inside a Debian VM on a Codam machine:

```text
Codam computer — Ubuntu 22.04, VirtualBox
└── Debian 13 — the outer VM, where this repository lives
    ├── P1 — two Vagrant VMs using libvirt / QEMU / KVM
    │   ├── osivkovS  — server node, 192.168.56.110
    │   └── osivkovSW — worker node, 192.168.56.111
    ├── P2 — one Vagrant server node, 192.168.56.110
    └── P3 and bonus — a K3d cluster in Docker
```

**Run the commands below inside Debian** unless stated otherwise. The Codam computer is used for the editor, terminal and browser. Package installation and libvirt run inside Debian, where `sudo` is available.

P1 and P2 share the server address `192.168.56.110`, so they must run separately. P3 and bonus share the `iot` cluster and the Argo CD Application `playground`; switching between them changes the source of the application manifests.

### Hardware and resource allocation

The lab runs with nested virtualization for P1/P2 and Docker for P3. The table below shows the resources configured for each part, rather than minimum hardware requirements.

The configured resources are:

| Component | CPU | RAM | Disk / persistent data |
| --- | --- | --- | --- |
| P1 server node `osivkovS` | 2 vCPU | 2048 MiB | Virtual disk from the Vagrant box |
| P1 worker node `osivkovSW` | 1 vCPU | 1024 MiB | A separate disk from the same box |
| P2 server node `osivkovS` | 3 vCPU | 3072 MiB | Virtual disk from the Vagrant box |
| P3 `iot` | No explicit limit | No explicit limit | K3s data in Docker; 1 server, 0 agents |
| Bonus GitLab | request: 1 CPU; limit: 4 CPU | request: 2 GiB; limit: 4 GiB | PVCs: 1 GiB config, 10 GiB data, 2 GiB logs |

P1 and P2 each allocate 3 GiB to their guest VMs. Debian needs additional memory for itself and virtualization. P3 shares Debian's available resources with Docker, k3d, Argo CD and the application. The bonus adds GitLab; its PVC sizes are capacity requests, not actual disk usage.

P1/P2 disk sizes are not set explicitly in the Vagrantfiles; they depend on the box. Check available memory and disk space before downloading images or starting GitLab:

```bash
free -h
df -h /
```

Stop P1 before running P2: both parts use the same private IP for their server.

### Before the first run

P1/P2 require Vagrant, the `vagrant-libvirt` plugin, QEMU/KVM, libvirt, `virsh`, `make` and the OpenSSH client. They also need access to `qemu:///system` and nested virtualization. This repository does not include an installer for these dependencies.

```bash
vagrant --version
vagrant plugin list
virsh -c qemu:///system list --all
```

P3 installs Docker, Python 3, k3d and kubectl with `make install` from `p3`. The bonus also needs Helm, installed with `make install-helm` from the same directory. The first run needs internet access to download packages, the Vagrant box and container images.

> P1/P2 `prepare.sh` changes Intel KVM EPT across the outer Debian VM and persists the setting in `/etc/modprobe.d/iot-kvm.conf`. All active libvirt VMs must be stopped before the KVM module can be reloaded. See the [nested virtualization notes](DEVELOPER.md#nested-virtualization) for details and limitations.

In P1, the Makefile creates a missing local SSH key pair so the worker node can retrieve its K3s join token from the server node. Existing keys are preserved. Vagrant manages SSH access from Debian to both VMs. P2 has only one server node and does not need a separate cluster key pair.

### P1 — server node and worker node

P1 creates two Debian VMs, each representing one Kubernetes node:

| Node | Vagrant name / hostname | Private IP | K3s mode and service | Responsibility |
| --- | --- | --- | --- | --- |
| Server node | `osivkovS` | `192.168.56.110` | `k3s server`, service `k3s` | Runs the control plane and datastore, exposes the API, and can also run workloads |
| Worker node | `osivkovSW` | `192.168.56.111` | `k3s agent`, service `k3s-agent` | Joins the server and runs workloads; it does not host the control plane |

Open a Debian terminal and enter the P1 directory:

```bash
cd ~/inception-of-things/p1
make up
```

This generates missing SSH keys, prepares the network, checks the environment, starts both VMs and runs the verification script. The server uses `192.168.56.110`; the worker uses `192.168.56.111`.

After startup, inspect the lab:

```bash
cd ~/inception-of-things/p1
make status
make nodes
make system-pods
```

Expect both VMs to be `running`, both Kubernetes nodes to be `Ready`, and the system Pods to be healthy. `Completed` is normal for finished installation Jobs. Run `make test` from `p1` to check SSH, guest names and IPs, K3s services and two Ready nodes; inspect all system Pods separately. The worker may have `<none>` in the Kubernetes `ROLES` column because it has no role label; its agent mode is verified through the `k3s-agent` service.

To access a VM, use `vagrant ssh osivkovS` or `vagrant ssh osivkovSW` from `p1`. Check each node's service, then query the cluster through the server node:

```bash
cd ~/inception-of-things/p1
vagrant ssh osivkovS -c 'sudo systemctl is-active k3s'
vagrant ssh osivkovSW -c 'sudo systemctl is-active k3s-agent'
vagrant ssh osivkovS -c 'sudo k3s kubectl get nodes -o wide'
```

> On the worker, plain `kubectl` may connect to `localhost:8080` and return `connection refused`. Without an administrative kubeconfig, that is expected. Check the agent through `k3s-agent` and the server's node list.

Both service checks should return `active`, and the node list should show two Ready nodes with the addresses in the table. From `p1`, stop with `make halt` and start again with `make up`. After editing provisioning scripts, run `vagrant provision`, then `make test` in that directory. A regular `up` may skip provisioners on an existing VM.

### P2 — three applications and Ingress

Stop P1 before starting P2:

```bash
cd ~/inception-of-things/p1
make halt
cd ../p2
make up
```

The VM runs three Deployments and three `ClusterIP` Services. Traefik selects an application using the HTTP `Host` header:

| Request | Response | Replicas |
| --- | --- | --- |
| `Host: app1.com` | HTML containing `Hello from app1` | 1 |
| `Host: app2.com` | `Hello from app2` | 3 |
| Any other Host, or a request to the IP | `Hello from app3` | 1 |

```bash
cd ~/inception-of-things/p2
make replicas
make ingress-details
make http-test
```

Run `make test` from `p2` to check the VM, K3s service and node, application rollouts, three ready app2 replicas and all three HTTP routes. During evaluation, `replicas` and `ingress-details` show the configuration behind those HTTP responses.

You can test the Ingress routes without DNS by setting the `Host` header:

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

Stop with `make halt` from `p2`. After editing manifests, run `vagrant provision osivkovS` there and repeat `make test`.

### P3 — GitHub and Argo CD

If the tools are not installed yet:

```bash
cd ~/inception-of-things/p3
make install
```

If the installer added your user to the Docker group, disconnect from the Debian SSH session and log in again. Then check access and start the cluster:

```bash
cd ~/inception-of-things/p3
docker info
make up
make status
```

This creates or starts `iot`. Argo CD runs in namespace `argocd`, and One More Cup is deployed in `dev`. The application's resources are named `playground`. Argo CD reads branch `main`, path `p3/confs/application`, from the public [GitHub repository](https://github.com/osivkov/inception-of-things).

A successful startup verifies that the Application is `Synced` and `Healthy`, the Deployment is ready, `/healthz` returns `ok` inside the container, and `/version.json` reports `v1` or `v2`. Repeat these checks with `make verify` from `p3`.

#### Open the application and Argo CD

Run these in two separate Debian terminals:

```bash
cd ~/inception-of-things/p3
make app
```

```bash
cd ~/inception-of-things/p3
make ui
```

Both commands keep running until `Ctrl-C`. The application is at `http://localhost:8888`; Argo CD is at `https://localhost:9090`. The Argo CD username is `admin`. Run `make password` from another terminal in `p3` to read the initial password; it may no longer work if the password has been changed. The browser may warn about Argo CD's local self-signed certificate.

**In these commands, `localhost` refers to the Debian VM.** To use a browser on Codam, also start this tunnel on Codam:

```bash
ssh -L 8888:127.0.0.1:8888 -L 9090:127.0.0.1:9090 osivkov@DEBIAN_VM_ADDRESS
```

Then open the same addresses in the Codam browser. Keep both `make app` and `make ui` running in Debian as well as the tunnel.

#### Demonstrate an update from v1 to v2

In `p3/confs/application/deployment.yaml`, change the image from `osivkov/one-more-cup:v1` to `osivkov/one-more-cup:v2`. From the repository root, push the change to GitHub:

```bash
cd ~/inception-of-things
git add p3/confs/application/deployment.yaml
git commit -m "Switch application to v2"
git push origin main
```

Here, `origin` must point to the GitHub repository configured in the Argo CD Application. Check it with `git remote -v`. Pushing only to Vogsphere will not update the application, because Argo CD reads GitHub.

Wait for synchronization, then check the revision, image and HTTP response:

```bash
cd ~/inception-of-things/p3
make verify
make status
curl -fsS http://127.0.0.1:8888/version.json
```

Keep `make app` running for the `curl` request. The response should contain `"version":"v2"`, allowing for JSON whitespace. A local edit without a push will not reach Argo CD. Switch back to `v1` with another commit to demonstrate the reverse update.

The application is pulled from Docker Hub. Its build sources are not in the current repository tree, so startup depends on the published tags `osivkov/one-more-cup:v1` and `v2`.

From `p3`, stop the cluster with `make stop`. The next `make up` selects GitHub as the source again.

### Bonus — local GitLab

The bonus adds GitLab to the same cluster using a local Helm chart. Prepare the installation:

```bash
cd ~/inception-of-things/p3
make install-helm
make bonus-setup
```

Open `http://localhost:8080` in Debian. For a Codam browser, start this tunnel on Codam: `ssh -L 8080:127.0.0.1:8080 osivkov@DEBIAN_VM_ADDRESS`.

For a new installation, the GitLab username is `root`. Read the initial password inside the container in a private terminal:

```bash
kubectl --context=k3d-iot -n gitlab exec deploy/gitlab -- grep 'Password:' /etc/gitlab/initial_root_password
```

The initial password file is temporary. If it is gone, use the current password. See the [GitLab installation guide](https://docs.gitlab.com/install/docker/installation/) for details.

In GitLab, create a personal access token with the `api` scope. Then run:

```bash
cd ~/inception-of-things/p3
make bonus-up
make status
```

The script prompts for the token without displaying it, creates the public group `osivkov` and project `iot` if needed, and seeds manifests only into an empty repository. Keep the token out of project files and command arguments.

The Application source becomes `http://gitlab.gitlab.svc.cluster.local/osivkov/iot.git`. To demonstrate a version update, edit `deployment.yaml` and commit it **in that GitLab project**. The local files in `bonus/confs/application/` are only the initial seed; editing them does not overwrite an existing GitLab repository.

To select GitHub in a running cluster:

```bash
cd ~/inception-of-things/p3
make source-p3
```

To select GitLab instead, after it has been installed and bootstrapped:

```bash
cd ~/inception-of-things/p3
make source-bonus
```

From `p3`, `make stop` stops P3 and the bonus together while preserving data.

### Stopping and preparing for the next evaluation

Run these commands inside the directory named in the column header:

| Action | P1: `p1/` | P2: `p2/` | P3 and bonus: `p3/` |
| --- | --- | --- | --- |
| Inspect status | `make status` | `make status` | `make status` |
| Stop and preserve data | `make halt` | `make halt` | `make stop` |
| Delete the environment | `make destroy` | `make destroy` | `k3d cluster delete iot` |

Delete VMs from the clone that created them. After `destroy` or `delete`, check the actual resources:

```bash
virsh -c qemu:///system list --all
k3d cluster list
docker ps -a
docker volume ls
```

For cleanup and recovery commands, see [DEVELOPER.md](DEVELOPER.md#cleanup-between-evaluations).

Deleting `iot` removes local GitLab data. The PVC retention annotation used for Helm uninstall does not protect against deletion of the cluster itself. Downloaded Vagrant boxes and Docker images can remain cached after deleting the environments.

To start the next part, enter its directory (`p1`, `p2` or `p3`) and run `make up`. P1/P2 prepare `iotnet` automatically.


## Resources

Useful references:

| Topic | Reference |
| --- | --- |
| VM lifecycle and provisioning | [Vagrant](https://developer.hashicorp.com/vagrant/docs), [vagrant-libvirt](https://vagrant-libvirt.github.io/vagrant-libvirt/) |
| Server and agent roles, K3s components | [K3s architecture](https://docs.k3s.io/architecture), [requirements](https://docs.k3s.io/installation/requirements) |
| Running K3s in Docker | [k3d configuration files](https://k3d.io/stable/usage/configfile/) |
| Routing HTTP requests to an application | [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) |
| Automated sync, prune and selfHeal | [Argo CD Automated Sync](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/) |
| First GitLab startup | [GitLab container installation](https://docs.gitlab.com/install/docker/installation/) |
| Saving and restoring GitLab | [Backup](https://docs.gitlab.com/administration/backup_restore/backup_gitlab/), [restore](https://docs.gitlab.com/administration/backup_restore/restore_gitlab/) |

### Use of AI

AI assistance through Codex was used for the following tasks during project preparation:

- Drafting, editing and translating `README.md` and `DEVELOPER.md`, including resource tables, user notes and evaluation instructions.
- Reviewing existing Vagrantfiles, Makefiles, shell scripts, Kubernetes manifests and the GitLab Helm chart against the documentation, and helping interpret SSH, networking and nested virtualization diagnostics.
- Assisting with local Vagrant and Docker cleanup before evaluation, validating Vagrant configuration, and checking documentation links and command examples.
