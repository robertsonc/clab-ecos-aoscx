FROM ghcr.io/srl-labs/vrnetlab-base:0.2.1

RUN apt-get update -qy \
    && apt-get install -y --no-install-recommends \
    python3 \
    genisoimage \
    && rm -rf /var/lib/apt/lists/*

# The Makefile pre-converts the OVA's two VMDKs into disk1.qcow2 and disk2.qcow2
COPY disk1.qcow2 /
COPY disk2.qcow2 /
COPY *.py /
RUN chmod +x /launch.py

EXPOSE 22 80 443 4443 8080 8443 5000 12000-12099
ENTRYPOINT ["/launch.py"]
