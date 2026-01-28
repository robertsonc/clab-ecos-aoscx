# EdgeConnect (ECOS) vrnetlab Node

This directory contains the vrnetlab components for building HPE Aruba EdgeConnect Virtual (EC-V) container images.

## Contents

```
ecos/
├── Makefile           # Build automation
├── README.md          # This file
└── docker/
    ├── Dockerfile     # Container image definition
    └── launch.py      # VM launch and management script
```

## VM Specifications

For EdgeConnect EC-V virtual appliance specifications including RAM, CPU, and disk requirements, refer to the official HPE Aruba SD-WAN documentation:

**https://arubanetworking.hpe.com/techdocs/sdwan/**

## Usage

1. Copy this folder to your vrnetlab installation:
   ```bash
   cp -r ecos /path/to/vrnetlab/aruba/
   ```

2. Place your EdgeConnect qcow2 image in the folder:
   ```bash
   cp ECV-*.qcow2 /path/to/vrnetlab/aruba/ecos/
   ```

3. Build the Docker image:
   ```bash
   cd /path/to/vrnetlab/aruba/ecos
   make docker-image
   ```

## Interface Mapping

| Container Interface | VM Interface | Purpose |
|---------------------|--------------|---------|
| eth0 | mgmt0 | Management (DHCP) |
| eth1 | wan0 | Primary WAN |
| eth2 | lan0 | Primary LAN |
| eth3 | wan1 | Secondary WAN |
| eth4 | lan1 | Secondary LAN |
| eth5 | ha | High Availability |

## License

EdgeConnect is a product of HPE Aruba Networks. This vrnetlab integration adapts patterns from the vrnetlab project.
