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
# Use: docker ps --format '{{.Names}}' | grep -i internet
# or:  sudo clab inspect -t <your-topo.yml>
CONTAINER_LAB1_INTERNET=" clab-chi-stl-dfw_ec-cx-internet"
CONTAINER_LAB1_MPLS=" clab-chi-stl-dfw_ec-cx-mpls"
CONTAINER_LAB2_INTERNET="clab-sea-sfo-las_ec-cx-internet"
CONTAINER_LAB2_MPLS="clab-sea-sfo-las_ec-cx-mpls"

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

deploy_host "$CONTAINER_LAB1_INTERNET" "lab1-internet" "Lab1 Internet (172.30.30.10 / AS65010)"
deploy_host "$CONTAINER_LAB1_MPLS"     "lab1-mpls"     "Lab1 MPLS (172.30.30.11 / AS65011)"
deploy_host "$CONTAINER_LAB2_INTERNET" "lab2-internet" "Lab2 Internet (172.30.30.12 / AS65012)"
deploy_host "$CONTAINER_LAB2_MPLS"     "lab2-mpls"     "Lab2 MPLS (172.30.30.13 / AS65013)"

echo ""
echo "======================================================"
echo "  All hosts deployed. BGP sessions should come up"
echo "  within ~30 seconds. Verify with:"
echo ""
echo "  docker exec $CONTAINER_LAB1_INTERNET vtysh -c 'show bgp summary'"
echo "  docker exec $CONTAINER_LAB1_INTERNET vtysh -c 'show ip route bgp'"
echo "======================================================"
