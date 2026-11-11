.DEFAULT_GOAL := help

S  = osivkovS
SW = osivkovSW

.PHONY: help up down status clean re kvm-off ssh-s ssh-sw \
        eval check-vms check-host check-net check-ssh check-k3s nodes

# ---------- lifecycle ----------
up:
	vagrant up

down:
	vagrant halt

status:
	vagrant status

clean:
	vagrant destroy -f
	rm -f confs/node-token

re: clean up

# free VT-x if KVM holds it (VERR_VMX_IN_VMX_ROOT_MODE)
kvm-off:
	-sudo systemctl stop libvirtd libvirtd.socket
	-sudo modprobe -r kvm_intel kvm_amd
	-sudo modprobe -r kvm

ssh-s:
	vagrant ssh $(S)

ssh-sw:
	vagrant ssh $(SW)

# ---------- evaluation ----------
eval: check-vms check-host check-net check-ssh check-k3s nodes
	@echo
	@echo "=== P1 EVAL: DONE ==="

check-vms:
	@echo "=== 1. Machines and resources (VirtualBox) ==="
	@vagrant status
	@for vm in $(S) $(SW); do \
		echo "--- $$vm ---"; \
		VBoxManage showvminfo $$vm --machinereadable | grep -E '^(name|memory|cpus)='; \
	done

check-host:
	@echo "=== 2. Hostname, OS, CPU/RAM inside the VMs ==="
	@for vm in $(S) $(SW); do \
		echo "--- $$vm ---"; \
		vagrant ssh $$vm -c 'hostname; grep PRETTY_NAME /etc/os-release; echo "CPU: $$(nproc)"; free -m | sed -n "1,2p"' 2>/dev/null; \
	done

check-net:
	@echo "=== 3. Dedicated IPs on the host-only interface ==="
	@vagrant ssh $(S)  -c 'ip -br -4 a | grep 192.168.56.110' 2>/dev/null
	@vagrant ssh $(SW) -c 'ip -br -4 a | grep 192.168.56.111' 2>/dev/null
	@echo "--- connectivity between machines ---"
	@vagrant ssh $(S)  -c 'ping -c 2 -W 2 192.168.56.111' 2>/dev/null
	@vagrant ssh $(SW) -c 'ping -c 2 -W 2 192.168.56.110' 2>/dev/null

check-ssh:
	@echo "=== 4. Passwordless SSH (BatchMode) ==="
	@for vm in $(S) $(SW); do \
		vagrant ssh-config $$vm > /tmp/ssh-$$vm.cfg; \
		ssh -F /tmp/ssh-$$vm.cfg -o BatchMode=yes -o StrictHostKeyChecking=no $$vm 'echo "$$(hostname): ssh OK, no password needed"' 2>/dev/null; \
		rm -f /tmp/ssh-$$vm.cfg; \
	done

check-k3s:
	@echo "=== 5. K3s modes: server / agent ==="
	@echo "--- $(S): server ---"
	@vagrant ssh $(S)  -c 'systemctl is-active k3s; systemctl cat k3s | grep -A3 ExecStart | tr -d "\\\\"; k3s --version | head -1' 2>/dev/null
	@echo "--- $(SW): agent ---"
	@vagrant ssh $(SW) -c 'systemctl is-active k3s-agent; systemctl cat k3s-agent | grep -A3 ExecStart | tr -d "\\\\"' 2>/dev/null

nodes:
	@echo "=== 6. kubectl: nodes ==="
	@vagrant ssh $(S) -c 'kubectl get nodes -o wide' 2>/dev/null
	@echo "--- system pods ---"
	@vagrant ssh $(S) -c 'kubectl get pods -A' 2>/dev/null



# ---------- help ----------
help:
	@echo ""
	@echo "=== P1 Commands ==="
	@echo ""
	@echo "--- Lifecycle ---"
	@echo "make up          -> vagrant up"
	@echo "make down        -> vagrant halt"
	@echo "make status      -> vagrant status"
	@echo "make clean       -> vagrant destroy -f"
	@echo "                    rm -f confs/node-token"
	@echo "make re          -> make clean && make up"
	@echo ""
	@echo "--- Virtualization ---"
	@echo "make kvm-off     -> sudo systemctl stop libvirtd libvirtd.socket"
	@echo "                    sudo modprobe -r kvm_intel kvm_amd"
	@echo "                    sudo modprobe -r kvm"
	@echo ""
	@echo "--- SSH ---"
	@echo "make ssh-s       -> vagrant ssh osivkovS"
	@echo "make ssh-sw      -> vagrant ssh osivkovSW"
	@echo ""
	@echo "--- Evaluation ---"
	@echo "make eval        -> make check-vms check-host check-net check-ssh check-k3s nodes"
	@echo ""
	@echo "make check-vms   -> vagrant status"
	@echo "                    VBoxManage showvminfo VM --machinereadable"
	@echo "                    grep name, memory, cpus"
	@echo ""
	@echo "make check-host  -> vagrant ssh VM -c 'hostname'"
	@echo "                    cat /etc/os-release"
	@echo "                    nproc"
	@echo "                    free -m"
	@echo ""
	@echo "make check-net   -> ip -br -4 a"
	@echo "                    ping -c 2 -W 2 192.168.56.110"
	@echo "                    ping -c 2 -W 2 192.168.56.111"
	@echo ""
	@echo "make check-ssh   -> vagrant ssh-config VM"
	@echo "                    ssh -F /tmp/ssh-VM.cfg -o BatchMode=yes VM"
	@echo ""
	@echo "make check-k3s   -> systemctl is-active k3s"
	@echo "                    systemctl is-active k3s-agent"
	@echo "                    systemctl cat k3s / k3s-agent"
	@echo "                    k3s --version"
	@echo ""
	@echo "make nodes       -> vagrant ssh osivkovS -c 'kubectl get nodes -o wide'"
	@echo "                    vagrant ssh osivkovS -c 'kubectl get pods -A'"
	@echo ""
	@echo "--- Help ---"
	@echo "make help        -> Show this command list"
	@echo ""
