#!/usr/bin/env bash
set -euo pipefail

# Resolve the project root and select the requested module.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PART="${1:-p2}"
URI="qemu:///system"

# Accept only modules supported by this script.
case "$PART" in
    p1|p2) ;;
    *)
        echo "Unsupported module: $PART. Use p1 or p2."
        exit 1
        ;;
esac

# Check that the required commands are available.
for cmd in vagrant virsh; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Command not found: $cmd"
        exit 1
    fi
done

cd "$ROOT/$PART"

# Validate the configuration before changing the system.
vagrant validate
virsh -c "$URI" list --all >/dev/null

if [[ ! -f confs/iotnet.xml ]]; then
    echo "Network configuration not found: $PART/confs/iotnet.xml"
    exit 1
fi

EPT_FILE="/sys/module/kvm_intel/parameters/ept"
EPT_CONFIG="/etc/modprobe.d/iot-kvm.conf"

# Disable EPT only when needed.
# This is a workaround for our nested VirtualBox/KVM environment.
if [[ ! -r "$EPT_FILE" ]] || [[ "$(cat "$EPT_FILE")" != "N" ]]; then
    RUNNING="$(virsh -c "$URI" list --name)"

    # Reloading KVM requires all active libvirt VMs to be stopped.
    if [[ -n "$RUNNING" ]]; then
        printf 'Stop the active VMs before changing EPT:\n%s\n' "$RUNNING"
        exit 1
    fi

    if [[ -d /sys/module/kvm_intel ]]; then
        sudo modprobe -r kvm_intel
    fi

    sudo modprobe kvm_intel ept=0
fi

# Preserve the EPT setting for subsequent module loads.
if ! grep -Fxq 'options kvm_intel ept=0' "$EPT_CONFIG" 2>/dev/null; then
    printf '%s\n' 'options kvm_intel ept=0' |
        sudo tee "$EPT_CONFIG"
fi

# Define the network only if it does not exist.
if ! virsh -c "$URI" net-info iotnet >/dev/null 2>&1; then
    virsh -c "$URI" net-define confs/iotnet.xml
fi

# Enable automatic network startup.
virsh -c "$URI" net-autostart iotnet

# Start the network only if it is inactive.
if ! virsh -c "$URI" net-list --name | grep -Fxq iotnet; then
    virsh -c "$URI" net-start iotnet
fi

echo "Environment prepared for $PART."