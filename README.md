*This project has been created as part of the 42 curriculum by osivkov, iriadyns.*

# Inception-of-Things

Kubernetes fundamentals through virtual machines, HTTP routing and GitOps.

[Description](#description) · [Instructions](#instructions) · [Resources](#resources) · [Developer guide](DEVELOPER.md)

## Description

Inception-of-Things is a system administration project from the 42 curriculum. It introduces Kubernetes through three environments and an optional bonus. The goal is to provision nodes, route requests through an Ingress and deploy application updates automatically from Git.

| Part | Environment | Main objective |
| --- | --- | --- |
| P1 | Two Debian 13 VMs managed by Vagrant and VirtualBox | Connect a K3s server and an agent |
| P2 | One Debian 13 VM running K3s | Route requests to three applications with Traefik |
| P3 | A k3d cluster running in Docker | Deploy One More Cup from GitHub with Argo CD |
| Bonus | GitLab in the P3 cluster | Deploy application updates from a local GitLab repository |

The project is developed by **osivkov** and **iriadyns**. Infrastructure files are stored in `p1/`, `p2/`, `p3/` and `bonus/`. Each mandatory part has its own Makefile. The bonus uses `p3/Makefile`.

### Architecture

```text
Host computer
└── Debian 13 VM, repository at ~/iot
    ├── P1, Vagrant and VirtualBox
    │   ├── osivkovS, K3s server, 192.168.56.110
    │   └── osivkovSW, K3s agent, 192.168.56.111
    ├── P2, Vagrant and VirtualBox
    │   └── osivkovS, K3s server, 192.168.56.110
    └── P3 and bonus, Docker and k3d
        └── iot cluster
            ├── argocd namespace
            ├── dev namespace, One More Cup
            └── gitlab namespace, bonus only
```

P1 and P2 use the same server name and address. Destroy the existing environment before creating the other one. A halted VM still owns its VirtualBox name.

P3 and the bonus share cluster `iot` and Argo CD Application `playground`. Selecting another source updates that same Application.

## Instructions

Run the commands inside the outer Debian VM. Examples assume the repository is at `~/iot`. Adjust this path for another clone. Run `make help` inside `p1`, `p2` or `p3` to list available commands.

There is no compilation step for the infrastructure. P2 uses published nginx images. P3 and the bonus pull One More Cup from Docker Hub. Its application build sources are not included in this repository.

### Prerequisites

| Environment | Required tools |
| --- | --- |
| P1 and P2 | VirtualBox 7.2, compatible Vagrant 2.4.x, make, curl and OpenSSH |
| P3 | Docker, Python 3, k3d and kubectl, installed with `make -C p3 install` |
| Bonus | P3 tools and Helm, installed with `make -C p3 install-helm` |

P1 and P2 need nested hardware virtualization exposed to Debian and the `vboxdrv` kernel module. If KVM holds VT-x or AMD-V, VirtualBox cannot start the guests. See [dependency installation](DEVELOPER.md#installing-virtualbox-and-vagrant) and [nested virtualization](DEVELOPER.md#nested-virtualization).

The first run needs internet access to download packages, Vagrant boxes and container images.

| Component | CPU | Memory | Persistent storage |
| --- | --- | --- | --- |
| Each P1 VM | 1 vCPU | 1024 MiB | Disk supplied by the Vagrant box |
| P2 VM | 2 vCPU | 2024 MiB | Disk supplied by the Vagrant box |
| P3 cluster | No explicit limit | No explicit limit | Data inside Docker |
| GitLab container | Request 1 CPU, limit 4 CPU | Request 2 GiB, limit 4 GiB | Config 1 GiB, data 10 GiB, logs 2 GiB |

These values describe the configuration. The outer Debian VM also needs resources for its own OS, Docker and the cluster services. Inspect available capacity before starting:

```bash
free -h
df -h /
```

### P1, K3s server and agent

If P2 exists, delete its VM from the clone that created it:

```bash
cd ~/iot/p2
make destroy
```

Start P1 and inspect the nodes:

```bash
cd ~/iot/p1
make up
make status
make eval
```

Expected state:

| VM | Address | Service | Expected Kubernetes state |
| --- | --- | --- | --- |
| `osivkovS` | `192.168.56.110` | `k3s` | Ready, control plane |
| `osivkovSW` | `192.168.56.111` | `k3s-agent` | Ready, agent |

Vagrant manages SSH keys. Connect with `make ssh-s` or `make ssh-sw` without a password. The worker can show `<none>` in the Kubernetes `ROLES` column. Its agent mode is visible through the `k3s-agent` service.

The server copies its join token to `p1/confs/node-token`, which is ignored by Git and shared with the worker. The worker reads this token and connects to the server at `https://192.168.56.110:6443`.

`make eval` prints diagnostics. Confirm that both nodes are present and Ready. An explicit readiness check is:

```bash
vagrant ssh osivkovS -c 'kubectl wait --for=condition=Ready nodes --all --timeout=180s'
vagrant ssh osivkovS -c 'kubectl get nodes -o wide'
```

The worker has no administrative kubeconfig. Run cluster queries on the server.

### P2, three applications and Ingress

Destroy P1 before starting P2:

```bash
cd ~/iot/p1
make clean
cd ../p2
make up
```

All three applications use `nginx:1.28-alpine` on port 80. Each has a ConfigMap, a Deployment and a ClusterIP Service forwarding port 80 to port 80 in the Pods. App2 and app3 render their Pod and node names into the page when the container starts.

| Request | Response contains | Replicas |
| --- | --- | --- |
| Host `app1.com` | `Hello from app1` | 1 |
| Host `app2.com` | `Hello from app2` | 3 |
| Any other Host, including access by IP | `Hello from app3` | 1 |

Inspect the configuration and test the routes from Debian:

```bash
cd ~/iot/p2
make replicas
make ingress-details
make test
curl -fsS -H 'Host: app1.com' http://192.168.56.110/
curl -fsS -H 'Host: app2.com' http://192.168.56.110/
curl -fsS -H 'Host: unknown.example' http://192.168.56.110/
curl -fsS http://192.168.56.110/
```

`make replicas` shows the Deployment and its Pods. App2 is configured with three replicas. Use `make ingress-details` to inspect the Host rules and `make test` to run the P2 checks.

Vagrant copies manifests into the VM during provisioning. After editing `p2/confs/`, apply the updated files and repeat the checks:

```bash
cd ~/iot/p2
vagrant provision osivkovS
make test
make replicas
```

If only the HTML template in the app2 or app3 ConfigMap changed, restart the affected Deployment after provisioning. Its page is rendered at container startup. See [P2 provisioning](DEVELOPER.md#p2).

Traefik can take longer to start than the application Pods. The HTTP checks retry connection failures.

For a browser on the host computer, open a tunnel there:

```bash
ssh -L 18080:192.168.56.110:80 osivkov@DEBIAN_VM_ADDRESS
```

Opening `http://127.0.0.1:18080/` shows app3. To select app1 or app2 without DNS, use curl with the corresponding Host header.

### P3, GitHub and Argo CD

Install dependencies once:

```bash
cd ~/iot/p3
make install
```

If the installer adds your user to the Docker group, log out and back in. Then start P3:

```bash
cd ~/iot/p3
docker info
make up
make status
```

Argo CD runs in `argocd` and deploys One More Cup into `dev`. It watches branch `main`, path `p3/confs/application`, in the public [osivkov/inception-of-things repository](https://github.com/osivkov/inception-of-things).

`make verify` checks Synced and Healthy status, the Deployment rollout, `/healthz` and `/version.json` inside the container. It accepts both `v1` and `v2`. Check the expected image and Git revision separately when demonstrating an update.

#### Access the application and Argo CD

Run `make app` and `make ui` in separate terminals inside `p3/`. Keep them running while using the services.

| Service | Address inside Debian | Login |
| --- | --- | --- |
| One More Cup | `http://localhost:8888` | Not required |
| Argo CD | `https://localhost:9090` | `admin`, initial password from `make password` |

The initial password may no longer work after it has been changed. Argo CD uses a local self-signed certificate.

For a host browser, also keep this tunnel running on the host computer:

```bash
ssh -L 8888:127.0.0.1:8888 -L 9090:127.0.0.1:9090 osivkov@DEBIAN_VM_ADDRESS
```

#### Demonstrate v1 to v2

Select the GitHub source with `make source-p3` inside `p3/`. The Deployment uses `osivkov/one-more-cup:v1` as the baseline for the update demonstration.

Publish the v1 baseline to the GitHub source watched by Argo CD if it has not been pushed yet:

```bash
cd ~/iot
git remote -v
git add p3/confs/application/deployment.yaml
git commit -m "Set application to v1"
git push https://github.com/osivkov/inception-of-things.git main
```

Use an authenticated GitHub transport for which you have push access and ensure the commit is on `main`. Argo CD watches the GitHub URL configured in its Application. The explicit push URL above can be used alongside a separate Vogsphere remote.

Wait for synchronization. Run `make -C p3 status` and `make -C p3 verify`. With `make app` running, check:

```bash
curl -fsS http://127.0.0.1:8888/version.json
```

Confirm the deployed Git revision matches the baseline commit, the image ends in `:v1` and the response reports `v1`.

Change the image to `osivkov/one-more-cup:v2`, commit it and push to the same GitHub branch. Repeat the checks and confirm the new commit, image tag and response all match `v2`.

### Bonus, local GitLab

The bonus installs GitLab in namespace `gitlab` using the local Helm chart. Prepare it from `p3/`:

```bash
cd ~/iot/p3
make install-helm
make bonus-setup
```

GitLab is available at `http://localhost:8080` inside Debian. For a host browser, open `ssh -L 8080:127.0.0.1:8080 osivkov@DEBIAN_VM_ADDRESS` on the host.

For a new installation, log in as `root`. Read the initial password in a private terminal:

```bash
kubectl --context=k3d-iot -n gitlab exec deploy/gitlab -- grep 'Password:' /etc/gitlab/initial_root_password
```

If that temporary file has been removed, use the current password. Create a personal access token with the `api` scope, then run:

```bash
cd ~/iot/p3
make bonus-up
make status
```

The script prompts for the token, creates the public group `osivkov` and project `iot` if missing, and adds the seed manifests only if the repository is empty. Existing commits are preserved.

Argo CD then reads `http://gitlab.gitlab.svc.cluster.local/osivkov/iot.git`, branch `main`. Demonstrate v1 to v2 by editing and committing `deployment.yaml` in that GitLab project. Files in `bonus/confs/application/` only initialize an empty repository.

Use `make source-p3` to select GitHub or `make source-bonus` to select an existing GitLab setup. Run both commands inside `p3/`.

The chart uses `gitlab/gitlab-ce:19.5.5-ce.0`. To apply the chart to an existing installation, run `make bonus-setup` from `p3/`. This starts the cluster and runs Helm upgrade while preserving the configured Application source.

### Stop, rebuild and delete

| Action | P1, inside `p1/` | P2, inside `p2/` | P3 and bonus, inside `p3/` |
| --- | --- | --- | --- |
| Inspect | `make status` | `make status` | `make status` |
| Stop and preserve data | `make down` | `make halt` | `make stop` |
| Recreate | `make re` | `make re` | Delete `iot`, then `make up` |
| Delete | `make clean` | `make destroy` or `make clean` | `k3d cluster delete iot` |

Delete Vagrant VMs from the clone that created them. Deleting the k3d cluster also removes local GitLab data inside its nodes. Back up required data first. See [cleanup](DEVELOPER.md#cleanup-between-evaluations) and [GitLab data](DEVELOPER.md#gitlab-data).

## Resources

| Topic | Reference |
| --- | --- |
| Virtual machines and provisioning | [Vagrant documentation](https://developer.hashicorp.com/vagrant/docs), [VirtualBox provider](https://developer.hashicorp.com/vagrant/docs/providers/virtualbox) |
| VirtualBox installation and networking | [Linux downloads](https://www.virtualbox.org/wiki/Linux_Downloads), [VirtualBox manual](https://www.virtualbox.org/manual/) |
| K3s server, agent and runtime | [K3s architecture](https://docs.k3s.io/architecture), [requirements](https://docs.k3s.io/installation/requirements) |
| Kubernetes in Docker | [k3d configuration](https://k3d.io/stable/usage/configfile/) |
| HTTP routing | [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) |
| GitOps | [Argo CD automated sync](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/) |
| Local GitLab | [Container installation](https://docs.gitlab.com/install/docker/installation/), [releases](https://docs.gitlab.com/releases/) |
| GitLab persistence | [Backup](https://docs.gitlab.com/administration/backup_restore/backup_gitlab/), [restore](https://docs.gitlab.com/administration/backup_restore/restore_gitlab/) |
