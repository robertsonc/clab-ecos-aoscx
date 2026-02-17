#!/bin/bash
# ============================================================
#  deploy-all.sh — Deploy inter-lab BGP peering to ISP sim hosts
#
#  Usage: ./deploy-all.sh <chi-stl-dfw|sea-sfo-las|jfk-rdu-mia|all>
#
#  This script copies the right FRR config into each ISP
#  container and runs the setup script.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Topology → container prefix and lab number mapping
declare -A TOPO_PREFIX=(
    [chi-stl-dfw]="clab-chi-stl-dfw_ec-cx"
    [sea-sfo-las]="clab-sea-sfo-las_ec-cx"
    [jfk-rdu-mia]="clab-jfk-rdu-mia_ec"
)

declare -A TOPO_LAB=(
    [chi-stl-dfw]="lab1"
    [sea-sfo-las]="lab2"
    [jfk-rdu-mia]="lab3"
)

declare -A TOPO_ISP_A_INFO=(
    [chi-stl-dfw]="Lab1 ISP-A (172.30.30.10 / AS65010)"
    [sea-sfo-las]="Lab2 ISP-A (172.30.30.12 / AS65012)"
    [jfk-rdu-mia]="Lab3 ISP-A (172.30.30.14 / AS65014)"
)

declare -A TOPO_ISP_B_INFO=(
    [chi-stl-dfw]="Lab1 ISP-B (172.30.30.11 / AS65011)"
    [sea-sfo-las]="Lab2 ISP-B (172.30.30.13 / AS65013)"
    [jfk-rdu-mia]="Lab3 ISP-B (172.30.30.15 / AS65015)"
)

usage() {
    echo "Usage: $0 <chi-stl-dfw|sea-sfo-las|jfk-rdu-mia|all>"
    exit 1
}

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

deploy_topo() {
    local topo=$1
    local prefix="${TOPO_PREFIX[$topo]}"
    local lab="${TOPO_LAB[$topo]}"

    deploy_host "${prefix}-isp-a" "${lab}-isp-a" "${TOPO_ISP_A_INFO[$topo]}"
    deploy_host "${prefix}-isp-b" "${lab}-isp-b" "${TOPO_ISP_B_INFO[$topo]}"
}

if [ $# -ne 1 ]; then
    usage
fi

ARG="${1,,}"

if [[ "$ARG" != "chi-stl-dfw" && "$ARG" != "sea-sfo-las" && "$ARG" != "jfk-rdu-mia" && "$ARG" != "all" ]]; then
    usage
fi

if [ "$ARG" = "all" ]; then
    TOPOS=("chi-stl-dfw" "sea-sfo-las" "jfk-rdu-mia")
else
    TOPOS=("$ARG")
fi

for topo in "${TOPOS[@]}"; do
    deploy_topo "$topo"
done

echo ""
echo "======================================================"
echo "  Deployed BGP to: ${TOPOS[*]}"
echo "  Sessions should come up within ~30 seconds."
echo ""
echo "  Verify with:"
for topo in "${TOPOS[@]}"; do
    local_prefix="${TOPO_PREFIX[$topo]}"
    echo "    docker exec ${local_prefix}-isp-a vtysh -c 'show bgp summary'"
done
echo "======================================================"
