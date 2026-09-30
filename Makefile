# Run checks when no target is specified.
.DEFAULT_GOAL := check

# Select P2 unless another module is requested.
PART ?= p2

.PHONY: prepare check up halt status

# Configure the outer Debian environment.
prepare:
	bash scripts/prepare.sh "$(PART)"

# Check the environment without changing it.
check:
	bash scripts/check.sh "$(PART)"

# Prepare, check, and start the selected module.
up: prepare
	bash scripts/check.sh "$(PART)"
	cd "$(PART)" && vagrant up --provider=libvirt

# Gracefully stop the selected module's VMs.
halt:
	cd "$(PART)" && vagrant halt

# Show the selected module's VM status.
status:
	cd "$(PART)" && vagrant status