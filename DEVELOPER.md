# Project internals and maintenance

The [README](README.md) covers startup and evaluation. This file describes the architecture, provisioning flow, configuration and maintenance commands.

Developed by **osivkov** and **iriadyns** as part of the 42 curriculum. Commands assume the repository is at `~/iot` inside the outer Debian VM.

[Repository map](#repository-map) · [Versions](#resource-allocation-and-versions) · [Networks](#networks-and-addresses) · [Provisioning](#provisioning-flow) · [Inspection](#inspection-commands) · [Logs](#logs-and-status)

## Repository map

```text
p1/
├── Vagrantfile              # K3s server and worker (VirtualBox)
├── Makefile                 # Startup, evaluation checks and cluster inspection
├── confs/                   # .gitkeep, node-token is written here at runtime (git-ignored)
└── scripts/                 # server.sh and agent.sh
p2/
├── Vagrantfile              # One VM running K3s (VirtualBox)
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
```

Git ignores `.vagrant/` and `p1/confs/node-token`. The `confs/` folder of P1 is kept in Git through a `.gitkeep` file: the server script writes the join token there, and the folder must exist inside the shared directory.

### Makefiles

Each part has a `Makefile` to group the commands needed for that environment. The Makefiles are a convenient interface to the provisioning scripts and cluster tools, not an additional infrastructure component.

| Part | Main tasks |
| --- | --- |
| P1 | Start both VMs, run the evaluation checks (`eval`, `check-*`), inspect nodes, SSH into either VM, recreate or delete the VMs, free VT-x from KVM (`kvm-off`) |
| P2 | Start the VM and run `verify.sh`, deploy three applications, test replicas and Ingress routes, inspect Kubernetes objects, free VT-x from KVM (`kvm-off`) |
| P3 | Install tools, manage the k3d cluster, access Argo CD and switch GitOps sources |

For example, `make -C p1 eval` prints every P1 evaluation check, and `make -C p2 all-checks` prints the P2 overview. See each Makefile for the full list of targets (`make help` in P2 and P3, a bare `make` in P1).

P1 evaluation targets:

| Target | What it shows |
| --- | --- |
| `check-vms` | `vagrant status` and, from `VBoxManage showvminfo`, each VM's name, memory and CPU count |
| `check-host` | Hostname, OS, `nproc` and `free -m` inside each guest |
| `check-net` | The `192.168.56.110/111` addresses and ping between the guests |
| `check-ssh` | Passwordless SSH with `BatchMode=yes` |
| `check-k3s` | `k3s` active on the server, `k3s-agent` active on the worker, and their `ExecStart` lines |
| `nodes` | `kubectl get nodes -o wide` and `kubectl get pods -A` from the server |
| `eval` | All of the above in order |

## Installing VirtualBox and Vagrant

Debian 13 (trixie) no longer ships VirtualBox in its own repositories, so install it from Oracle's APT repository. This is a one-time setup inside the outer Debian VM:

```bash
sudo apt update
sudo apt install -y curl gpg build-essential dkms linux-headers-$(uname -r)

curl -fsSL https://www.virtualbox.org/download/oracle_vbox_2016.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/oracle-virtualbox-2016.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian trixie contrib" \
  | sudo tee /etc/apt/sources.list.d/virtualbox.list

sudo apt update
sudo apt install -y virtualbox-7.2
sudo usermod -aG vboxusers "$USER"     # log out and in afterwards
```

Install Vagrant from HashiCorp's repository (see the [Vagrant installation guide](https://developer.hashicorp.com/vagrant/install)) rather than from Debian: Debian trixie packages Vagrant 2.3.7, which is older than the 2.4.x series used here and predates VirtualBox 7.2. Check which one is installed and where it comes from:

```bash
vagrant --version
apt policy vagrant
VBoxManage --version
lsmod | grep vboxdrv
```

## Resource allocation and versions

The Vagrantfiles set VM resources. Kubernetes requests and limits control container resources inside those VMs. Changing a Pod limit does not increase the VM's RAM.

| Configuration file | Current allocation |
| --- | --- |
| `p1/Vagrantfile` | Both machines: 1 vCPU / 1024 MiB (set per machine in the `MACHINES` list) |
| `p2/Vagrantfile` | 2 vCPU / 2024 MiB for the server |
| `p3/confs/cluster.yaml` | 1 server, 0 agents, no explicit CPU or RAM limits |
| `bonus/charts/gitlab/templates/deployment.yaml` | requests: 1 CPU / 2 GiB, limits: 4 CPU / 4 GiB, `/dev/shm`: memory-backed emptyDir up to 256 MiB |
| `bonus/charts/gitlab/templates/storage.yaml` | PVCs: config 1 GiB, data 10 GiB, logs 2 GiB, StorageClass `local-path` |

The GitLab PVC capacities do not include image storage or other cluster data. VM disk sizes come from the Vagrant box because neither Vagrantfile sets a disk size.

The versions below are configured in the project files or were used in our runs. Check compatibility before changing them.

| Component | Value in the project | Source |
| --- | --- | --- |
| VirtualBox (outer Debian VM) | 7.2.22 from Oracle's repository | Installed on the host, not in the repository |
| Vagrant (outer Debian VM) | 2.4.9 | Installed on the host, not in the repository |
| P1/P2 Debian box | `bento/debian-13`, provider `virtualbox`, no `box_version` set | Both Vagrantfiles |
| P1 K3s | Not pinned, resolved from the installer's stable channel | `p1/scripts/server.sh`, `agent.sh` |
| P2 K3s | `v1.37.2+k3s1` | `p2/scripts/server.sh` |
| P3/bonus K3s | `rancher/k3s:v1.36.5-k3s1` | `p3/confs/cluster.yaml` |
| k3d | `v5.9.0` | `p3/scripts/install.sh` |
| P3 kubectl | `v1.36.5` | `p3/scripts/install.sh` |
| Argo CD | `v3.3.16` in the local installation manifest's images | `p3/confs/argocd-install.yaml` |
| Helm | `v4.3.1` | `bonus/scripts/install-helm.sh` |
| GitLab CE | `19.5.5-ce.0` | `bonus/charts/gitlab/values.yaml` |
| P2 app1 | `nginx:1.28-alpine` | `p2/confs/app1.yaml` |
| P2 app2/app3 | `nginx:1.28-alpine` | `p2/confs/app2.yaml`, `app3.yaml` |
| One More Cup (P3) | `osivkov/one-more-cup:v1`, baseline for the update to `v2` | `p3/confs/application/deployment.yaml` |
| One More Cup (bonus seed) | `osivkov/one-more-cup:v1`, used only to initialize an empty GitLab repository | `bonus/confs/application/deployment.yaml` |

P3 uses Docker from Debian packages. K3s in P1/P2 uses its own container runtime. P2 and P3 configure different K3s minor versions (v1.37 and v1.36). These are independent environments. Validate their dependencies separately when upgrading.

P2 pins its K3s version, while P1 uses the version supplied by the K3s installer. P2 installs K3s only when the `k3s` executable is absent. Editing its pinned version does not upgrade an existing installation. Updating `cluster.yaml` alone does not upgrade an existing k3d cluster.

The bonus chart uses GitLab CE `19.5.5-ce.0`. The image tag is set in `bonus/charts/gitlab/values.yaml`, and `Chart.yaml` records the same release in `appVersion`. `make -C p3 bonus-setup` applies the chart with Helm and preserves the selected Application source.

## Networks and addresses

### P1/P2

Each VirtualBox guest has two adapters, created by Vagrant:

| Adapter | Type | Purpose |
| --- | --- | --- |
| Adapter 1 | NAT (`10.0.2.15` inside the guest) | Internet access and Vagrant's SSH, through a forwarded port on `127.0.0.1` of Debian (`2222` for the first VM, Vagrant picks another port, such as `2200`, if it is taken) |
| Adapter 2 | Host-only (`private_network`) | The project network, `192.168.56.0/24` |

| Purpose | Configuration |
| --- | --- |
| Project network | VirtualBox host-only network, created by Vagrant. Debian sees it as an interface such as `vboxnet0` with `192.168.56.1/24` |
| P1 or P2 server | `192.168.56.110` |
| P1 worker | `192.168.56.111` |
| K3s API used by the worker | `https://192.168.56.110:6443` |
| P2 Ingress | `http://192.168.56.110:80` |

VirtualBox 7 only allows host-only addresses inside the ranges listed in `/etc/vbox/networks.conf`. `192.168.56.0/21` is allowed by default, so no change is required. Inspect the actual configuration with:

```bash
VBoxManage list hostonlyifs
VBoxManage list runningvms
ip -br address
vagrant ssh-config
```

Inside the guests the project interface name varies by box (`eth1` in the Vagrant boxes we used, while other distributions may call it `enp0s8`). Both K3s installation scripts therefore detect it by its address instead of hardcoding it:

```bash
IFACE=$(ip -o -4 addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2}')
```

The result is passed to K3s as `--flannel-iface`. If K3s ever uses `10.0.2.15` as the node address, the worker cannot join. Check `kubectl get nodes -o wide` for `INTERNAL-IP`.

### P3/bonus

K3d creates cluster `iot`. Kubectl uses context `k3d-iot`. Port 8080 is bound to Debian's loopback interface, so access from Codam uses a tunnel.

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

The first request requires the P3 application Ingress to be present. Switching to the bonus source can prune that Ingress because the bonus seed contains only a Deployment and Service. The second request requires GitLab to be running. Application access on 8888 uses port-forwarding directly to the Service and works with either source.

## Provisioning flow

### P1

`make up` runs `vagrant up` for the server first and then the worker, so the server can publish the join token before the worker needs it. The Vagrantfile defines both machines from one `MACHINES` list (name, IP, provisioning script, memory) and applies common settings: the `bento/debian-13` box, a 600-second boot timeout, a VirtualBox shared folder (`.` → `/vagrant`), a host-only `private_network`, 1 vCPU and the memory from the list.

Two VirtualBox options are set on every guest. `--uartmode1 disconnected` avoids the serial-port logging that can stall boot of some Debian boxes at "SSH auth method: private key", and `--natdnshostresolver1 on` makes DNS inside the guest follow the host resolver.

`server.sh` finds the project interface by IP and installs K3s in server mode with `--node-ip`, `--advertise-address`, `--flannel-iface` and `--write-kubeconfig-mode=644`. When `/var/lib/rancher/k3s/server/node-token` exists, it copies the token to `/vagrant/confs/node-token`. The tracked `.gitkeep` keeps the destination directory in a clean checkout.

`agent.sh` reads the shared token once the file is non-empty and installs K3s in agent mode with `K3S_URL=https://192.168.56.110:6443`, `K3S_TOKEN`, `--node-ip` and `--flannel-iface`. Run cluster queries through the server kubeconfig.

K3s inside the guests uses its own container runtime. P1/P2 do not require Docker on each node. Docker in the outer Debian VM is used by K3d for P3.

The join token is stored in the shared folder and ignored by Git. The server kubeconfig uses mode `644`, allowing the Vagrant user to run kubectl on the server.

### P2

The shared folder is disabled. Vagrant copies `confs/` into `/home/vagrant/confs` on the guest with a `file` provisioner. `server.sh` installs K3s (`v1.37.2+k3s1`) if missing, starts the service, waits for the API and a Ready node, applies the applications and Ingress, then waits for all three Deployment rollouts.

Traefik is installed by K3s through its Helm controller after the API starts, so it comes up a little later than the application Pods. Until then port 80 refuses connections. `scripts/verify.sh` therefore retries failed HTTP requests with curl. It uses up to 10 retries, a 2-second retry delay and a 10-second timeout for each attempt. A successful HTTP response containing unexpected content fails the check immediately.

All three applications use `nginx:1.28-alpine` and listen on port 80. Each manifest defines a page ConfigMap, a Deployment and a ClusterIP Service with `port: 80` and `targetPort: 80`. All resources are in namespace `default`.

| Application | Page configuration | Replicas | Ingress Host |
| --- | --- | --- | --- |
| app1 | `app1-page`, mounted into the nginx document root | 1 | `app1.com` |
| app2 | `app2-page`, rendered by `envsubst` at container startup | 3 | `app2.com` |
| app3 | `app3-page`, rendered by `envsubst` at container startup | 1 | Any other Host or access by IP |

App2 and app3 obtain `POD_NAME` and `NODE_NAME` through the Downward API. Their startup command substitutes those values into the HTML template before starting nginx. Updating a ConfigMap does not rerun this command in existing containers. Recreate the affected Pods with a Deployment rollout restart when changing their page templates.

The Ingress rule without a `host` selects app3 as the default. Its backend and the other two backends reference their matching Service on port 80.

After editing the copied files, run `vagrant provision osivkovS` from `p2`. Editing local YAML alone does not change resources inside an existing VM. If only the app2 or app3 page template changed, restart the affected Deployment after provisioning. For example, for app2:

```bash
cd ~/iot/p2
vagrant provision osivkovS
vagrant ssh osivkovS -c 'sudo k3s kubectl rollout restart deployment/app2'
vagrant ssh osivkovS -c 'sudo k3s kubectl rollout status deployment/app2 --timeout=180s'
make test
make replicas
```

### P1 and P2 together

Both parts name their VM `osivkovS` in VirtualBox and use `192.168.56.110`. VirtualBox refuses to import a second VM with an existing name, even if the first one is powered off, so destroy one part before starting the other:

```bash
make -C p1 clean     # before starting p2
make -C p2 destroy   # before starting p1
```

### P3 and bonus

`p3/scripts/up.sh` creates `iot` if missing or starts it if present, switches the current kubectl context, waits for the node, and applies namespaces and the local Argo CD installation manifest. It then waits for the Deployments and Application controller.

A normal run applies the GitHub Application. The bonus calls the same script with `SKIP_APPLICATION=true`, installs GitLab with Helm and uses the GitLab API. `--setup-only` stops after GitLab becomes ready so the user can create a token. If an Application source was already configured, this mode preserves it.

The `verify` target checks the deployed application after startup.

## GitOps and repositories

| Mode | Source URL | Branch | Path |
| --- | --- | --- | --- |
| P3 | `https://github.com/osivkov/inception-of-things.git` | `main` | `p3/confs/application` |
| Bonus | `http://gitlab.gitlab.svc.cluster.local/osivkov/iot.git` | `main` | `.` |

Both definitions describe **one** Application, `argocd/playground`, deploying to `dev`. Applying the other definition changes its source. Automated sync includes `prune` and `selfHeal`, so Argo CD reconciles resources with Git. For a lasting change, commit the manifest to the repository Argo CD is watching rather than patching the Deployment manually. See the [Argo CD sync policy](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/) for details.

Argo CD reads the repository configured in `spec.source.repoURL`. Commit and push application changes to that repository and its watched branch. The README uses an explicit GitHub push URL so GitOps updates can coexist with a separate Vogsphere remote.

The bonus bootstrap creates a public group and project, then adds `deployment.yaml` and `service.yaml` in the first commit only when the repository is empty. It does not update an existing branch from the local seed files. `GITLAB_GROUP` and `GITLAB_PROJECT` change the bootstrap project's address, but the URL in `bonus/confs/argocd-application.yaml` remains explicitly configured.

GitLab serves Git over HTTP in this setup. No separate GitLab SSH Service is exposed.

## Inspection commands

| Command | Purpose |
| --- | --- |
| `make -C p1 eval` | Display VM resources, hostnames, network addresses, SSH access, services, nodes and Pods |
| `make -C p2 test` | Run the P2 verification script and HTTP route checks |
| `make -C p2 replicas` | Display app2 Deployment replica counts and its Pods |
| `make -C p2 ingress-details` | Display Ingress rules and backends |
| `make -C p3 verify` | Inspect Application sync and health, wait for the rollout and query the application endpoints |
| `make -C p3 status` | Display the active source, Git revision, image and workloads |

For an application update, compare the deployed Git revision and image tag with the commit that was pushed. Query `/version.json` to see the running release. Use `make app` and `make ui` from `p3/` for application and Argo CD access.

## Nested virtualization

P1 and P2 run VirtualBox guests inside a Debian VM that is itself a VirtualBox guest on the Codam machine. This needs hardware virtualization exposed to the outer VM and working VirtualBox kernel modules inside it.

The main trap is KVM. If the `kvm` kernel modules are loaded in the outer Debian VM (they are pulled in when libvirt/QEMU is used or installed), they own VT-x and VirtualBox cannot start a guest:

```text
VBoxManage: error: VT-x is being used by another hypervisor (VERR_VMX_IN_VMX_ROOT_MODE)
```

Free VT-x with the Makefile helper (available in `p1` and `p2`) and verify:

```bash
make kvm-off
lsmod | grep kvm        # must print nothing
lsmod | grep vboxdrv    # must print the module
```

`kvm-off` stops `libvirtd`, then unloads `kvm_intel` / `kvm_amd` and `kvm`. To keep KVM from returning after a reboot, blacklist it:

```bash
printf 'blacklist kvm\nblacklist kvm_intel\nblacklist kvm_amd\n' | sudo tee /etc/modprobe.d/blacklist-kvm.conf
sudo systemctl disable --now libvirtd libvirtd.socket 2>/dev/null
sudo update-initramfs -u
```

Other checks for the outer VM:

```bash
grep -Ec '(vmx|svm)' /proc/cpuinfo      # hardware virtualization visible, must be > 0
sudo /sbin/vboxconfig                    # rebuild the kernel modules if vboxdrv is missing
mokutil --sb-state                       # Secure Boot blocks unsigned vboxdrv modules
```

If `vboxdrv` is missing after a kernel update, install matching `linux-headers-$(uname -r)` and run `sudo /sbin/vboxconfig`.

Nested guests start slowly. The Vagrantfiles set a 600-second boot timeout for that reason. Avoid powering off the outer VM while the inner VMs are running: shut them down first (`make down` / `make halt`). An abrupt power-off can leave the K3s server in an unready state on the next start.

## Logs and status

Run these commands to inspect the environment and its service logs.

P1 nodes and service logs:

```bash
cd ~/iot/p1
make eval
vagrant ssh osivkovS -c 'sudo journalctl -u k3s -b --no-pager | tail -50'
vagrant ssh osivkovSW -c 'sudo journalctl -u k3s-agent -b --no-pager | tail -50'
```

For P2, use `make -C p2 all-checks` and `make -C p2 logs`. For P3:

```bash
kubectl --context=k3d-iot -n argocd get application playground -o yaml
kubectl --context=k3d-iot -n dev get pods -o wide
kubectl --context=k3d-iot -n dev get events --sort-by=.metadata.creationTimestamp
```

## Cleanup between evaluations

Stopping keeps the environment. Deleting removes it. `make down` (P1), `make halt` (P2) and `k3d cluster stop iot` preserve the environment. To rebuild P1/P2, run `make -C p1 clean` and `make -C p2 destroy` from the clone that owns the VMs. For P3, remove the existing `iot` with `k3d cluster delete iot`.

Check for remaining resources before starting again:

```bash
VBoxManage list vms
vagrant global-status --prune
k3d cluster list
docker ps -a
```

If a VM was removed by hand and Vagrant still lists it, `vagrant global-status --prune` clears the stale entry. A leftover VirtualBox VM can be removed with `VBoxManage unregistervm <name> --delete`.

Deleting the k3d cluster also deletes GitLab data stored inside it. Use the backup procedure below if that data needs to be kept.

## GitLab data

GitLab uses three `local-path` PVCs for configuration, data and logs. Stopping k3d keeps them. The PVC templates include `helm.sh/resource-policy: keep`, so uninstalling the Helm release does not necessarily remove the PVCs. Deleting the cluster itself removes the data inside its nodes. See the [Helm documentation](https://helm.sh/docs/howto/charts_tips_and_tricks/) for the annotation's behavior.

To prepare a backup:

```bash
kubectl --context=k3d-iot -n gitlab exec deploy/gitlab -- gitlab-backup create
kubectl --context=k3d-iot -n gitlab exec deploy/gitlab -- ls -lh /var/opt/gitlab/backups
```

Copy the required archive outside the cluster. Also save `/etc/gitlab/gitlab-secrets.json` and the configuration from the config PVC. The application archive alone is insufficient. Restore using the corresponding GitLab version. Follow the official [backup](https://docs.gitlab.com/administration/backup_restore/backup_gitlab/) and [restore](https://docs.gitlab.com/administration/backup_restore/restore_gitlab/) procedures. This project does not include a restore script.
