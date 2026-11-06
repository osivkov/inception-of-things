# Project internals and maintenance

For the startup walkthrough, see the [README](README.md). This guide covers configuration changes, troubleshooting and rebuilding the lab.

## Repository map

```text
p1/
├── Vagrantfile              # K3s server and worker
├── Makefile                 # Startup, verification and cluster inspection
├── confs/                   # iotnet definition and local cluster_key* files
└── scripts/                 # Common guest setup, server, worker and verify
p2/
├── Vagrantfile              # One VM running K3s
├── Makefile
├── confs/                   # Three applications and their Ingress
└── scripts/                 # K3s installation, manifest application and verify
p3/
├── Makefile                 # Installation, startup, GitOps and port-forwarding
├── confs/
│   ├── cluster.yaml         # K3d iot and port 8080 mapping
│   ├── argocd-install.yaml  # Local copy of the Argo CD installation manifests
│   ├── argocd-application.yaml
│   ├── namespaces.yaml
│   └── application/         # Application Deployment, Service and Ingress
└── scripts/                 # Tool installation and cluster startup
bonus/
├── charts/gitlab/           # Local chart for GitLab CE
├── confs/                   # Namespace, Application and seed manifests
└── scripts/                 # Helm installation, startup and GitLab API bootstrap
scripts/
├── prepare.sh               # Shared libvirt preparation for P1/P2
└── check.sh                 # Prepared environment checks
```

There is no root Makefile. Run `make -C p1 ...` from the root, or `make ...` inside `p1`; the same applies to P2/P3. `.vagrant`, `cluster_key*`, `.env` files and tokens are local state and are excluded from Git.

## Resource allocation and versions

VM resources are set in the Vagrantfiles; Kubernetes requests and limits are set in Deployments. These are separate layers: increasing a container limit does not add RAM to the outer VM.

| Configuration file | Current allocation |
| --- | --- |
| `p1/Vagrantfile` | Default: 1 vCPU / 1024 MiB; server override: 2 vCPU / 2048 MiB |
| `p2/Vagrantfile` | 3 vCPU / 3072 MiB for the server |
| `p3/confs/cluster.yaml` | 1 server, 0 agents; no explicit CPU or RAM limits |
| `bonus/charts/gitlab/templates/deployment.yaml` | requests: 1 CPU / 2 GiB; limits: 4 CPU / 4 GiB; `/dev/shm`: memory-backed emptyDir up to 256 MiB |
| `bonus/charts/gitlab/templates/storage.yaml` | PVCs: config 1 GiB, data 10 GiB, logs 2 GiB; StorageClass `local-path` |

The P2 applications and One More Cup have no explicit requests or limits in their Deployments. Disk planning must also account for images, container writes and Argo CD components. The 13 GiB requested by GitLab PVCs does not cover all disk usage.

The versions below come from the repository files. To change one, edit the source listed here, then check compatibility and release availability.

| Component | Value in the project | Source |
| --- | --- | --- |
| P1/P2 Debian box | `debian/trixie64`, no `box_version` set | Both Vagrantfiles |
| P1 K3s | Not pinned | `p1/scripts/server.sh`, `worker.sh` |
| P2 K3s | `v1.36.5+k3s1` | `p2/scripts/server.sh` |
| P3/bonus K3s | `rancher/k3s:v1.36.5-k3s1` | `p3/confs/cluster.yaml` |
| k3d | `v5.9.0` | `p3/scripts/install.sh` |
| P3 kubectl | `v1.36.5` | `p3/scripts/install.sh` |
| Argo CD | `v3.3.16` in the local installation manifest's images | `p3/confs/argocd-install.yaml` |
| Helm | `v4.3.1` | `bonus/scripts/install-helm.sh` |
| GitLab CE | `19.5.1-ce.0` | `bonus/charts/gitlab/values.yaml` |
| P2 app1 | `nginx:1.28-alpine` | `p2/confs/app1.yaml` |
| P2 app2/app3 | `hashicorp/http-echo:1.0.0` | `p2/confs/app2.yaml`, `app3.yaml` |
| One More Cup | `osivkov/one-more-cup:v1`, with `v2` for the update demonstration | P3 Deployment and bonus seed Deployment |

Docker is installed through Debian's `docker.io` package. Its version is not pinned in the script. The k3d, kubectl and Helm installers check downloads against published checksums.

A new P1 installation may receive a different K3s release from P2/P3. This is a reproducibility limitation of the current scripts. Changing the K3s image in `cluster.yaml` does not upgrade an existing cluster: `up.sh` starts it again when it already exists. P2 also skips K3s installation when the binary is already present.

## Networks and addresses

### P1/P2

Vagrant uses system libvirt at `qemu:///system`. Each VM has a Vagrant management network and a separate project network:

| Purpose | Configuration |
| --- | --- |
| Vagrant management | In this lab: `vagrant-libvirt`, subnet `192.168.121.0/24`; used by Vagrant for management and SSH |
| Project network | `iotnet`, NAT, bridge `virbr56`, gateway `192.168.56.1/24` |
| P1 or P2 server | `192.168.56.110` |
| P1 worker | `192.168.56.111` |
| K3s API used by the worker | `https://192.168.56.110:6443` |
| P2 Ingress | `http://192.168.56.110:80` |

The `iotnet` definition is in `p1/confs/iotnet.xml` and `p2/confs/iotnet.xml`. Preparation defines the network if missing, enables autostart and starts it if inactive. Editing the XML does not automatically redefine an existing network. Inspect its actual configuration with:

```bash
virsh -c qemu:///system net-list --all
virsh -c qemu:///system net-dumpxml iotnet
ip -br address
```

Expected domain names are `p1_osivkovS`, `p1_osivkovSW` and `p2_osivkovS`. If the project directory or provider settings have changed, check the actual names with `virsh list --all`.

P2 passes `--flannel-iface eth1` to K3s. When moving to another box, run `ip -br address` inside the VM and check the interface name. The selected interface must have `192.168.56.110`.

### P3/bonus

K3d creates cluster `iot`; kubectl uses context `k3d-iot`. Port 8080 is bound to Debian's loopback interface, so access from Codam uses a tunnel.

| Address in Debian | Destination |
| --- | --- |
| `127.0.0.1:8080`, Host `cup.localhost` | P3 application Ingress |
| `127.0.0.1:8080`, Host `localhost` | GitLab Ingress after bonus installation |
| `127.0.0.1:8888` with `make -C p3 app` | Application Service through port-forwarding |
| `127.0.0.1:9090` with `make -C p3 ui` | Argo CD Service, HTTPS through port-forwarding |

The two Ingress resources can share a port because their Hosts differ. To test without a browser:

```bash
curl -H 'Host: cup.localhost' http://127.0.0.1:8080/version.json
curl -H 'Host: localhost' http://127.0.0.1:8080/
```

The second request requires GitLab to be running. Application access on 8888 does not use Ingress: the port-forward goes directly to the Service.

## Provisioning flow

### P1

`make up` calls `keys`, then `prepare`, `check`, `vagrant up --provider=libvirt` and `test`. The current Makefile does not pass `--no-parallel`.

On both VMs, `common.sh` installs tools and SSH keys, adds hostnames to `/etc/hosts` and disables swap. `server.sh` installs K3s in server mode. `worker.sh` fetches `/var/lib/rancher/k3s/server/node-token` from the server over SSH and installs the agent with the API address and token. Token retrieval uses a bounded number of attempts; failure ends provisioning with an error.

K3s inside the guests uses its own container runtime. P1/P2 do not require Docker on each node; Docker in the outer Debian VM is used by K3d for P3.

Vagrant keeps its own SSH state in `.vagrant`. The `confs/cluster_key*` pair is a separate mechanism for guest-to-guest access. The `keys` target preserves an existing private key and derives its `.pub` file. P2 has no token exchange between VMs and does not copy this pair.

The lab takes a few shortcuts: host key checking is disabled for `192.168.56.*`, and the server kubeconfig is created with mode `644`. Review these settings before using the setup on a shared or public server. An administrative kubeconfig is not configured automatically on the worker.

### P2

Vagrant copies `confs/` into `/home/vagrant/confs` on the guest. `server.sh` installs K3s if missing, starts the service, waits for the API and a Ready node, applies the applications and Ingress, then waits for all three Deployment rollouts.

App1 gets its HTML from ConfigMap `app1-page` and serves it with nginx on port 80. App2 and app3 listen on 5678; their Services accept port 80 and forward to 5678. The Ingress rule without a `host` routes to app3. All these resources are in namespace `default`.

After editing the copied files, run `vagrant provision osivkovS` from `p2`. Editing local YAML alone does not change resources inside an existing VM.

### P3 and bonus

`p3/scripts/up.sh` creates `iot` if missing or starts it if present, switches the current kubectl context, waits for the node, and applies namespaces and the local Argo CD installation manifest. It then waits for the Deployments and Application controller.

A normal run applies the GitHub Application. The bonus calls the same script with `SKIP_APPLICATION=true`, installs GitLab with Helm and uses the GitLab API. `--setup-only` stops after GitLab becomes ready so the user can create a token. If an Application source was already configured, this mode preserves it.

Startup scripts and `make verify` cover different checks. Running through `make -C p3 up` or `bonus-up` includes the final application verification. Calling `bonus/scripts/up.sh` directly checks Application sync and health, but does not run all HTTP checks from the Makefile.

## GitOps and repositories

| Mode | Source URL | Branch | Path |
| --- | --- | --- | --- |
| P3 | `https://github.com/osivkov/inception-of-things.git` | `main` | `p3/confs/application` |
| Bonus | `http://gitlab.gitlab.svc.cluster.local/osivkov/iot.git` | `main` | `.` |

Both definitions describe **one** Application, `argocd/playground`, deploying to `dev`. Applying the other definition changes its source. Automated sync includes `prune` and `selfHeal`, so Argo CD reconciles resources with Git. A manual Deployment edit through kubectl does not replace a commit. See the [Argo CD sync policy](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/) for details.

In the working repository, `origin` is used for GitHub and `vogsphere` for submission. A new Vogsphere clone may have a different `origin`. The Argo CD URL does not change automatically: check `git remote -v` and `spec.source.repoURL` before demonstrating an update.

The bonus bootstrap creates a public group and project, then adds `deployment.yaml` and `service.yaml` in the first commit only when the repository is empty. It does not update an existing branch from the local seed files. `GITLAB_GROUP` and `GITLAB_PROJECT` change the bootstrap project's address, but the URL in `bonus/confs/argocd-application.yaml` remains explicitly configured.

GitLab serves Git over HTTP in this setup. No separate GitLab SSH Service is exposed, and the P1 lab key pair is not needed for GitLab.

## Before submission

A fresh clone gets only committed files. The part Makefiles and `verify.sh` scripts must be tracked even if they already work on the local lab. Check tracked files and remaining changes with:

```bash
git status --short
git diff --check
git ls-files p1/Makefile p1/scripts/verify.sh p2/Makefile p2/scripts/verify.sh
git remote -v
```

Push the submission commit to `vogsphere` and P3 GitOps changes to GitHub. These have different purposes. Local SSH keys will not appear in a clone: `cluster_key*` is deliberately ignored and generated locally when needed.

## What the checks cover

| Command | Checks | Inspect separately |
| --- | --- | --- |
| `make -C p1 check` | Vagrantfile, libvirt access, Intel EPT, active/autostart iotnet and conflict with P2 | Kubernetes state after startup |
| `make -C p1 test` | SSH to both guests, hostname/IP, K3s services, server kubectl and two Ready nodes | All system Pods and events |
| `make -C p2 test` | Guest, K3s, one Ready node, application rollouts, 3 ready app2 replicas and HTTP for three Hosts | Ingress and Service details: the script lists them but does not compare the full YAML |
| `make -C p3 verify` | Application Synced/Healthy, rollout, `/healthz` and v1/v2 inside the container | Browser access, Service/Ingress and the intended Git revision |

P3 `verify` accepts both v1 and v2. To prove an update specifically to v2, check the current image, Git revision and `/version.json`. A successful request inside a Pod does not prove the user's tunnel is open.

Provisioning errors are not all handled the same way: the final diagnostic server `kubectl get nodes` in P1 allows failure, while `make test` runs after `vagrant up`. Use the test result and actual cluster state to judge whether the lab is ready.

## Nested virtualization

This lab runs VirtualBox → Debian → KVM → guest VMs. Previous VBox.log output showed `VERR_VMX_INVALID_GUEST_STATE` followed by `GURU_MEDITATION`. This confirms a VMX error, but does not establish its trigger. RAM exhaustion has not been proven as the cause.

The current `scripts/prepare.sh` disables Intel EPT with `kvm_intel ept=0` and writes the setting to `/etc/modprobe.d/iot-kvm.conf`. If it is not set yet, the script requires all active libvirt VMs to stop before reloading the module. This affects the outer Debian VM as a whole. The scripts target the Intel lab described here.

This workaround has not been confirmed to prevent Guru Meditation. Sequential startup can be tried as a separate diagnostic step after the usual P1 `keys`, `prepare` and `check`:

```bash
vagrant up --provider=libvirt --no-parallel
make test
```

Run these from `p1`. This experiment is not a proven fix for the underlying virtualization error. To check hardware acceleration on a running domain:

```bash
virsh -c qemu:///system qemu-monitor-command p1_osivkovS --hmp 'info kvm'
```

Use `sudo` for this diagnostic command if elevated access is required. `kvm support: enabled` confirms that KVM is in use, but does not guarantee stable nested virtualization.

Keep the memory layers separate when reading system metrics. Debian's `available` value describes guest headroom; freed guest memory may not return immediately to the physical host. Do not add VirtualBox thread rows in htop as if they were independent processes. Check both Debian and the physical host before changing the RAM allocation.

## Troubleshooting

Start with the component that reported the error. The commands below are for an existing environment; there is no need to create new infrastructure just to read these notes.

| Symptom | What to check |
| --- | --- |
| `make check` fails before VM startup | `virsh -c qemu:///system list --all`, `net-list --all`, EPT access and `vagrant validate` in the relevant part |
| Worker missing from `get nodes` | `k3s-agent`, worker-to-server SSH access, server and agent logs |
| Pod is `Pending` or in `CrashLoopBackOff` | `describe pod` and events in the relevant namespace, then container logs |
| P2 shows app3 when accessed by IP | This is the default route; app1/app2 require their Host header |
| P2 does not respond at all | `eth1`, Traefik, Service endpoints, routes and HTTP from Debian before testing the tunnel |
| Docker returns `permission denied` | Current user access; start a new login session after installation or group changes |
| Argo CD does not update the image | Active repoURL, branch, Git revision and whether the change was pushed there |
| Browser reports connection refused | Debian port-forward, Codam SSH tunnel and an available local port |
| GitLab is not ready | Pods, PVCs, events in `gitlab`, available RAM and disk space |

P1 already provides diagnostic targets:

```bash
make -C p1 cluster-check
make -C p1 logs-server
make -C p1 logs-worker
```

For P2, use `make -C p2 all-checks` and `make -C p2 logs`. For P3:

```bash
kubectl --context=k3d-iot -n argocd get application playground -o yaml
kubectl --context=k3d-iot -n dev get pods -o wide
kubectl --context=k3d-iot -n dev get events --sort-by=.metadata.creationTimestamp
```

The warning `[fog][WARNING] Unrecognized arguments: libvirt_ip_command` alone does not establish the cause of a failure. After a shutdown `Fog::Errors::TimeoutError`, inspect `virsh list --all` to find out which VMs are still running. If the outer VirtualBox VM itself crashed, read its VBox.log on the physical computer.

## Cleanup between evaluations

Stopping and deleting serve different purposes. `halt` and `k3d cluster stop iot` preserve the environment. To rebuild P1/P2, run `make -C p1 destroy` and `make -C p2 destroy` from the clone that owns the VMs. For P3, remove the existing `iot` with `k3d cluster delete iot`.

After deletion, inspect libvirt and Docker as well as local Vagrant status:

```bash
virsh -c qemu:///system list --all
virsh -c qemu:///system pool-list --all
virsh -c qemu:///system vol-list --pool default
k3d cluster list
docker ps -a
docker volume ls
docker network ls
```

`default` is this lab's storage pool name. In another environment, use the name from `pool-list`. Vagrant box images remain as a cache for future VMs. Individual machine disks are normally named `p1_osivkovS.img`, `p1_osivkovSW.img` and `p2_osivkovS.img`.

If a domain remains from an old clone, establish its origin and inspect its disk first:

```bash
virsh -c qemu:///system dumpxml p2_osivkovS
virsh -c qemu:///system domblklist p2_osivkovS --details
```

Vagrant-libvirt normally records `Source: .../p2/Vagrantfile` in the XML. Check ownership before deleting a similarly named volume. Keep `.vagrant` until its VMs have been removed so Vagrant retains their identity. Shared networks `iotnet` and `vagrant-libvirt` can remain; `prepare.sh` prepares the project network on the next startup.

Docker images can also remain to speed up the next run. If clearing the cache, inspect `docker image ls` and delete specific tags with `docker image rm`. A general `docker system prune --volumes` is unnecessary here. Existing P1 keys are preserved independently of VM deletion.

## GitLab data

The chart stores configuration, data and logs in three `local-path` PVCs. A normal K3d stop preserves them. The PVC templates include `helm.sh/resource-policy: keep`, so uninstalling the Helm release does not necessarily remove the PVCs. Deleting the cluster itself removes the data inside its nodes. See the [Helm documentation](https://helm.sh/docs/howto/charts_tips_and_tricks/) for the annotation's behavior.

To prepare a backup:

```bash
kubectl --context=k3d-iot -n gitlab exec deploy/gitlab -- gitlab-backup create
kubectl --context=k3d-iot -n gitlab exec deploy/gitlab -- ls -lh /var/opt/gitlab/backups
```

Copy the required archive outside the cluster. Also save `/etc/gitlab/gitlab-secrets.json` and the configuration from the config PVC; the application archive alone is insufficient. Restore using the corresponding GitLab version. Follow the official [backup](https://docs.gitlab.com/administration/backup_restore/backup_gitlab/) and [restore](https://docs.gitlab.com/administration/backup_restore/restore_gitlab/) procedures. This project does not include a restore script.
