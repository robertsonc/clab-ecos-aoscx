#!/bin/bash
# ============================================================
#  deploy-all.sh — Deploy BGP peering to all four WAN hosts
#
#  Edit the CONTAINER_* variables below to match your actual
#  containerlab container names (docker ps to check)
#
#  This script copies the right config into each container
#  and runs the setup script.
# ============================================================

set -euo pipefail

# ---- EDIT THESE to match your container names ----
# Use: docker ps --format '{{.Names}}' | grep -i isp
# or:  sudo clab inspect -t <your-topo.yml>
CONTAINER_LAB1_ISP_A="clab-chi-stl-dfw_ec-cx-isp-a"
CONTAINER_LAB1_ISP_B="clab-chi-stl-dfw_ec-cx-isp-b"
CONTAINER_LAB2_ISP_A="clab-sea-sfo-las_ec-cx-isp-a"
CONTAINER_LAB2_ISP_B="clab-sea-sfo-las_ec-cx-isp-b"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

deploy_host() {
    local CONTAINER="$1"
    local HOST_DIR="$2"
    local HOST_LABEL="$3"

    echo ""
    echo "======================================================"
    echo "  Deploying BGP on: $HOST_LABEL ($CONTAINER)"
    echo "======================================================"

    # Create target dir in container
    docker exec "$CONTAINER" mkdir -p /tmp/bgp

    # Copy files into container
    docker cp "$SCRIPT_DIR/$HOST_DIR/frr.conf"  "$CONTAINER:/tmp/bgp/frr.conf"
    docker cp "$SCRIPT_DIR/daemons"              "$CONTAINER:/tmp/bgp/daemons"
    docker cp "$SCRIPT_DIR/setup-bgp.sh"         "$CONTAINER:/tmp/bgp/setup-bgp.sh"

    # Run setup
    docker exec "$CONTAINER" chmod +x /tmp/bgp/setup-bgp.sh
    docker exec "$CONTAINER" /bin/bash /tmp/bgp/setup-bgp.sh

    echo "  ✓ $HOST_LABEL complete"
}

deploy_host "$CONTAINER_LAB1_ISP_A" "lab1-isp-a" "Lab1 ISP-A (172.30.30.10 / AS65010)"
deploy_host "$CONTAINER_LAB1_ISP_B" "lab1-isp-b" "Lab1 ISP-B (172.30.30.11 / AS65011)"
deploy_host "$CONTAINER_LAB2_ISP_A" "lab2-isp-a" "Lab2 ISP-A (172.30.30.12 / AS65012)"
deploy_host "$CONTAINER_LAB2_ISP_B" "lab2-isp-b" "Lab2 ISP-B (172.30.30.13 / AS65013)"

echo ""
echo "======================================================"
echo "  All hosts deployed. BGP sessions should come up"
echo "  within ~30 seconds. Verify with:"
echo ""
echo "  docker exec $CONTAINER_LAB1_ISP_A vtysh -c 'show bgp summary'"
echo "  docker exec $CONTAINER_LAB1_ISP_A vtysh -c 'show ip route bgp'"
echo "======================================================"
