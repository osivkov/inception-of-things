# Inception of Things (IoT)

A learning project about Vagrant, K3s, and HTTP routing in Kubernetes. The project runs inside a Debian 13 VM: Vagrant uses the libvirt provider to create nested VMs on QEMU/KVM.

## The project in one minute

P2 creates one Debian VM with the private IP `192.168.56.110`. Provisioning installs a single-node K3s cluster and deploys three small websites. Traefik reads the HTTP Host header: `app1.com` goes to app1, `app2.com` goes to app2, and every other Host goes to app3. App2 has three Pod replicas.

```text
Outer Debian VM
  └─ Vagrant + libvirt → osivkovS (192.168.56.110)
                         └─ K3s → Traefik → app1 / app2 / app3
```

If you are returning to the project after a break, read [Quick start](#quick-start), then [P2: verify](#p2-verify). [DEVELOPER.md](DEVELOPER.md) explains what each component does and how to change it.

## Project status

| Part | Status based on repository files |
| --- | --- |
| P1 | Server and worker configuration is present; the previous README reported both nodes as Ready |
| P2 | Three applications, three app2 replicas, and an Ingress are configured; the current cluster state still needs runtime verification |
| P3 | Not implemented |

P2 was reviewed from source files only. No VM, K3s cluster, or application was started during this review.

## P2 requirements checklist

| Requirement | Evidence in the repository |
| --- | --- |
| One VM named after a team login with an S suffix | `p2/Vagrantfile` defines only `osivkovS` |
| Private IP `192.168.56.110` | `p2/Vagrantfile` and `p2/confs/iotnet.xml` |
| K3s in server mode | `p2/scripts/server.sh` installs and starts K3s |
| Three web applications | `p2/confs/app1.yaml`, `app2.yaml`, and `app3.yaml` |
| Three replicas of application 2 | `p2/confs/app2.yaml` sets `replicas: 3` |
| Host-based routing and app3 as the default | `p2/confs/ingress.yaml` has rules for `app1.com`, `app2.com`, and a rule without a Host |

All required P2 components are present in the source files. A static review cannot confirm that provisioning succeeds, images can be pulled, Pods become ready, or HTTP requests return the expected responses.

## Repository layout

```text
Makefile                 Prepare, check, and manage VMs
scripts/                 Prepare and check the outer Debian VM
p1/
  Vagrantfile            Two VMs: server and worker
  scripts/               K3s installation
  confs/                 Network configuration and public SSH key
p2/
  Vagrantfile            One VM: K3s server
  scripts/server.sh      K3s installation and manifest deployment
  confs/iotnet.xml       Private libvirt network
  confs/app1.yaml        HTML page, Deployment, and Service for app1
  confs/app2.yaml        Deployment and Service for app2
  confs/app3.yaml        Deployment and Service for app3
  confs/ingress.yaml     Traefik HTTP routes
p3/                     Empty for now
DEVELOPER.md             Development and verification guide
```

## Environment requirements

- A Debian 13 VM with nested hardware virtualization available.
- Vagrant, the `vagrant-libvirt` plugin, QEMU/KVM, and system libvirt (`qemu:///system`).
- `sudo` access to prepare the environment.
- Internet access to download the Vagrant box, packages, and container images.

The `Makefile` does not install these tools. The preparation script uses `kvm_intel ept=0` for the current VirtualBox and nested KVM setup. Stop all running libvirt VMs before reloading the KVM module.

To check the EPT setting after rebooting the outer VM:

```bash
cat /sys/module/kvm_intel/parameters/ept
```

The expected value for this setup is `N`. The setting is saved in `/etc/modprobe.d/iot-kvm.conf`. This is a local workaround for nested virtualization and may reduce performance.

## Quick start

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

The commands above describe the expected workflow; they have not been executed as part of this review.

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

The Host header lets you test the routes without DNS or `/etc/hosts`. During the defense, also show the Ingress and app2 replica count with `sudo k3s kubectl describe ingress apps` and `sudo k3s kubectl get deployment app2` inside the VM.

If verification fails, check the VM and Pod status first:

```bash
vagrant status
vagrant ssh osivkovS -c 'sudo systemctl status k3s --no-pager'
vagrant ssh osivkovS -c 'sudo k3s kubectl get pods -A'
```

All application Pods should be `Running`, and the app2 Deployment should show `3/3` ready replicas. The HTTP requests also verify the Services and Ingress routing.

## Network and VM resources

| Part | VM | Role | Private IP | vCPUs | RAM |
| --- | --- | --- | --- | ---: | ---: |
| P1 | `osivkovS` | K3s server | `192.168.56.110` | 2 | 2048 MiB |
| P1 | `osivkovSW` | K3s agent | `192.168.56.111` | 1 | 1024 MiB |
| P2 | `osivkovS` | K3s server | `192.168.56.110` | 3 | 3072 MiB |

Each VM has a Vagrant management interface and a private `eth1` interface. The `iotnet` network uses `192.168.56.0/24`, the `virbr56` bridge, and `192.168.56.1` as its gateway. In P2, K3s uses `192.168.56.110` as its node IP and `eth1` for Flannel.

## P1: local SSH key

P1 provisioning needs `p1/confs/cluster_key` and `p1/confs/cluster_key.pub`. If the private key is missing after cloning, create a new pair:

```bash
ssh-keygen -t ed25519 -N '' -f p1/confs/cluster_key
```

The private key is excluded from Git. The worker retrieves the K3s join token from the server over SSH; the current scripts do not use a local `confs/node-token` file.

For the architecture, development workflow, and troubleshooting steps, see [DEVELOPER.md](DEVELOPER.md).
