VENDOR=aruba
NAME=vgw
IMAGE_FORMAT=ova

# Find the OVA file
OVA=$(shell ls -1 *.ova 2>/dev/null | head -1)

# Extract version from filename like ArubaOS_VGW_8.6.0.4-2.2.0.0_76431.ova -> 8.6.0.4-2.2.0.0_76431
VERSION=$(shell echo $(OVA) | sed -e 's/ArubaOS_VGW_\(.*\)\.ova/\1/' | sed -e 's/arubaos_vgw_\(.*\)\.ova/\1/')

# Docker image tag
DOCKER_IMAGE=vrnetlab/$(VENDOR)_$(NAME):$(VERSION)

# Try to include vrnetlab common makefiles, but don't fail if they don't exist
-include ../../makefile-sanity.include
-include ../../makefile.include

# If the common makefile.include wasn't found, define our own targets
ifeq ($(origin docker-build),undefined)

.PHONY: all build clean docker-build docker-clean

all: build

build: docker-build

docker-build:
	@if [ -z "$(OVA)" ]; then \
		echo "Error: No OVA image found."; \
		echo "Please place an ArubaOS_VGW_*.ova file in this directory."; \
		exit 1; \
	fi
	@echo "==> Extracting VMDKs from $(OVA)..."
	cd docker && tar xf ../$(OVA) --wildcards '*.vmdk'
	@echo "==> Converting disk1 VMDK to qcow2..."
	cd docker && qemu-img convert -p -f vmdk -O qcow2 \
		$$(ls -1 *disk1.vmdk 2>/dev/null || ls -1 *-disk1.vmdk 2>/dev/null) disk1.qcow2
	@echo "==> Converting disk2 VMDK to qcow2..."
	cd docker && qemu-img convert -p -f vmdk -O qcow2 \
		$$(ls -1 *disk2.vmdk 2>/dev/null || ls -1 *-disk2.vmdk 2>/dev/null) disk2.qcow2
	rm -f docker/*.vmdk docker/*.ovf docker/*.mf docker/*.cert
	@echo "==> Building Docker image $(DOCKER_IMAGE)..."
	(cd docker && docker build -t $(DOCKER_IMAGE) .)
	rm -f docker/disk1.qcow2 docker/disk2.qcow2
	@echo "==> Done: $(DOCKER_IMAGE)"

clean: docker-clean

docker-clean:
	rm -f docker/*.qcow2 docker/*.vmdk docker/*.ovf docker/*.mf docker/*.cert
	-docker rmi $(DOCKER_IMAGE) 2>/dev/null || true

endif
