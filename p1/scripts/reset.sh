#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

URI="qemu:///system"
NETWORK="iotnet"

VMS=(
    "p1_osivkovS"
    "p1_osivkovSW"
)

echo "=================================="
echo " P1 FULL ENVIRONMENT RESET"
echo "=================================="

# ==================================================
# 1. Destroy Vagrant machines
# ==================================================

echo "[RESET] Destroying Vagrant machines..."

# Continue with libvirt cleanup if Vagrant metadata is broken.
if ! vagrant destroy -f; then
    echo "[WARN] Vagrant destroy failed."
    echo "[WARN] Continuing with direct libvirt cleanup."
fi

# ==================================================
# 2. Remove orphaned libvirt domains
# ==================================================

for vm in "${VMS[@]}"; do
    if virsh -c "$URI" dominfo "$vm" >/dev/null 2>&1; then
        echo "[RESET] Removing libvirt VM: $vm"

        state="$(virsh -c "$URI" domstate "$vm")"

        # Stop the VM only if it is running.
        if [[ "$state" != "shut off" ]]; then
            virsh -c "$URI" destroy "$vm"
        fi

        # Remove the domain and its managed storage.
        virsh -c "$URI" undefine "$vm" --remove-all-storage
    else
        echo "[OK] VM already absent: $vm"
    fi
done

# ==================================================
# 3. Verify VM removal
# ==================================================

echo "[RESET] Verifying libvirt domains..."

for vm in "${VMS[@]}"; do
    if virsh -c "$URI" dominfo "$vm" >/dev/null 2>&1; then
        echo "[ERROR] VM still exists: $vm"
        exit 1
    fi
done

echo "[OK] P1 virtual machines removed."

# ==================================================
# 4. Remove Vagrant metadata
# ==================================================

echo "[RESET] Removing Vagrant metadata..."

rm -rf -- .vagrant

# Clean stale global Vagrant references.
vagrant global-status --prune

# ==================================================
# 5. Remove libvirt network (only if no other part uses it)
# ==================================================

echo "[RESET] Cleaning network: $NETWORK"

if virsh -c "$URI" net-info "$NETWORK" >/dev/null 2>&1; then

    # The network is shared with other parts (p2, ...).
    # Keep it if running VMs from another part exist.
    if virsh -c "$URI" list --name | grep -E '^p[0-9]+_' | grep -vE '^p1_' | grep -q .; then
        echo "[WARN] VMs from another part are running; keeping network $NETWORK."
    else
        # Stop the network if active.
        if virsh -c "$URI" net-list --name | grep -Fxq "$NETWORK"; then
            echo "[RESET] Stopping network: $NETWORK"
            virsh -c "$URI" net-destroy "$NETWORK"
        fi

        # Remove the network definition.
        echo "[RESET] Undefining network: $NETWORK"
        virsh -c "$URI" net-undefine "$NETWORK"
    fi
else
    echo "[OK] Network already absent."
fi

# ==================================================
# 6. Remove P1 SSH host fingerprints
# ==================================================

echo "[RESET] Removing P1 SSH host fingerprints..."

ssh-keygen -R 192.168.56.110 >/dev/null 2>&1 || true
ssh-keygen -R 192.168.56.111 >/dev/null 2>&1 || true

# ==================================================
# 7. Remove generated cluster SSH keys
# ==================================================

echo "[RESET] Removing generated cluster keys..."

rm -f -- \
    confs/cluster_key \
    confs/cluster_key.pub

# ==================================================
# 8. Final verification
# ==================================================

echo ""
echo "=================================="
echo " P1 RESET COMPLETE"
echo "=================================="
echo "VMs:          Removed"
echo "Vagrant:      Metadata cleaned"
echo "Network:      Removed (or kept if shared and in use)"
echo "SSH keys:     Removed"
echo ""
echo "Environment ready for fresh deployment."
