# Project internals and maintenance

The [README](README.md) covers startup and evaluation. This file explains the configuration, how the parts fit together, and what to check when something fails.

This project has been created as part
of the 42 curriculum by
The project was developed by **osivkov** and **iriadyns**. See the [README](README.md#contributors) for the contributor list.

## Repository map

```text
p1/
├── Vagrantfile              # K3s server and worker (VirtualBox)
├── Makefile                 # Startup, evaluation checks and cluster inspection
├── confs/                   # .gitkeep; node-token is written here at runtime (git-ignored)
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

For example, `make -C p1 eval` prints every P1 evaluation check, and `make -C p2 all-checks` prints the P2 overview. See each Makefile for the full list of targets (`make help` in P2 and P3; a bare `make` in P1).

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

The Vagrantfiles set VM resources. Kubernetes requests and limits control container resources inside those VMs; changing a Pod limit does not increase the VM's RAM.

| Configuration file | Current allocation |
| --- | --- |
| `p1/Vagrantfile` | Both machines: 1 vCPU / 1024 MiB (set per machine in the `MACHINES` list) |
| `p2/Vagrantfile` | 1 vCPU / 1024 MiB for the server |
| `p3/confs/cluster.yaml` | 1 server, 0 agents; no explicit CPU or RAM limits |
| `bonus/charts/gitlab/templates/deployment.yaml` | requests: 1 CPU / 2 GiB; limits: 4 CPU / 4 GiB; `/dev/shm`: memory-backed emptyDir up to 256 MiB |
| `bonus/charts/gitlab/templates/storage.yaml` | PVCs: config 1 GiB, data 10 GiB, logs 2 GiB; StorageClass `local-path` |

The GitLab PVC capacities do not include image storage or other cluster data.

The versions below are configured in the project files or were used in our runs. Check compatibility before changing them.

| Component | Value in the project | Source |
| --- | --- | --- |
| VirtualBox (outer Debian VM) | 7.2.22 from Oracle's repository | Installed on the host, not in the repository |
| Vagrant (outer Debian VM) | 2.4.9 | Installed on the host, not in the repository |
| P1/P2 Debian box | `bento/debian-13` (v202510.26.0 in our runs), provider `virtualbox`, no `box_version` set | Both Vagrantfiles |
| P1 K3s | Not pinned: the installer's stable channel (v1.37.2+k3s1 in our runs) | `p1/scripts/server.sh`, `agent.sh` |
| P2 K3s | `v1.37.2+k3s1` | `p2/scripts/server.sh` |
| P3/bonus K3s | `rancher/k3s:v1.36.5-k3s1` | `p3/confs/cluster.yaml` |
| k3d | `v5.9.0` | `p3/scripts/install.sh` |
| P3 kubectl | `v1.36.5` | `p3/scripts/install.sh` |
| Argo CD | `v3.3.16` in the local installation manifest's images | `p3/confs/argocd-install.yaml` |
| Helm | `v4.3.1` | `bonus/scripts/install-helm.sh` |
| GitLab CE | `19.5.1-ce.0` | `bonus/charts/gitlab/values.yaml` |
| P2 app1 | `nginx:1.28-alpine` | `p2/confs/app1.yaml` |
| P2 app2/app3 | `hashicorp/http-echo:1.0.0` | `p2/confs/app2.yaml`, `app3.yaml` |
| One More Cup | `osivkov/one-more-cup:v1`, with `v2` for the update demonstration | P3 Deployment and bonus seed Deployment |

P3 uses Docker from Debian packages; K3s in P1/P2 uses its own container runtime. P2 and P3 run slightly different K3s minor versions (v1.37 and v1.36); they are independent environments, so this does not affect behavior, but keep it in mind when upgrading.

P2 pins its K3s version, while P1 uses the version supplied by the K3s installer. Updating `cluster.yaml` alone does not upgrade an existing k3d cluster.

## Networks and addresses

### P1/P2

Each VirtualBox guest has two adapters, created by Vagrant:

| Adapter | Type | Purpose |
| --- | --- | --- |
| Adapter 1 | NAT (`10.0.2.15` inside the guest) | Internet access and Vagrant's SSH, through a forwarded port on `127.0.0.1` of Debian (`2222` for the first VM; Vagrant picks another port, such as `2200`, if it is taken) |
| Adapter 2 | Host-only (`private_network`) | The project network, `192.168.56.0/24` |

| Purpose | Configuration |
| --- | --- |
| Project network | VirtualBox host-only network, created by Vagrant; Debian sees it as an interface such as `vboxnet0` with `192.168.56.1/24` |
| P1 or P2 server | `192.168.56.110` |
| P1 worker | `192.168.56.111` |
| K3s API used by the worker | `https://192.168.56.110:6443` |
| P2 Ingress | `http://192.168.56.110:80` |

VirtualBox 7 only allows host-only addresses inside the ranges listed in `/etc/vbox/networks.conf`; `192.168.56.0/21` is allowed by default, so no change is required. Inspect the actual configuration with:

```bash
VBoxManage list hostonlyifs
VBoxManage list runningvms
ip -br address
vagrant ssh-config
```

Inside the guests the project interface name varies by box (`eth1` in the Vagrant boxes we used, but modern distributions may call it `enp0s8`). Both K3s installation scripts therefore detect it by its address instead of hardcoding it:

```bash
IFACE=$(ip -o -4 addr show | awk -v ip="$NODE_IP" '$4 ~ "^"ip"/" {print $2}')
```

The result is passed to K3s as `--flannel-iface`. If K3s ever uses `10.0.2.15` as the node address, the worker cannot join; check `kubectl get nodes -o wide` for `INTERNAL-IP`.

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

`make up` runs `vagrant up` for the server first and then the worker, so the server can publish the join token before the worker needs it. The Vagrantfile defines both machines from one `MACHINES` list (name, IP, provisioning script, memory) and applies common settings: the `bento/debian-13` box, a 600-second boot timeout, a VirtualBox shared folder (`.` → `/vagrant`), a host-only `private_network`, 1 vCPU and the memory from the list.

Two VirtualBox options are set on every guest. `--uartmode1 disconnected` avoids the serial-port logging that can stall boot of some Debian boxes at "SSH auth method: private key", and `--natdnshostresolver1 on` makes DNS inside the guest follow the host resolver.

`server.sh` finds the project interface by IP, installs K3s in server mode with `--node-ip`, `--advertise-address`, `--flannel-iface` and `--write-kubeconfig-mode=644`, waits until the node is `Ready`, creates `/vagrant/confs` if needed, removes any old token and copies `/var/lib/rancher/k3s/server/node-token` to `/vagrant/confs/node-token`.

`agent.sh` waits for that file, reads the token and installs K3s in agent mode with `K3S_URL=https://192.168.56.110:6443`, `K3S_TOKEN`, `--node-ip` and `--flannel-iface`. If no token appears within the bounded wait, provisioning fails instead of hanging. K3s installs `kubectl` on the server; the worker has no administrative kubeconfig.

K3s inside the guests uses its own container runtime. P1/P2 do not require Docker on each node; Docker in the outer Debian VM is used by K3d for P3.

This is a local lab, not a production setup. The join token lives in a plain file on the host and the server kubeconfig is readable by all local users (`644`). Do not copy these settings to a shared machine. The worker does not get an admin kubeconfig.

### P2

The shared folder is disabled. Vagrant copies `confs/` into `/home/vagrant/confs` on the guest with a `file` provisioner. `server.sh` installs K3s (`v1.37.2+k3s1`) if missing, starts the service, waits for the API and a Ready node, applies the applications and Ingress, then waits for all three Deployment rollouts.

Traefik is installed by K3s through its Helm controller after the API starts, so it comes up a little later than the application Pods. Until then port 80 refuses connections. `scripts/verify.sh` therefore retries each HTTP request for several minutes; if you script your own checks, do the same.

App1 gets its HTML from ConfigMap `app1-page` and serves it with nginx on port 80. App2 and app3 listen on 5678; their Services accept port 80 and forward to 5678. The Ingress rule without a `host` routes to app3. All these resources are in namespace `default`.

After editing the copied files, run `vagrant provision osivkovS` from `p2`. Editing local YAML alone does not change resources inside an existing VM.

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

Argo CD reads the repository configured in `spec.source.repoURL`. Changes need to be committed and pushed there before the cluster can synchronize them.

The bonus bootstrap creates a public group and project, then adds `deployment.yaml` and `service.yaml` in the first commit only when the repository is empty. It does not update an existing branch from the local seed files. `GITLAB_GROUP` and `GITLAB_PROJECT` change the bootstrap project's address, but the URL in `bonus/confs/argocd-application.yaml` remains explicitly configured.

GitLab serves Git over HTTP in this setup. No separate GitLab SSH Service is exposed.

## What the checks cover

| Command | Checks | Inspect separately |
| --- | --- | --- |
| `make -C p1 eval` | VM names, CPUs and memory, guest OS, the two IPs and ping, passwordless SSH, `k3s` / `k3s-agent` services, `kubectl get nodes -o wide`, all Pods | Events and logs when a Pod is unhealthy |
| `make -C p2 test` | Guest, K3s service, one Ready node, application rollouts, 3 ready app2 replicas and HTTP for three Hosts | Ingress and Service details: the script lists them but does not compare the full YAML |
| `make -C p3 verify` | Application Synced/Healthy, rollout, `/healthz` and v1/v2 inside the container | Browser access, Service/Ingress and the intended Git revision |

P3 `verify` accepts both v1 and v2. To prove an update specifically to v2, check the current image, Git revision and `/version.json`. A successful request inside a Pod does not prove the user's tunnel is open.

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

## Troubleshooting

Check the failing component first. These commands work on an existing environment.

| Symptom | What to check |
| --- | --- |
| `VERR_VMX_IN_VMX_ROOT_MODE` on `vagrant up` | KVM holds VT-x. Run `make kvm-off`, confirm `lsmod \| grep kvm` is empty, then retry |
| `Kernel driver not installed` / no `vboxdrv` | `sudo /sbin/vboxconfig`, matching `linux-headers`, Secure Boot state |
| `unsupported VirtualBox version` from Vagrant | Vagrant is too old for the installed VirtualBox; use the HashiCorp build (2.4.x) |
| `vagrant up` stops at "SSH auth method: private key" | The guest is still booting: wait, rerun `make up` (the boot timeout is 600 s). Take a screenshot to see the console: `VBoxManage controlvm <name> screenshotpng /tmp/vm.png` |
| `cp: cannot create regular file '/vagrant/confs/node-token'` | `p1/confs/` is missing; recreate it with `mkdir -p p1/confs && touch p1/confs/.gitkeep` and run `vagrant provision osivkovS` |
| Worker missing from `get nodes`, `k3s-agent` repeats `503` / "server is not ready" | The server's API is not ready. Check `systemctl is-active k3s` and `kubectl get nodes` on `osivkovS`, then `journalctl -u k3s -b` there |
| Worker joins but node IPs are `10.0.2.15` | `--flannel-iface` / `--node-ip` did not match the host-only interface; check `ip -br -4 a` in the guest |
| `kubectl` on the worker prints `localhost:8080 refused` | Expected: the worker has no kubeconfig. Run `kubectl` on the server |
| `A VirtualBox machine with the name osivkovS already exists` | P1 or P2 is still defined; `make clean` / `make destroy` in the other part, then `VBoxManage list vms` |
| P2 shows app3 when accessed by IP | This is the default route; app1/app2 require their Host header |
| P2 `curl` is refused right after boot | Traefik is still starting; `make -C p2 system-pods`, then repeat `make -C p2 test` |
| P2 does not respond at all | The project interface, Traefik, Service endpoints and routes; test HTTP from Debian before testing the tunnel |
| Pod is `Pending` or in `CrashLoopBackOff` | `describe pod` and events in the relevant namespace, then container logs |
| Docker returns `permission denied` | Current user access; start a new login session after installation or group changes |
| Argo CD does not update the image | Active repoURL, branch, Git revision and whether the change was pushed there |
| Browser reports connection refused | Debian port-forward, Codam SSH tunnel and an available local port |
| GitLab is not ready | Pods, PVCs, events in `gitlab`, available RAM and disk space |

Useful diagnostics for P1:

```bash
make -C p1 eval
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

Stopping keeps the environment; deleting removes it. `make down` (P1), `make halt` (P2) and `k3d cluster stop iot` preserve the environment. To rebuild P1/P2, run `make -C p1 clean` and `make -C p2 destroy` from the clone that owns the VMs. For P3, remove the existing `iot` with `k3d cluster delete iot`.

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

Copy the required archive outside the cluster. Also save `/etc/gitlab/gitlab-secrets.json` and the configuration from the config PVC; the application archive alone is insufficient. Restore using the corresponding GitLab version. Follow the official [backup](https://docs.gitlab.com/administration/backup_restore/backup_gitlab/) and [restore](https://docs.gitlab.com/administration/backup_restore/restore_gitlab/) procedures. This project does not include a restore script.
