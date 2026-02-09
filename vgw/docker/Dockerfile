FROM ghcr.io/srl-labs/vrnetlab-base:0.2.1

RUN apt-get update -qy \
    && apt-get install -y --no-install-recommends \
    python3 \
    genisoimage \
    qemu-utils \
    && rm -rf /var/lib/apt/lists/*

# The Makefile extracts the two VMDKs from the OVA into the build context.
# Convert them to qcow2 here where qemu-img is available, then remove the
# VMDKs to keep the final image small.
COPY disk1.vmdk /tmp/disk1.vmdk
COPY disk2.vmdk /tmp/disk2.vmdk
RUN qemu-img convert -f vmdk -O qcow2 /tmp/disk1.vmdk /disk1.qcow2 \
    && qemu-img convert -f vmdk -O qcow2 /tmp/disk2.vmdk /disk2.qcow2 \
    && rm -f /tmp/disk1.vmdk /tmp/disk2.vmdk

COPY *.py /
RUN chmod +x /launch.py

EXPOSE 22 80 443 4443 8080 8443 5000 12000-12099
ENTRYPOINT ["/launch.py"]
