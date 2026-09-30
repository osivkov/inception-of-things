# Inception of Things

A learning project focused on virtual machines, Kubernetes networking,
and application deployment with K3s.

## Environment

The project runs inside a Debian 13 virtual machine hosted by VirtualBox
on a Codam workstation.

Inside Debian, Vagrant uses the libvirt provider and QEMU/KVM to run the
project VMs. The outer Debian VM has approximately 5.8 GiB RAM and 6 vCPUs.

## Project status

| Part | Current progress |
|------|------------------|
| P1 | Server and worker connected; both nodes verified Ready |
| P2 | Single-node cluster and app1 HTTP routing verified |
| P3 | Not started |

P2 is still in progress. The remaining work includes app2 with three
replicas, app3 as the default application, and automatic manifest deployment.

## Repository layout

```text
Makefile
scripts/                Environment preparation and checks
p1/
  Vagrantfile           Server and worker VM definitions
  scripts/              K3s provisioning scripts
  confs/                Network configuration and local SSH files
p2/
  Vagrantfile           Single server VM definition
  scripts/server.sh     K3s installation
  confs/iotnet.xml       Private libvirt network
  confs/app1.yaml        app1 Deployment and Service
  confs/ingress.yaml     HTTP routing rules
p3/                     Reserved for the next part
```

## Prerequisites

The outer Debian environment requires:

- Vagrant and the vagrant-libvirt plugin
- QEMU/KVM and system libvirt
- Access to `qemu:///system`
- Nested hardware virtualization enabled in the outer hypervisor
- sudo access for environment preparation
- Internet access for box, package, and container image downloads

The Makefile assumes these tools are already installed.

## Virtual machines

| Part | VM | Role | Private IP | vCPUs | RAM |
|------|----|------|------------|-------|-----|
| P1 | osivkovS | K3s server | 192.168.56.110 | 2 | 2048 MiB |
| P1 | osivkovSW | K3s agent | 192.168.56.111 | 1 | 1024 MiB |
| P2 | osivkovS | K3s server | 192.168.56.110 | 3 | 3072 MiB |

P1 and P2 servers use the same private IP. Stop one part before starting
the other.

## Environment preparation

Run commands from the repository root:

```bash
make prepare PART=p2
make check PART=p2
make up PART=p2
make status PART=p2
make halt PART=p2
```

`PART` defaults to `p2`.

- `prepare` configures the KVM EPT workaround and the private network.
- `check` validates the selected Vagrantfile and checks the environment.
- `up` prepares, checks, and starts the selected part.
- `halt` shuts down the VMs while preserving their disks.

### Nested virtualization workaround

VirtualBox previously crashed while running nested KVM guests.
Disabling EPT in the outer Debian KVM module is currently used as a workaround.

The preparation script loads `kvm_intel` with `ept=0` when needed and saves:

```text
options kvm_intel ept=0
```

in `/etc/modprobe.d/iot-kvm.conf`.

All active libvirt VMs must be stopped before reloading the KVM module.
Verify the setting after reboot:

```bash
cat /sys/module/kvm_intel/parameters/ept
```

The expected value for this workaround is `N`. This setting is specific
to the current environment, may reduce performance, and is not proof
that the original VirtualBox fault has been permanently resolved.

## Networking

- `vagrant-libvirt`: management network using DHCP.
- `iotnet`: private NAT network, `192.168.56.0/24`.
- `virbr56`: bridge for iotnet, with gateway address `192.168.56.1`.
- `eth0` inside the project VMs: management interface.
- `eth1` inside the project VMs: static private address.

K3s in P2 uses `192.168.56.110` as its node IP and `eth1` for Flannel.

## P1 local SSH key

P1 provisioning requires these local files:

```text
p1/confs/cluster_key
p1/confs/cluster_key.pub
```

If the private key is missing after cloning, generate a new pair:

```bash
ssh-keygen -t ed25519 -N '' -f p1/confs/cluster_key
```

The private key is intentionally excluded from Git. The worker uses SSH
to retrieve the current K3s join token from the server. A local
`confs/node-token` file is not used by the current provisioning scripts.

## P2 application deployment

K3s installation runs through Vagrant shell provisioning.

Application manifests currently need to be applied manually from `p2`:

```bash
cd p2

vagrant ssh osivkovS -c 'sudo k3s kubectl apply -f -' < confs/app1.yaml
vagrant ssh osivkovS -c 'sudo k3s kubectl apply -f -' < confs/ingress.yaml
```

app1 uses:

- Deployment: one replica of `hashicorp/http-echo:1.0.0`
- Container HTTP port: `5678`
- Service: `ClusterIP`, port `80` forwarding to `5678`
- Ingress: `app1.com`, handled by Traefik

## Verification

From the outer Debian VM:

```bash
cd p2

vagrant ssh osivkovS -c 'sudo k3s kubectl get nodes -o wide'
vagrant ssh osivkovS -c 'sudo k3s kubectl get pods -A'

curl -fsS --max-time 10 -H 'Host: app1.com' http://192.168.56.110
```

Expected HTTP response:

```text
Hello from app1
```

The Host header allows testing without modifying DNS or `/etc/hosts`.

