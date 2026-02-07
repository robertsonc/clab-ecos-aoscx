FROM ghcr.io/srl-labs/vrnetlab-base:0.2.1

RUN apt-get update -qy \
    && apt-get install -y --no-install-recommends \
    python3 \
    && rm -rf /var/lib/apt/lists/*

ARG IMAGE
COPY $IMAGE* /
COPY *.py /
RUN chmod +x /launch.py

# TODO: Adjust exposed ports once VGW requirements are confirmed
EXPOSE 22 80 443 830 5000 12000-12099
ENTRYPOINT ["/launch.py"]
