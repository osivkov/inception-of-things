#!/usr/bin/env bash
set -euo pipefail

# Resolve the project root and select the requested module.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PART="${1:-p2}"
URI="qemu:///system"

# Identify the other module's server to prevent an IP conflict.
case "$PART" in
    p1) OTHER_SERVER="p2_osivkovS" ;;
    p2) OTHER_SERVER="p1_osivkovS" ;;
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

# Validate the Vagrantfile and check access to system libvirt.
vagrant validate
virsh -c "$URI" list --all >/dev/null

EPT_FILE="/sys/module/kvm_intel/parameters/ept"

# Check that the KVM Intel EPT parameter is readable.
if [[ ! -r "$EPT_FILE" ]]; then
    echo "KVM Intel EPT parameter is unavailable."
    exit 1
fi

# Verify the EPT setting required by our current workaround.
if [[ "$(cat "$EPT_FILE")" != "N" ]]; then
    echo "EPT is enabled. Run: make prepare PART=$PART"
    exit 1
fi

# Check that the private network is active.
if ! virsh -c "$URI" net-list --name | grep -Fxq iotnet; then
    echo "Network iotnet is inactive or missing."
    exit 1
fi

# Check that network autostart is enabled.
if ! virsh -c "$URI" net-list --autostart --name | grep -Fxq iotnet; then
    echo "Network iotnet has no autostart."
    exit 1
fi

# P1 and P2 servers share the same private IP address.
if virsh -c "$URI" list --name | grep -Fxq "$OTHER_SERVER"; then
    echo "Stop $OTHER_SERVER: it uses the same IP as $PART."
    exit 1
fi

echo "Environment checks passed for $PART."