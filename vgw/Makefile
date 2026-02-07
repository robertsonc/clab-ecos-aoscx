VENDOR=aruba
NAME=vgw
IMAGE_FORMAT=qcow2
IMAGE_GLOB=*.qcow2

# Extract version from filename like VGW-9.5.6.0_103864.qcow2 -> 9.5.6.0_103864
# TODO: Update the sed pattern once the actual VGW image naming convention is known
VERSION=$(shell echo $(IMAGE) | sed -e 's/VGW-\(.*\)\.qcow2/\1/' | sed -e 's/vgw-\(.*\)\.qcow2/\1/')

# Try to include vrnetlab common makefiles, but don't fail if they don't exist
-include ../../makefile-sanity.include
-include ../../makefile.include

# If the common makefile.include wasn't found, define our own targets
ifeq ($(origin docker-build),undefined)

# Find the image file
IMAGE=$(shell ls -1 *.qcow2 2>/dev/null | head -1)

# Docker image tag
DOCKER_IMAGE=vrnetlab/$(VENDOR)_$(NAME):$(VERSION)

.PHONY: all build clean docker-build docker-clean

all: build

build: docker-build

docker-build:
	@if [ -z "$(IMAGE)" ]; then \
	        echo "Error: No qcow2 image found. Please place a VGW-*.qcow2 file in this directory."; \
	        exit 1; \
	fi
	@echo "Building $(DOCKER_IMAGE) from $(IMAGE)"
	cp $(IMAGE) docker/
	(cd docker && docker build --build-arg IMAGE=$(IMAGE) -t $(DOCKER_IMAGE) .)
	rm -f docker/$(IMAGE)

clean: docker-clean

docker-clean:
	rm -f docker/*.qcow2
	-docker rmi $(DOCKER_IMAGE) 2>/dev/null || true

endif
