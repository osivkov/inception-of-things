# Implementation notes

The [README](README.md) has the commands for running P1, P2, and P3. This file explains how their pieces connect and where to look when something goes wrong.

## P1: two-node K3s cluster

P1 creates two Debian 13 guests through Vagrant and `vagrant-libvirt` inside the outer Debian VM. Both guests use the private `iotnet` network. `osivkovS` (`192.168.56.110`) runs the K3s server; `osivkovSW` (`192.168.56.111`) runs a K3s agent that joins the server. The server has 2 vCPUs and 2048 MiB of RAM; the worker uses the default 1 vCPU and 1024 MiB.

```text
Outer Debian VM → Vagrant + libvirt
                   ├─ osivkovS  : 192.168.56.110 → K3s server + Kubernetes API
                   └─ osivkovSW : 192.168.56.111 → K3s agent
                              worker ──SSH join-token request──→ server
                              worker ──K3s join on 6443───────→ server
```

Each guest also has a Vagrant management interface for `vagrant ssh`. The private interface uses `iotnet`, defined by `p1/confs/iotnet.xml` with `192.168.56.0/24`, bridge `virbr56`, and gateway `192.168.56.1`. P1 and P2 cannot run together because both define a server at `192.168.56.110`.

### P1 file map and provisioning

| File | Purpose |
| --- | --- |
| `p1/Vagrantfile` | Defines both guests, resources, hostnames, private IPs, uploads, and provisioning order |
| `p1/confs/iotnet.xml` | Defines the private libvirt network prepared by `scripts/prepare.sh` |
| `p1/confs/cluster_key` and `.pub` | Local SSH key pair copied to both guests for the worker's passwordless token request |
| `p1/scripts/common.sh` | Installs guest prerequisites, adds private names to `/etc/hosts`, disables swap, and installs the SSH key for `vagrant` |
| `p1/scripts/server.sh` | Installs K3s in server mode on `192.168.56.110` |
| `p1/scripts/worker.sh` | Reads the server join token over SSH and installs K3s in agent mode on `192.168.56.111` |
| `scripts/prepare.sh` | Applies the outer VM's EPT workaround and prepares `iotnet` for P1 or P2 |
| `scripts/check.sh` | Checks Vagrant, libvirt, EPT, network state, and the other part's server IP conflict |

Vagrant uploads the key pair to each guest, then runs `common.sh` before the role-specific script. The common script installs `curl`, CA certificates, and an SSH client; updates `/etc/hosts`; turns swap off; and puts the key in `/home/vagrant/.ssh`. The worker script connects to the server as `vagrant`, reads `/var/lib/rancher/k3s/server/node-token`, and passes that token to the K3s agent installer. The ignored local file `p1/confs/node-token` is not read by these scripts. Unlike P2, P1's K3s install script does not pin a K3s version.

### Prepare and start P1

Run the commands inside the outer Debian VM. You need Vagrant with `vagrant-libvirt`, QEMU/KVM, libvirt, `sudo`, nested virtualization, internet access, and the P1 key pair. The private key and its `.pub` file are ignored by Git, so generate them locally when absent:

```bash
cd ~/inception-of-things
if [ ! -f p1/confs/cluster_key ]; then
  ssh-keygen -t ed25519 -N '' -f p1/confs/cluster_key
fi
if [ ! -f p1/confs/cluster_key.pub ]; then
  ssh-keygen -y -f p1/confs/cluster_key > p1/confs/cluster_key.pub
fi
make up PART=p1
```

The commands keep an existing private key and generate only missing files. Stop P2 first if it is active. `make up PART=p1` runs preparation and checks before `vagrant up --provider=libvirt`; preparation may change the outer VM's KVM module configuration and libvirt network. For separate diagnosis, run `make prepare PART=p1`, `make check PART=p1`, and `make status PART=p1` from the repository root.

The server install script makes a short `kubectl get nodes` attempt and ignores failure of that command. Vagrant provisioning can therefore finish before the complete two-node cluster is ready. Verify readiness explicitly.

### Verify and stop P1

From `p1` in the outer VM:

```bash
vagrant status
vagrant ssh osivkovS -c 'hostname; ip -4 addr show'
vagrant ssh osivkovSW -c 'hostname; ip -4 addr show'
vagrant ssh osivkovS -c 'sudo systemctl is-active k3s'
vagrant ssh osivkovSW -c 'sudo systemctl is-active k3s-agent'
vagrant ssh osivkovS -c 'sudo k3s kubectl get nodes -o wide'
vagrant ssh osivkovSW -c 'ssh -o BatchMode=yes vagrant@192.168.56.110 hostname'
```

Expect two running VMs, the specified hostnames and private addresses, active K3s services, and two `Ready` Kubernetes nodes. `vagrant ssh` should connect to each guest without a VM password. The final command tests the passwordless worker-to-server SSH path used to obtain the join token. To stop both VMs, run `vagrant halt` from `p1` or `make halt PART=p1` from the repository root.

If the worker does not join, inspect `vagrant ssh osivkovSW -c 'sudo systemctl status k3s-agent --no-pager'`, the worker's provisioning output, the server's K3s service, and the worker-to-server SSH command above. If the private network is unavailable, run `make check PART=p1` from the repository root and inspect its EPT and `iotnet` messages.

## P2: one node, three apps

Vagrant creates `osivkovS` on QEMU/KVM with the private address `192.168.56.110`; a separate management interface handles SSH and provisioning. `p2/scripts/server.sh` installs K3s `v1.36.5+k3s1`. K3s supplies the Kubernetes API, kubectl, Flannel networking, and Traefik.

Each application has a Deployment and an internal `ClusterIP` Service. App1 uses `nginx:1.28-alpine` and serves an HTML page from a ConfigMap mounted into the Nginx document root. App2 and app3 use `hashicorp/http-echo:1.0.0` on container port `5678`; their Services listen on port `80` and forward traffic to `5678`. App2 has three replicas. App1 and app3 have one each.

```text
HTTP client -> 192.168.56.110:80 -> Traefik -> Ingress apps
                                         | app1.com -> Service app1 -> Nginx Pod
                                         | app2.com -> Service app2 -> 3 http-echo Pods
                                         | other Host -> Service app3 -> http-echo Pod
```

The Ingress uses `ingressClassName: traefik`. It has two Host-specific rules and one rule without a Host for the default application.

### Kubernetes objects in plain language

- A **ConfigMap** stores app1's `index.html` without building a custom image.
- A **Deployment** declares an application's container and desired number of replicas. Kubernetes creates and replaces the Pods.
- A **Service** provides a stable name and port for the Pods selected by its labels.
- An **Ingress** describes which Service receives an external HTTP request. Traefik implements these rules.

All application resources defined by the P2 manifests use the Kubernetes `default` namespace because the manifests do not specify another namespace. The `argocd` and `dev` namespaces belong to P3, not P2.

## P2 file map

| File | Purpose |
| --- | --- |
| `p2/Vagrantfile` | Debian box, VM resources and IP, manifest upload, and provisioning |
| `p2/scripts/server.sh` | Install K3s, wait for the node, apply YAML, and wait for Deployments |
| `p2/confs/app1.yaml` | HTML ConfigMap, Nginx Deployment, and app1 Service |
| `p2/confs/app2.yaml` | App2 Deployment with `replicas: 3` and Service |
| `p2/confs/app3.yaml` | App3 Deployment and Service |
| `p2/confs/ingress.yaml` | Host-based routes and the route without a Host |
| `p2/confs/iotnet.xml` | Definition of the private libvirt network |
| `scripts/prepare.sh` | Configure EPT and the libvirt network in the outer VM |
| `scripts/check.sh` | Check Vagrant, libvirt, EPT, the network, and IP conflicts |

## Prepare and start P2

Run commands from the repository root **inside the outer Debian VM**. You need Vagrant, `vagrant-libvirt`, QEMU/KVM, libvirt, `sudo`, nested virtualization, and internet access. For this setup, preparation disables Intel EPT through `/etc/modprobe.d/iot-kvm.conf` and creates `iotnet`. If other libvirt VMs are running, preparation stops before reloading the KVM module.

```bash
make up PART=p2
```

`make up` runs preparation and checks automatically. To diagnose these stages separately, use `make prepare PART=p2` and `make check PART=p2`. P1 and P2 cannot run at the same time because their servers use the same IP. To manage the VM from the repository root:

```bash
make status PART=p2
make halt PART=p2
```

To connect from the `p2` directory:

```bash
cd p2
vagrant ssh osivkovS
```

On the first `vagrant up`, Vagrant copies `p2/confs` to `/home/vagrant/confs` in the guest and runs `server.sh`. The script installs K3s, waits for the node to become `Ready`, applies app1, app2, app3, and Ingress YAML, then waits for each Deployment rollout. A normal `vagrant up` on an existing VM may not rerun provisioning.

### What `make up PART=p2` does

1. `scripts/prepare.sh` checks the host tools, applies the local EPT workaround when needed, and creates or starts the `iotnet` network.
2. `scripts/check.sh` validates Vagrant and libvirt access and checks that the P1 server is not using `192.168.56.110`.
3. Vagrant starts `osivkovS`, uploads `p2/confs`, and executes `p2/scripts/server.sh`.
4. The server script installs K3s if needed, waits for the node, applies the manifests, and waits for all three Deployments.

This order helps locate a failure: a failure before the VM starts is usually in preparation or Vagrant; a failure after K3s starts is usually visible through `kubectl`.

## Change a P2 application

Edit the YAML files in `p2/confs`. To copy them into an existing VM again and apply the changes, run this from `p2`:

```bash
vagrant provision osivkovS
```

If you only change app1's ConfigMap, the mounted file may take some time to update. If needed, restart the Deployment:

```bash
vagrant ssh osivkovS -c 'sudo k3s kubectl rollout restart deployment/app1'
vagrant ssh osivkovS -c 'sudo k3s kubectl rollout status deployment/app1 --timeout=120s'
```

Adding a fourth application requires more than another YAML file: `server.sh` explicitly lists application names in its apply and rollout loops. The new application also needs a route in `ingress.yaml`.

## Verify P2

Run these commands from `p2`:

```bash
vagrant ssh osivkovS -c 'sudo k3s kubectl get nodes -o wide'
vagrant ssh osivkovS -c 'sudo k3s kubectl get deployments,services,ingress'
vagrant ssh osivkovS -c 'sudo k3s kubectl get pods -o wide'
vagrant ssh osivkovS -c 'sudo k3s kubectl describe ingress apps'

curl -fsS --max-time 10 -H 'Host: app1.com' http://192.168.56.110/
curl -fsS --max-time 10 -H 'Host: app2.com' http://192.168.56.110/
curl -fsS --max-time 10 -H 'Host: unknown.example' http://192.168.56.110/
```

Look for one app1 Pod, three app2 Pods, and one app3 Pod in `Running` state. The app2 Deployment should show `3/3` ready replicas. The HTTP responses should contain `Hello from app1` (HTML), `Hello from app2`, and `Hello from app3`, respectively. `describe ingress apps` shows the routing rules.

If something fails, check `vagrant status`, then `sudo systemctl status k3s`, `sudo k3s kubectl get pods -A`, and `sudo k3s kubectl describe pod <name>` inside the VM. If disk space is low, inspect large directories in the outer VM with `du -xhd2 ~/ | sort -hr`.

### Common checks

| Symptom | First thing to inspect |
| --- | --- |
| `make up` stops before creating the VM | The `prepare` or `check` message, libvirt access, and whether the P1 server is running |
| A Pod is not `Running` | `sudo k3s kubectl describe pod <name>` and its Events section |
| app2 shows fewer than `3/3` ready replicas | `sudo k3s kubectl get pods -o wide` and `sudo k3s kubectl describe deployment app2` |
| A Host returns the wrong page | `sudo k3s kubectl describe ingress apps`, then check the matching Service and Pods |

`sudo k3s kubectl get deployments,services,ingress` gives a compact view of the route from HTTP request to Pod.

## P3: K3s, K3d, and GitOps

K3s is the lightweight Kubernetes distribution that runs the cluster. K3d runs K3s nodes as Docker containers, so P3 creates a cluster directly inside the outer Debian VM instead of creating another Vagrant VM. Argo CD watches Git for the desired Kubernetes objects and applies changes to the cluster. GitHub holds the desired image tag; the Kubernetes Deployment records the image running in `dev`.

```text
Outer Debian VM
  Docker → K3d cluster iot (one K3s server, no agents)
               ├─ namespace argocd → Argo CD → reads GitHub main
               │                              p3/confs/application/
               └─ namespace dev    → playground Deployment → Pod
                                    → playground ClusterIP Service :8888
```

The K3d configuration pins `rancher/k3s:v1.36.5-k3s1`. The installer pins K3d `v5.9.0` and kubectl `v1.36.5`; the vendored Argo CD manifest uses `quay.io/argoproj/argocd:v3.3.16`.

### P3 file map

| File | Purpose |
| --- | --- |
| `p3/Makefile` | Commands to install tools, start/stop the cluster, inspect it, and forward local ports |
| `p3/scripts/install.sh` | Install Docker, K3d, and kubectl; verify K3d and kubectl download checksums |
| `p3/scripts/up.sh` | Create/start K3d, install Argo CD, register the GitHub Application, and wait for sync and health |
| `p3/confs/cluster.yaml` | Cluster `iot`, one K3s server, and a loopback port mapping |
| `p3/confs/namespaces.yaml` | `argocd` and `dev` namespaces |
| `p3/confs/argocd-install.yaml` | Vendored Argo CD installation resources |
| `p3/confs/argocd-application.yaml` | Git source, destination namespace, and automated sync policy |
| `p3/confs/application/deployment.yaml` | One `playground` replica and its versioned container image |
| `p3/confs/application/service.yaml` | Internal Service forwarding port `8888` to the Pod |

### Prepare and start P3

Run everything inside the outer Debian VM. The machine needs `sudo`, internet access for packages, binaries, GitHub, and container images, plus enough free disk and memory for Docker and Argo CD. The repository-root `Makefile` is for P1/P2 and invokes Vagrant; use the P3 Makefile from `p3`:

```bash
cd p3
make install
```

`make install` runs `p3/scripts/install.sh` with `sudo`. It installs `docker.io`, `curl`, and CA certificates through apt, enables Docker, downloads the pinned K3d and kubectl binaries, verifies their checksums, and installs them in `/usr/local/bin`. If it added your user to the `docker` group, log out of the Debian VM and back in before continuing. Confirm Docker access in that new session:

```bash
cd ~/inception-of-things/p3
docker info
make up
```

`make up` checks the required commands and Docker access, creates `iot` from `cluster.yaml` if absent or starts it if stopped, selects the `k3d-iot` kubectl context, and waits for the node to be Ready. It then applies the namespaces and Argo CD manifest, waits for Argo CD Deployments and its application-controller StatefulSet, creates the `playground` Application, and waits for `Synced` and `Healthy`. Running `make up` again is intended to reuse the same cluster and reapply configuration. It does not change the GitHub source image tag.

To stop the cluster without deleting it, run `make stop` from `p3`. A later `make up` starts the same cluster again.

### Where the desired state comes from

`p3/confs/argocd-application.yaml` creates an Argo CD `Application` named `playground` in `argocd`. Its source URL is `https://github.com/osivkov/inception-of-things.git`, branch `main`, path `p3/confs/application`; Argo CD needs public read access to that repository. Its destination is the in-cluster Kubernetes API and namespace `dev`. Automated sync is enabled with `prune` and `selfHeal`: Argo CD applies changes found in Git, removes managed resources deleted from Git, and restores managed resources changed directly in the cluster.

The assignment also requires a team login in the repository **name**. The configured repository is named `inception-of-things`; `osivkov` is its owner, so this requirement remains open. If the repository changes, update `repoURL` before switching versions through Git.

Only `deployment.yaml` and `service.yaml` in that source directory are the application payload. The Deployment currently declares `wil42/playground:v2`, one replica, and container port `8888`. The Service selects Pods labeled `app: playground` and exposes port `8888` inside the cluster. The Argo CD install manifest and Application definition are applied locally by `up.sh`; Argo CD then reads the application payload from the **remote** repository. A local edit that has not been pushed is not a GitOps deployment.

`cluster.yaml` maps `127.0.0.1:8080` on the outer VM to port `80` of the K3d load balancer. P3 has no Ingress for `playground`, so the documented way to reach the app is a `kubectl port-forward` to its Service on `localhost:8888`.

### Inspect P3 and access its interfaces

From `p3`:

```bash
make status
kubectl --context=k3d-iot get nodes
kubectl --context=k3d-iot get namespaces argocd dev
kubectl --context=k3d-iot -n argocd get application playground
kubectl --context=k3d-iot -n dev get deployment,service,pods
kubectl --context=k3d-iot -n dev get deployment playground -o jsonpath='{.spec.template.spec.containers[0].image}'
echo
```

In a healthy cluster, the node is Ready, both namespaces are Active, the Application is `Synced` and `Healthy`, and `playground` has one ready replica using the image in GitHub. To see the Git revision reported by Argo CD:

```bash
kubectl --context=k3d-iot -n argocd get application playground -o jsonpath='{.status.sync.revision}'
echo
```

Open the Argo CD UI from the same VM by running `make ui` in one terminal and visiting `https://localhost:9090`. The username is `admin`; `make password` prints the initial password from the cluster Secret. The browser may warn about the locally generated TLS certificate. If the password was changed, the initial Secret value is no longer the login password.

Run `make app` in a second terminal, then request the app in a third terminal:

```bash
curl -fsS http://localhost:8888/
```

The response should identify the deployed version (`v1` or `v2`). The two `make` port-forward commands keep running until stopped with Ctrl-C.

### Switch `v2 → v1 → v2` through Git

The tracked image starts at `wil42/playground:v2`. Before changing it, check which version is on GitHub `main` and keep unrelated local changes out of the commit. Leave `make app` running so `curl http://localhost:8888/` can check each version.

1. Show the current image in `p3/confs/application/deployment.yaml`, the image reported by `kubectl` in `dev`, Argo CD's `Synced`/`Healthy` status, and the HTTP response.
2. Change the Deployment image tag from `v2` to `v1`. Stage that file, choose your own commit message, and push the commit to the public GitHub `main` branch.
3. Let Argo CD reconcile the new Git revision. Show that its Application becomes `Synced` and `Healthy`, the Deployment image becomes `wil42/playground:v1`, its Pod is ready, and the HTTP response reports `v1`.
4. Change the image tag back to `v2`, commit and push again, and repeat the same checks for `v2`.

For each version change, stage only the application manifest and commit from the repository root. `git commit` opens your configured editor so you can choose the message:

```bash
cd ~/inception-of-things
git add p3/confs/application/deployment.yaml
git commit
git push origin main
```

Useful commands after each push, while `make app` is running in another terminal:

```bash
kubectl --context=k3d-iot -n argocd get application playground -o wide -w
# Stop the watch with Ctrl-C after it shows the new revision and healthy sync.
kubectl --context=k3d-iot -n dev get deployment playground -o wide
kubectl --context=k3d-iot -n dev rollout status deployment/playground --timeout=120s
kubectl --context=k3d-iot -n dev get pods
curl -fsS http://localhost:8888/
```

Git polling and image download can take time. Check the Application revision and Deployment image before expecting the new HTTP response. A direct `kubectl apply` of the local Deployment would bypass the GitHub change and does not show the required GitOps update.

### P3 troubleshooting

| Symptom | Check |
| --- | --- |
| `make up` stops at `docker info` | Confirm Docker is active (`systemctl status docker`) and the current login session has Docker access; log out and back in after `make install` added the group |
| K3d cluster creation fails | Inspect `k3d cluster list`, Docker availability, free disk space, and the error from `make up` |
| Argo CD does not become ready | Inspect `kubectl --context=k3d-iot -n argocd get pods` and describe a failing Pod for image pull or scheduling events |
| Application is not `Synced` | Inspect `kubectl --context=k3d-iot -n argocd describe application playground`; confirm the public repository, `main` branch, and `p3/confs/application` path are reachable |
| Application is `Synced` but not `Healthy` | Inspect the `dev` Deployment, Pods, and their events; confirm the `wil42/playground` image can be pulled |
| Git change does not appear | Confirm the version change was pushed to `main`, then compare `.status.sync.revision` with the pushed commit and check the Application conditions |
| `curl` cannot connect | Keep `make app` running in another terminal and check whether local port `8888` is free |

The pushed Git change, Argo CD revision, Deployment image, and HTTP response together show that the new version reached the cluster.
