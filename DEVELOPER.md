# Developer guide

Use this guide when you need to rebuild P2, explain it during the defense, or change an application. For the shortest command sequence, see [Quick start](README.md#quick-start).

## Stack at a glance

| Layer | Technology | Job in this project |
| --- | --- | --- |
| Outer environment | Debian 13 in VirtualBox | Runs the tools that create the project VM |
| VM automation | Vagrant and `vagrant-libvirt` | Defines, starts, and provisions `osivkovS` |
| Virtualization and network | QEMU/KVM and libvirt | Runs the nested VM and provides the private `iotnet` network |
| Kubernetes | K3s (`v1.36.5+k3s1` in the install script) | Runs the single-node cluster and the three applications |
| Pod network | Flannel | Carries traffic between Kubernetes workloads |
| HTTP entry point | Traefik and a Kubernetes Ingress | Selects an application from the request's Host header |
| Applications | Nginx and `hashicorp/http-echo` | Serve the app1 HTML page and the app2/app3 text responses |

The practical order to remember is: **Vagrant creates the VM → K3s runs Kubernetes → Services find Pods → Traefik routes incoming HTTP requests.**

## Technology stack and request flow

The project runs inside an outer Debian 13 VM. Vagrant with `vagrant-libvirt` creates VMs on QEMU/KVM. The private `iotnet` network gives the P2 server the address `192.168.56.110`; Vagrant uses a separate management interface for SSH and provisioning. The `p2/scripts/server.sh` script installs K3s in server mode. K3s provides the Kubernetes API, `kubectl`, Flannel networking, and the Traefik Ingress controller.

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

## File map

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

## Change an application

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

## Verify the deployment

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

Expected result: one app1 Pod, three app2 Pods, and one app3 Pod in `Running` state; the app2 Deployment should show `3/3` ready replicas. The HTTP responses should contain `Hello from app1` (HTML), `Hello from app2`, and `Hello from app3`, respectively. Show the Ingress during the defense: it is intentionally omitted from the example output in the assignment.

If something fails, check `vagrant status`, then `sudo systemctl status k3s`, `sudo k3s kubectl get pods -A`, and `sudo k3s kubectl describe pod <name>` inside the VM. If disk space is low, inspect large directories in the outer VM with `du -xhd2 ~/ | sort -hr`.

### Common checks

| Symptom | First thing to inspect |
| --- | --- |
| `make up` stops before creating the VM | The `prepare` or `check` message, libvirt access, and whether the P1 server is running |
| A Pod is not `Running` | `sudo k3s kubectl describe pod <name>` and its Events section |
| app2 shows fewer than `3/3` ready replicas | `sudo k3s kubectl get pods -o wide` and `sudo k3s kubectl describe deployment app2` |
| A Host returns the wrong page | `sudo k3s kubectl describe ingress apps`, then check the matching Service and Pods |

The first useful check after starting is `sudo k3s kubectl get deployments,services,ingress`. It shows the three layers involved in HTTP delivery without searching through every cluster object.

## Scope of the current review

This guide is based on the repository files. The running VM, image availability, Pod readiness, and Ingress responses still need to be verified in the working environment.
