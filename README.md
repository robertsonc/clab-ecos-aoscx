# ECOS + AOS-CX ContainerLab

Run HPE Aruba EdgeConnect SD-WAN and AOS-CX switches together in ContainerLab.

## What's This?

This repo provides everything needed to run a complete EdgeConnect SD-WAN lab with:
- **EdgeConnect Virtual (EC-V)** - SD-WAN appliances with Orchestrator preconfigurations
- **AOS-CX Virtual (vCX)** - Data center switches with full VXLAN/EVPN, BGP, OSPF, and VRF configurations
- **Linux transport nodes** - Simulating internet and MPLS WAN networks with DHCP
- **Test clients** - Per-segment clients for validating end-to-end connectivity
- **Deploy/destroy scripts** - Automated topology deployment with config push and teardown

Built on [vrnetlab](https://github.com/srl-labs/vrnetlab) for packaging VMs in containers and [ContainerLab](https://containerlab.dev/) for topology orchestration.

### Lab Topology

![Lab Topology](topology.png)

The lab consists of two independent 3-site topologies that can be deployed individually or together:

**Topology 1: CHI-STL-DFW** (Chicago, St. Louis, Dallas)
- DFW-ECV-01 `lan0` ↔ DFW-vCX-01 `1/1/1`
- STL-ECV-01 `lan0` ↔ STL-vCX-01 `1/1/1`
- CHI-ECV-01 `lan0` ↔ CHI-vCX-01 `1/1/1`
- All EC-V `wan0` → **internet** transport node
- All EC-V `wan1` → **mpls** transport node
- 9 test clients (3 per site: managed, unmanaged, guest)

**Topology 2: SEA-SFO-LAS** (Seattle, San Francisco, Las Vegas)
- SEA-ECV-01 `lan0` ↔ SEA-vCX-01 `1/1/1`
- SFO-ECV-01 `lan0` ↔ SFO-vCX-01 `1/1/1`
- LAS-ECV-01 `lan0` ↔ LAS-vCX-01 `1/1/1`
- All EC-V `wan0` → **internet** transport node
- All EC-V `wan1` → **mpls** transport node
- 9 test clients (3 per site: managed, unmanaged, guest)

Each topology uses its own transport nodes with unique management IPs to allow both to run simultaneously.

### Network Design

Each site follows the same architecture:

- **EdgeConnect EC-V** handles SD-WAN overlay, connecting to two WAN transports (internet + MPLS) and one LAN interface to the local vCX switch
- **AOS-CX vCX** provides LAN switching with three customer segments (VRFs) and VXLAN/EVPN for cross-site L2/L3 connectivity
- **Test clients** attach to access ports on the vCX, one per customer segment

**Routing and overlay stack:**

| Layer | Technology | Details |
|-------|-----------|---------|
| Underlay | OSPF (area 0) | EC-V ↔ vCX LAN adjacency, loopback reachability |
| Overlay control | BGP (eBGP multihop) | EC-V AS 64001 ↔ vCX AS 65001, L2VPN EVPN address-family |
| Overlay data | VXLAN | 6 VNIs per site (3 L2 bridge + 3 L3 routing per VRF) |
| Segmentation | VRFs | CSN_Managed, CSN_Unmanaged, CSN_Guest |
| VLANs | 1010, 1011, 1012 | Mapped to Managed, Unmanaged, Guest segments |
| Client services | DHCP | Per-VRF DHCP servers on each vCX |

### What Gets Configured Automatically

**AOS-CX switches** receive full startup configurations via the deploy script:
- VRFs (CSN_Managed, CSN_Unmanaged, CSN_Guest) with EVPN route-targets
- OSPF and BGP (with EVPN address-family)
- VXLAN tunnel with L2 and L3 VNIs
- VLANs, SVI interfaces, and access ports
- DHCP servers per VRF

**EdgeConnect EC-V** appliances boot with basic credentials and Orchestrator registration info. Orchestrator preconfigurations are provided in `preconfig/` for import into Orchestrator to complete provisioning (deployment mode, interfaces, OSPF, BGP, VXLAN, overlays, and segments).

**Transport nodes** (internet and MPLS) configure themselves with IP addressing, DHCP (dnsmasq), IP forwarding, and NAT rules.

**Test clients** obtain DHCP addresses from their respective vCX VRF and set a default route via the LAN.

## Prerequisites

### System Requirements

| Requirement | Minimum (single topology) | Full lab (both topologies) | Notes |
|-------------|---------------------------|----------------------------|-------|
| **OS** | Linux (Ubuntu 20.04+, Debian 11+, RHEL 8+) | Same | Native Linux required |
| **CPU** | 8+ cores with virtualization extensions | 16+ cores | Intel VT-x or AMD-V required |
| **RAM** | 40GB+ | 80GB+ | EC-V: 4GB x 3, AOS-CX: 8GB x 3 per topology |
| **Disk** | 50GB free | 100GB free | For Docker images and VM disks |
| **KVM** | Enabled and accessible | Same | Required for running VMs in containers |

### Required Software

1. **KVM/Virtualization Support** - VMs run inside QEMU/KVM
2. **Docker** - Container runtime
3. **ContainerLab** - Network topology orchestration
4. **vrnetlab** - Framework for packaging VMs into container images
5. **sshpass** - Used by the deploy script for SSH config push to AOS-CX

### Required Images (Note: Obtain these from HPE/Aruba)

1. **EdgeConnect EC-V qcow2** - e.g., `ECV-9.6.1.0_106887.qcow2`
2. **AOS-CX vmdk** - e.g., `arubaoscx-disk-image-genericx86-p4-20250822141147.vmdk`

## Installation Guide

### Step 1: Verify KVM Support

```bash
# Check for virtualization extensions
grep -E '(vmx|svm)' /proc/cpuinfo

# Verify /dev/kvm exists
ls -la /dev/kvm

# If missing, load KVM modules
sudo modprobe kvm
sudo modprobe kvm_intel  # or kvm_amd
```

### Step 2: Install Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# Note: Log out and back in
```

### Step 3: Install ContainerLab

```bash
# Quick install script
bash -c "$(curl -sL https://get.containerlab.dev)"
clab version
```

### Step 4: Clone and Set Up vrnetlab

vrnetlab is the framework that packages VMs into container images. You need to clone it and add our custom node types.

```bash
git clone https://github.com/srl-labs/vrnetlab.git
cd vrnetlab
```

### Step 5: Add EdgeConnect (ECOS) Node Type to vrnetlab

The AOS-CX node type already exists in vrnetlab. However, EdgeConnect (ECOS) is a custom node type that must be added manually.

Copy the ECOS docker components from this repository into vrnetlab:

```bash
# From the vrnetlab directory, create the aruba/ecos folder and copy files
# Adjust the path to where you cloned this repo
mkdir -p aruba/ecos/docker
cp /path/to/clab-ecos-aoscx/ecos/Makefile ./aruba/ecos/
cp /path/to/clab-ecos-aoscx/ecos/docker/* ./aruba/ecos/docker/
```

After copying, your vrnetlab directory should contain:
```
vrnetlab/
├── aruba/
│   ├── aoscx/             # Already exists in vrnetlab
│   │   ├── Makefile
│   │   ├── README.md
│   │   └── docker/
│   │       ├── Dockerfile
│   │       └── launch.py
│   └── ecos/              # Added from this repo
│       ├── Makefile
│       └── docker/
│           ├── Dockerfile
│           └── launch.py
├── ... (other vrnetlab node types)
```

### Step 6: Copy Vendor Images into vrnetlab Folders

Place your vendor images (obtained from HPE) into the respective vrnetlab folders:

```bash
# Copy EdgeConnect qcow2 image to the aruba/ecos folder
cp /path/to/ECV-9.6.1.0_106887.qcow2 ./aruba/ecos/

# Copy AOS-CX image to the existing aoscx folder
cp /path/to/arubaoscx-disk-image-genericx86-p4-20250822141147.vmdk ./aruba/aoscx/
```

### Step 7: Build Docker Images

Build from each directory:

**Build EdgeConnect (ECOS):**

```bash
cd aruba/ecos
make docker-image
cd ..
```

**Build AOS-CX:**

```bash
cd aruba/aoscx
make docker-image
cd ..
```

Verify images were created:
```bash
docker images | grep aruba
```

## Quick Start

Once you've built the Docker images (Steps 4-7), return to this repository directory to deploy the lab.

```bash
cd /path/to/clab-ecos-aoscx
```

### 1. Configure Credentials

```bash
cp env.example .env
# Edit with your credentials
vi .env
```

### 2. Update Topology Image Tags

Edit the topology files in `examples/` to match your image versions:

```yaml
# Update these to match your built images
image: vrnetlab/aruba_ecos:9.6.1.0_106887
image: vrnetlab/aruba_arubaos-cx:20250822141147
```

### 3. Install sshpass

The deploy script uses sshpass to push configurations to AOS-CX switches via SSH:

```bash
sudo apt install sshpass
```

### 4. Deploy the Lab

The deploy script handles topology deployment, waits for AOS-CX switches to boot, pushes startup configurations via SSH, and renews DHCP leases on test clients.

```bash
# Source environment variables first
source .env

# Deploy a single topology
./scripts/deploy.sh chi-stl-dfw
./scripts/deploy.sh sea-sfo-las

# Or deploy both topologies
./scripts/deploy.sh all
```

### 5. Monitor Boot Progress

EC-V boots in ~60-90 seconds, AOS-CX takes ~2-3 minutes:

```bash
# Watch all containers
watch docker ps

# Check specific node logs
docker logs -f clab-chi-stl-dfw_ec-cx-DFW-ECV-01
docker logs -f clab-chi-stl-dfw_ec-cx-DFW-vCX-01
```

### 6. Access Your Devices

**CHI-STL-DFW Topology:**

| Node | Type | Web UI | SSH |
|------|------|--------|-----|
| DFW-ECV-01 | EC-V | https://172.30.30.21 | ssh admin@172.30.30.21 |
| STL-ECV-01 | EC-V | https://172.30.30.22 | ssh admin@172.30.30.22 |
| CHI-ECV-01 | EC-V | https://172.30.30.23 | ssh admin@172.30.30.23 |
| DFW-vCX-01 | AOS-CX | https://172.30.30.31 | ssh admin@172.30.30.31 |
| STL-vCX-01 | AOS-CX | https://172.30.30.32 | ssh admin@172.30.30.32 |
| CHI-vCX-01 | AOS-CX | https://172.30.30.33 | ssh admin@172.30.30.33 |
| internet | Linux | N/A | docker exec -it clab-chi-stl-dfw_ec-cx-internet bash |
| mpls | Linux | N/A | docker exec -it clab-chi-stl-dfw_ec-cx-mpls bash |

**SEA-SFO-LAS Topology:**

| Node | Type | Web UI | SSH |
|------|------|--------|-----|
| SEA-ECV-01 | EC-V | https://172.30.30.24 | ssh admin@172.30.30.24 |
| SFO-ECV-01 | EC-V | https://172.30.30.25 | ssh admin@172.30.30.25 |
| LAS-ECV-01 | EC-V | https://172.30.30.26 | ssh admin@172.30.30.26 |
| SEA-vCX-01 | AOS-CX | https://172.30.30.34 | ssh admin@172.30.30.34 |
| SFO-vCX-01 | AOS-CX | https://172.30.30.35 | ssh admin@172.30.30.35 |
| LAS-vCX-01 | AOS-CX | https://172.30.30.36 | ssh admin@172.30.30.36 |
| internet | Linux | N/A | docker exec -it clab-sea-sfo-las_ec-cx-internet bash |
| mpls | Linux | N/A | docker exec -it clab-sea-sfo-las_ec-cx-mpls bash |

Default credentials: `admin` / `admin`

### 7. Tear Down

```bash
# Destroy a single topology
./scripts/destroy.sh chi-stl-dfw
./scripts/destroy.sh sea-sfo-las

# Or destroy both
./scripts/destroy.sh all
```

## Configuration

### Environment Variables

| Variable | Description | Applies To |
|----------|-------------|------------|
| `ECOS_ADMIN_PASSWORD` | Admin password | EC-V |
| `ECOS_REGISTRATION_KEY` | Portal registration key | EC-V |
| `ECOS_ACCOUNT_NAME` | Portal account name | EC-V |
| `ECOS_PORTAL_HOSTNAME` | Portal hostname | EC-V |
| `AOSCX_ADMIN_PASSWORD` | Admin password | AOS-CX |

### AOS-CX Startup Configurations

Each vCX switch has a startup config in `configs/` that is pushed via SSH during deployment. The configurations include:

- **VRFs**: CSN_Managed, CSN_Unmanaged, CSN_Guest with per-VRF route-distinguishers and EVPN route-targets
- **OSPF** (area 0): LAN-facing interface for underlay reachability to EC-V loopbacks
- **BGP** (AS 65001): eBGP multihop peering to EC-V (AS 64001) with L2VPN EVPN address-family
- **VXLAN**: L2 VNIs (1010, 1011, 1012) bridging VLANs across sites, L3 VNIs (10010, 10011, 10012) for inter-VRF routing
- **VLANs and SVIs**: VLAN 1010 (Managed), 1011 (Unmanaged), 1012 (Guest) with /24 subnets
- **Access ports**: 1/1/2 (Managed), 1/1/3 (Unmanaged), 1/1/4 (Guest) for test clients
- **DHCP servers**: Per-VRF pools serving test clients

**Per-site IP addressing:**

| Site | Loopback | LAN (1/1/1) | Managed SVI | Unmanaged SVI | Guest SVI |
|------|----------|-------------|-------------|---------------|-----------|
| DFW | 198.18.1.1/32 | 10.1.0.1/31 | 192.168.10.1/24 | 192.168.11.1/24 | 192.168.12.1/24 |
| STL | 198.18.2.1/32 | 10.2.0.1/31 | 192.168.20.1/24 | 192.168.21.1/24 | 192.168.22.1/24 |
| CHI | 198.18.3.1/32 | 10.3.0.1/31 | 192.168.30.1/24 | 192.168.31.1/24 | 192.168.32.1/24 |
| SEA | 198.18.4.1/32 | 10.4.0.1/31 | 192.168.40.1/24 | 192.168.41.1/24 | 192.168.42.1/24 |
| SFO | 198.18.5.1/32 | 10.5.0.1/31 | 192.168.50.1/24 | 192.168.51.1/24 | 192.168.52.1/24 |
| LAS | 198.18.6.1/32 | 10.6.0.1/31 | 192.168.60.1/24 | 192.168.61.1/24 | 192.168.62.1/24 |

### EdgeConnect Preconfigurations

YAML preconfigurations for each EC-V are in `preconfig/`. These files are formatted for import into Orchestrator to provision the appliances and include:

- Appliance info (hostname, group, site, location)
- Template groups (Default, VXLAN)
- Business intent overlays (RealTime, CriticalApps, BulkApps, DefaultOverlay, CSN_LBO, CSN_SSE)
- Deployment mode (inline-router) with interface definitions (lan0, wan0, wan1)
- OSPF configuration per segment
- BGP configuration (AS 64001) with EVPN peering to vCX (AS 65001)
- Per-segment BGP route-targets for CSN_Managed, CSN_Unmanaged, CSN_Guest
- Segment local routes for internet breakout
- VXLAN configuration (UDP 4789, VTEP source on lo0)

### Transport Nodes

Each topology has two Linux transport nodes simulating WAN circuits:

- **internet**: Provides DHCP (dnsmasq) on 192.168.x.0/24 ranges, NAT via iptables, and IP forwarding
- **mpls**: Provides DHCP (dnsmasq) on 10.100.x.0/24 ranges with IP forwarding

DNSMasq configurations are in `configs/` with separate files per topology to avoid IP conflicts.

### Interface Mapping

**EdgeConnect EC-V:**

| Container Interface | VM Interface | Purpose |
|---------------------|--------------|---------|
| eth0 | mgmt0 | Management (DHCP) |
| eth1 | wan0 | Primary WAN (internet) |
| eth2 | lan0 | Primary LAN (to vCX 1/1/1) |
| eth3 | wan1 | Secondary WAN (MPLS) |
| eth4 | lan1 | Secondary LAN (unused) |
| eth5 | ha | High availability (unused) |

**AOS-CX:**

| Container Interface | VM Interface | Purpose |
|---------------------|--------------|---------|
| eth0 | OOBM | Management |
| eth1 | 1/1/1 | LAN uplink to EC-V |
| eth2 | 1/1/2 | Managed client access (VLAN 1010) |
| eth3 | 1/1/3 | Unmanaged client access (VLAN 1011) |
| eth4 | 1/1/4 | Guest client access (VLAN 1012) |

## Troubleshooting

### Build Issues

```bash
# From the vrnetlab directory, verify vendor images are in the correct folders
ls aruba/ecos/*.qcow2
ls aruba/aoscx/*.vmdk

# Check existing docker images
docker images | grep -E "(aruba_ecos|aruba_arubaos-cx)"

# Rebuild an image (remove old first if needed)
docker rmi vrnetlab/aruba_ecos:<version>
cd aruba/ecos && docker build --build-arg IMAGE=<your-image>.qcow2 -t vrnetlab/aruba_ecos:<version> .
```

### Environment Variables Not Applied

If your EdgeConnect devices show literal variable names (e.g., `$ECOS_ACCOUNT_NAME`) instead of actual values:

```bash
# Destroy the lab
./scripts/destroy.sh all

# Source environment variables
source .env

# Verify variables are set
echo $ECOS_ACCOUNT_NAME

# Redeploy
./scripts/deploy.sh all
```

### AOS-CX Not Booting

AOS-CX requires 8GB RAM per instance. Check available memory and container resource usage:
```bash
free -h
docker stats --no-stream
docker logs clab-chi-stl-dfw_ec-cx-DFW-vCX-01
```

If running on a VM, ensure you have at least 40GB RAM per topology.

### KVM Permission Denied

```bash
sudo usermod -aG kvm $USER
# Log out and back in
```

### Container Health

```bash
# Check health status
docker ps --format "table {{.Names}}\t{{.Status}}"

# Detailed health check
docker inspect --format='{{.State.Health.Status}}' clab-chi-stl-dfw_ec-cx-DFW-ECV-01
```

### EC-Vs Not Showing Up in Orchestrator

If your EdgeConnect appliances are deployed but not appearing in Orchestrator, the environment variables (`ECOS_ACCOUNT_NAME`, `ECOS_REGISTRATION_KEY`) may not have been passed into the containers correctly.

**Verify the environment variables inside a container:**

```bash
# Check a single EC-V container
docker exec clab-chi-stl-dfw_ec-cx-DFW-ECV-01 printenv | grep ECOS

# Check all EC-V containers at once
for ecv in DFW-ECV-01 STL-ECV-01 CHI-ECV-01; do
  echo "=== $ecv ==="
  docker exec clab-chi-stl-dfw_ec-cx-$ecv printenv | grep ECOS
done
```

If the variables are missing or contain literal `$` references, destroy and redeploy with the correct environment:

```bash
./scripts/destroy.sh chi-stl-dfw
source .env
echo $ECOS_ACCOUNT_NAME   # verify it's set
./scripts/deploy.sh chi-stl-dfw
```

### Performance Problems / Tunnels Not Coming Up or Unstable

If tunnels are failing to establish or are flapping, the host may be under resource pressure. Check host resources and container utilization:

```bash
# Check host CPU and memory
free -h
nproc
uptime

# Check resource usage across all lab containers
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | grep clab

# Check for CPU steal or overcommit (high steal% means the host itself is a VM that is overprovisioned)
top -bn1 | head -5

# Check disk I/O which can impact QEMU performance
iostat -x 1 3

# Check for out-of-memory kills
dmesg | grep -i "oom\|killed process" | tail -10
```

Each EC-V requires ~4GB RAM and each AOS-CX requires ~8GB RAM. A single 3-site topology needs approximately 40GB+ total. Running both topologies simultaneously requires 80GB+. If the host is under pressure, consider deploying only one topology at a time.

### Not Sure if EC-Vs Have Actually Booted

The vrnetlab launch script runs QEMU inside each container. You can verify that the VM is running and has completed booting by checking for the QEMU process and looking for the "login prompt detected" message in the container logs:

```bash
# Check if QEMU is running inside each EC-V container
for ecv in DFW-ECV-01 STL-ECV-01 CHI-ECV-01; do
  echo "=== $ecv ==="
  docker exec clab-chi-stl-dfw_ec-cx-$ecv ps aux | grep qemu
done

# Check container logs for the login prompt detection (indicates boot completed)
for ecv in DFW-ECV-01 STL-ECV-01 CHI-ECV-01; do
  echo "=== $ecv ==="
  docker logs clab-chi-stl-dfw_ec-cx-$ecv 2>&1 | grep -i "login prompt"
done

# Follow logs in real time for a specific node to watch boot progress
docker logs -f clab-chi-stl-dfw_ec-cx-DFW-ECV-01
```

If QEMU is not running, check for KVM/permission issues. If QEMU is running but no login prompt is detected, the VM may still be booting or may have failed during startup — check the full logs for errors.

### Config Push Failures

If the deploy script fails to push configs to AOS-CX switches:

```bash
# Verify SSH is reachable
ssh-keyscan 172.30.30.31

# Test SSH manually
sshpass -p admin ssh -o StrictHostKeyChecking=no admin@172.30.30.31

# Check the deploy script output for specific errors
# The script will try the configured AOSCX_ADMIN_PASSWORD first,
# then fall back to the default admin/admin password
```

### Clean Restart

```bash
./scripts/destroy.sh all
docker rm -f $(docker ps -aq --filter name=clab)
source .env
./scripts/deploy.sh all
```

## Directory Structure

```
clab-ecos-aoscx/
├── README.md
├── env.example                              # Environment variable template
├── .gitignore
├── topology.png                             # Network diagram
├── configs/                                 # Device startup configurations
│   ├── CHI-vCX-01.cfg                       # AOS-CX switch configs (6 total)
│   ├── DFW-vCX-01.cfg
│   ├── LAS-vCX-01.cfg
│   ├── SEA-vCX-01.cfg
│   ├── SFO-vCX-01.cfg
│   ├── STL-vCX-01.cfg
│   ├── chi-stl-dfw-internet-dnsmasq.conf    # DNSMasq DHCP configs (4 total)
│   ├── chi-stl-dfw-mpls-dnsmasq.conf
│   ├── sea-sfo-las-internet-dnsmasq.conf
│   └── sea-sfo-las-mpls-dnsmasq.conf
├── ecos/                                    # EdgeConnect custom vrnetlab node type
│   ├── Makefile
│   └── docker/
│       ├── Dockerfile
│       └── launch.py
├── examples/                                # ContainerLab topology definitions
│   ├── CHI-STL-DFW_topology.clab.yml
│   └── SEA-SFO-LAS_topology.clab.yml
├── preconfig/                               # EC-V Orchestrator preconfigurations
│   ├── CHI-ECV-01.yml
│   ├── DFW-ECV-01.yml
│   ├── LAS-ECV-01.yml
│   ├── SEA-ECV-01.yml
│   ├── SFO-ECV-01.yml
│   └── STL-ECV-01.yml
└── scripts/                                 # Deployment automation
    ├── deploy.sh                            # Deploy topology + push configs
    └── destroy.sh                           # Tear down topology
```

## Security Considerations

This lab is designed for **isolated testing and development environments only**. Review these considerations before deployment:

- **Default Credentials**: Devices use `admin`/`admin` by default. Change passwords via environment variables (`ECOS_ADMIN_PASSWORD`, `AOSCX_ADMIN_PASSWORD`) before deployment
- **Credential Storage**: The `.env` file contains sensitive credentials. Ensure it is never committed to version control (included in `.gitignore`)
- **Environment Variables**: Credentials passed via environment variables may be visible in process listings. Use appropriate access controls on the host system
- **Network Isolation**: The management network (172.30.30.0/24) should not be exposed to untrusted networks
- **Console Access**: Initial device configuration is applied via console (telnet to QEMU). This occurs within the container and is not exposed externally
- **SSH Config Push**: The deploy script uses sshpass with `StrictHostKeyChecking=no` for automated config push. This is acceptable in an isolated lab but should not be used in production
- **Lab Environment Only**: This topology is intended for lab, testing, and educational purposes. Do not use default configurations in production environments

## Useful Resources

- **[ContainerLab Documentation](https://containerlab.dev/)** - Full ContainerLab docs
- **[vrnetlab (srl-labs fork)](https://github.com/srl-labs/vrnetlab)** - VM containerization framework
- **[ContainerLab AOS-CX Guide](https://containerlab.dev/manual/kinds/vr-aoscx/)** - AOS-CX specific docs
- **[HPE Aruba EdgeConnect](https://www.arubanetworks.com/products/sd-wan/)** - EdgeConnect product info
- **[HPE Aruba AOS-CX](https://www.arubanetworks.com/products/switches/)** - AOS-CX product info

## License

This project adapts vrnetlab patterns for HPE Aruba network appliances.
EdgeConnect and AOS-CX are products of HPE Aruba Networks.

This software is provided "as-is" without any express or implied warranties. Use at your own risk.
