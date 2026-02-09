VENDOR=aruba
NAME=vgw
IMAGE_FORMAT=ova
IMAGE_GLOB=*.ova

# Extract version from filename like ArubaOS_VGW_10.8.0.0_94533.ova -> 10.8.0.0_94533
VERSION=$(shell echo $(IMAGE) | sed -e 's/ArubaOS_VGW_\(.*\)\.ova/\1/' | sed -e 's/arubaos_vgw_\(.*\)\.ova/\1/')

# Try to include vrnetlab common makefiles, but don't fail if they don't exist
-include ../../makefile-sanity.include
-include ../../makefile.include

# Override docker-build-image-copy from makefile.include:
# The VGW OVA contains two VMDKs that must be extracted and converted to
# qcow2 before the Docker build. The default `cp $(IMAGE)* docker/` won't
# work because the Dockerfile expects disk1.qcow2 and disk2.qcow2.
docker-build-image-copy:
	@echo "==> Extracting VMDKs from $(IMAGE)..."
	tar xf $(IMAGE) --wildcards '*.vmdk'
	@echo "==> Converting disk1 VMDK to qcow2..."
	qemu-img convert -p -f vmdk -O qcow2 \
		$$(ls -1 *-disk1.vmdk 2>/dev/null | head -1) docker/disk1.qcow2
	@echo "==> Converting disk2 VMDK to qcow2..."
	qemu-img convert -p -f vmdk -O qcow2 \
		$$(ls -1 *-disk2.vmdk 2>/dev/null | head -1) docker/disk2.qcow2
	rm -f *.vmdk *.ovf *.mf *.cert

# If the common makefile.include wasn't found, define our own targets
ifeq ($(origin docker-build),undefined)

OVA=$(shell ls -1 *.ova 2>/dev/null | head -1)
DOCKER_IMAGE=vrnetlab/$(VENDOR)_$(NAME):$(VERSION)

.PHONY: all build clean docker-build docker-clean

all: build

build: docker-build

docker-build:
	@if [ -z "$(OVA)" ]; then \
		echo "Error: No OVA image found."; \
		echo "Please place an ArubaOS_VGW_*.ova file in this directory."; \
		exit 1; \
	fi
	@echo "Building $(DOCKER_IMAGE) from $(OVA)"
	$(MAKE) IMAGE=$(OVA) docker-build-image-copy
	(cd docker && docker build -t $(DOCKER_IMAGE) .)
	rm -f docker/disk1.qcow2 docker/disk2.qcow2

clean: docker-clean

docker-clean:
	rm -f docker/*.qcow2 docker/*.vmdk
	-docker rmi $(DOCKER_IMAGE) 2>/dev/null || true

endif
