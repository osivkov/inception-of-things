# Inception of Things (IoT)

Three Kubernetes setups built inside a Debian 13 VM. P1 and P2 use Vagrant and libvirt to create guest VMs. P3 runs K3d in Docker and uses Argo CD to deploy an app from GitHub.

## How the parts fit together

| Part | What it runs |
| --- | --- |
| P1 | Two VMs: a K3s server at `192.168.56.110` and an agent at `192.168.56.111` |
| P2 | One K3s VM with three HTTP apps; `app2` has three replicas, and Traefik routes by Host |
| P3 | One K3d cluster with Argo CD in `argocd` and `wil42/playground` in `dev` |

Start with the part you want to run below. [DEVELOPER.md](DEVELOPER.md) has the wiring behind each setup.

One P3 detail is still open: the repository is named `inception-of-things`, while the assignment asks for a team login in the **repository name**. `osivkov` currently appears only as the owner. If you rename or replace the repository, update `repoURL` in `p3/confs/argocd-application.yaml` too.

## Repository layout

```text
Makefile       P1/P2 VM commands
scripts/       Shared P1/P2 host preparation and checks
p1/           Two Vagrant VMs and K3s server/agent scripts
p2/           One Vagrant VM, three apps, and an Ingress
p3/           K3d, Argo CD, and the Git-managed playground app
DEVELOPER.md  Configuration and troubleshooting details
```

## Before running P1 or P2

- A Debian 13 VM with nested hardware virtualization available.
- Vagrant, the `vagrant-libvirt` plugin, QEMU/KVM, and system libvirt (`qemu:///system`).
- `sudo` access to prepare the environment.
- Internet access to download the Vagrant box, packages, and container images.

The `Makefile` does not install these tools. The preparation script uses `kvm_intel ept=0` for the current VirtualBox and nested KVM setup. Stop all running libvirt VMs before reloading the KVM module.

To check the EPT setting after rebooting the outer VM:

```bash
cat /sys/module/kvm_intel/parameters/ept
```

For this setup, the value should be `N`. The setting is saved in `/etc/modprobe.d/iot-kvm.conf`. This local workaround for nested virtualization may reduce performance.

## P1 quick start

Run from the repository root inside the outer Debian VM. P1 needs a matching `p1/confs/cluster_key` and `p1/confs/cluster_key.pub` pair before provisioning. The key files are ignored by Git. If the private key is absent, create the pair locally:

```bash
if [ ! -f p1/confs/cluster_key ]; then
  ssh-keygen -t ed25519 -N '' -f p1/confs/cluster_key
fi
if [ ! -f p1/confs/cluster_key.pub ]; then
  ssh-keygen -y -f p1/confs/cluster_key > p1/confs/cluster_key.pub
fi
```

Keep an existing private key; the commands above generate only missing files. Stop P2 first if it is running: the P1 and P2 servers share `192.168.56.110`.

```bash
make up PART=p1
cd p1
vagrant ssh osivkovS -c 'sudo k3s kubectl get nodes -o wide'
```

The node list should contain the server and worker, both `Ready`. To stop both VMs from `p1`, run `vagrant halt`. The [P1 implementation notes](DEVELOPER.md#p1-two-node-k3s-cluster) explain how the worker joins the server.

## P1: start

The root `Makefile` accepts `PART=p1` and defaults to `p2`. From the repository root:

```bash
make prepare PART=p1
make check PART=p1
make up PART=p1
make status PART=p1
```

`make up` already runs `prepare` and `check`. The separate commands are useful when diagnosing the outer VM. Preparation configures the nested-KVM EPT workaround and the `iotnet` libvirt network. Vagrant then creates both Debian VMs and provisions their shared setup, server, and worker scripts. The worker fetches the K3s join token over SSH from the server; it does not use the local `p1/confs/node-token` file.

## P1: verify

Run from `p1` inside the outer VM:

```bash
vagrant status
vagrant ssh osivkovS -c 'hostname; ip -4 addr show'
vagrant ssh osivkovSW -c 'hostname; ip -4 addr show'
vagrant ssh osivkovS -c 'sudo k3s kubectl get nodes -o wide'
vagrant ssh osivkovS -c 'sudo systemctl is-active k3s'
vagrant ssh osivkovSW -c 'sudo systemctl is-active k3s-agent'
```

Check the hostnames and private addresses against the P1 requirements, confirm both services are active, and confirm both Kubernetes nodes are `Ready`. `vagrant ssh` should connect without asking for a VM password. The worker-to-server SSH path used for the join token can be checked with `vagrant ssh osivkovSW -c 'ssh -o BatchMode=yes vagrant@192.168.56.110 hostname'`.

If the worker is missing from `kubectl get nodes`, inspect `vagrant ssh osivkovSW -c 'sudo systemctl status k3s-agent --no-pager'` and its provisioning output. The server script makes a brief, nonfatal `kubectl get nodes` attempt; successful VM provisioning alone does not prove both nodes are ready.

## P2 quick start

Run these commands from the **repository root inside the outer Debian VM** after installing the tools listed above. Stop the P1 server first if it is running, because P1 and P2 share the same private IP.

```bash
make up PART=p2
cd p2
vagrant ssh osivkovS -c 'sudo k3s kubectl get deployments,ingress'
curl -fsS --max-time 10 -H 'Host: app2.com' http://192.168.56.110/
```

The deployment list should include app1, app2, and app3; app2 should show `3/3` ready replicas. The HTTP command should print `Hello from app2`. To stop the VM from `p2`:

```bash
vagrant halt
```

## P2: start

Normally, `make up PART=p2` is enough. To inspect each preparation step separately, run these commands from the repository root inside the outer Debian VM:

```bash
make prepare PART=p2
make check PART=p2
make up PART=p2
make status PART=p2
```

`PART` defaults to `p2`. `make up` already runs `prepare` and `check`; running them separately is useful for diagnosis. `prepare` changes the KVM and libvirt network settings, `check` validates the environment, and `up` starts the VM and runs provisioning.

The P1 and P2 servers both use `192.168.56.110`, so do not run them at the same time. To stop P2:

```bash
make halt PART=p2
```

Provisioning should install K3s, apply all four application and Ingress YAML files from `p2/confs`, and wait for the three Deployments to become ready.

After changing YAML files on an existing VM, rerun provisioning from the repository root:

```bash
cd p2
vagrant provision osivkovS
```

This copies the manifests again and runs `kubectl apply`. A normal `vagrant up` on an existing VM may not rerun provisioning.

## P2: verify

From the repository root in the outer Debian VM:

```bash
cd p2
vagrant ssh osivkovS -c 'sudo k3s kubectl get nodes -o wide'
vagrant ssh osivkovS -c 'sudo k3s kubectl get deployments,services,ingress'
vagrant ssh osivkovS -c 'sudo k3s kubectl get pods -o wide'

curl -fsS --max-time 10 -H 'Host: app1.com' http://192.168.56.110/
curl -fsS --max-time 10 -H 'Host: app2.com' http://192.168.56.110/
curl -fsS --max-time 10 -H 'Host: unknown.example' http://192.168.56.110/
```

| Host sent to `192.168.56.110` | Expected response | Replicas |
| --- | --- | ---: |
| `app1.com` | HTML containing `Hello from app1` | 1 |
| `app2.com` | `Hello from app2` | 3 |
| Any other Host | `Hello from app3` | 1 |

The Host header lets you test the routes without DNS or `/etc/hosts`. To show the routing and replica count, run `sudo k3s kubectl describe ingress apps` and `sudo k3s kubectl get deployment app2` inside the VM.

If verification fails, check the VM and Pod status first:

```bash
vagrant status
vagrant ssh osivkovS -c 'sudo systemctl status k3s --no-pager'
vagrant ssh osivkovS -c 'sudo k3s kubectl get pods -A'
```

All application Pods should be `Running`, and the app2 Deployment should show `3/3` ready replicas. The HTTP requests also verify the Services and Ingress routing.

## P3 quick start

Run P3 commands from the `p3` directory **inside the outer Debian VM**. P3 uses Docker and K3d on that VM; it does not create a Vagrant guest. The root `Makefile` manages P1/P2 Vagrant VMs, so use `p3/Makefile` for P3.

```bash
cd p3
make install
```

If the installer added your user to the `docker` group, log out of the Debian VM and back in. Then return to `p3` and continue:

```bash
cd ~/inception-of-things/p3
make up
make status
```

`make install` needs `sudo` and internet access. It installs Docker, K3d, and kubectl; the script verifies the downloaded K3d and kubectl checksums. Run `make up` as a user who can access Docker (`docker info` must succeed). `make up` creates or starts the `iot` cluster, applies the two namespaces, installs Argo CD, creates its Application, and waits for `Synced` and `Healthy` status. It also selects the `k3d-iot` kubectl context. Use `make stop` to stop the cluster without deleting it.

## P3: architecture and repository

K3d runs K3s nodes inside Docker containers. Argo CD runs in the `argocd` namespace. Its `playground` Application is configured to read `https://github.com/osivkov/inception-of-things.git`, branch `main`, directory `p3/confs/application`, and deploy that directory's Deployment and Service to the `dev` namespace. The repository must be publicly readable. Automated sync, pruning, and self-healing are configured in `p3/confs/argocd-application.yaml`.

```text
GitHub main:p3/confs/application/
        │
        ▼
Argo CD Application (namespace argocd)
        │ automatic sync
        ▼
Deployment + Service playground (namespace dev)
        │
        ▼
wil42/playground:v2 on port 8888
```

The tracked Deployment currently requests `wil42/playground:v2`. The application has a single replica and its Service is internal (`ClusterIP`). Use `make app` to forward local port `8888` to the Service. `p3/confs/cluster.yaml` also maps host `127.0.0.1:8080` to load-balancer port `80`, but P3 defines no Ingress for `playground`; that mapping is not the documented application access path.

## P3: verify and access

From `p3`, inspect the cluster and the two namespaces:

```bash
make status
kubectl --context=k3d-iot get namespaces argocd dev
kubectl --context=k3d-iot -n argocd get application playground
kubectl --context=k3d-iot -n dev get deployment,service,pods
kubectl --context=k3d-iot -n dev get deployment playground -o jsonpath='{.spec.template.spec.containers[0].image}'
echo
```

Expect the Application to report `Synced` and `Healthy`, one ready `playground` replica in `dev`, and the image tag currently committed to GitHub. To view the Argo CD UI, run `make ui` in one terminal and open `https://localhost:9090` in the VM. Sign in as `admin`; `make password` prints the initial password from the Argo CD Secret. The UI uses a locally generated certificate, so the browser may display a certificate warning. The initial password may no longer work after it has been changed.

To request the application, run `make app` in another terminal and then, from the same VM:

```bash
curl -fsS http://localhost:8888/
```

The response should report the deployed version, for example `"message": "v2"` for the currently tracked image. Both `make ui` and `make app` keep their terminals occupied until you stop the port-forward with Ctrl-C.

## P3: change the version through Git

Argo CD reads the **pushed** `main` branch. A local edit alone will not change the cluster. Starting from the tracked `v2`, switch to `v1` and back:

1. Change only the `image:` line in `p3/confs/application/deployment.yaml` from `wil42/playground:v2` to `wil42/playground:v1`.
2. Commit and push that change to `main` in the public GitHub repository. Choose the commit message yourself.
3. Wait for Argo CD to observe the new revision and report `Synced` and `Healthy`. Check the Deployment image, Pod readiness, and `curl http://localhost:8888/`; the response should now report `v1`.
4. Change the same image line back to `wil42/playground:v2`, commit and push, then repeat the checks for `v2`.

Argo CD polls Git, so the update may take a few minutes. You can watch progress with `kubectl --context=k3d-iot -n argocd get application playground -w` (Ctrl-C to stop). Check the image actually deployed before interpreting the HTTP response. The procedure changes the Git-managed manifest; applying a local Deployment directly to Kubernetes would not demonstrate the required GitOps update.

## Network and VM resources

| Part | VM | Role | Private IP | vCPUs | RAM |
| --- | --- | --- | --- | ---: | ---: |
| P1 | `osivkovS` | K3s server | `192.168.56.110` | 2 | 2048 MiB |
| P1 | `osivkovSW` | K3s agent | `192.168.56.111` | 1 | 1024 MiB |
| P2 | `osivkovS` | K3s server | `192.168.56.110` | 3 | 3072 MiB |

Each VM has a Vagrant management interface and an additional private interface. The `iotnet` network uses `192.168.56.0/24`, the `virbr56` bridge, and `192.168.56.1` as its gateway. In P2, K3s uses `192.168.56.110` as its node IP and the script selects `eth1` for Flannel.
