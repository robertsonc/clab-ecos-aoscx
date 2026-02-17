#!/usr/bin/env bash
set -euo pipefail

# Generate background ping traffic across SD-WAN topologies
# Creates visible flows in Orchestrator for testing overlay policies

declare -A TOPO_CLAB_PREFIX=(
    [chi-stl-dfw]="clab-chi-stl-dfw_ec-cx"
    [jfk-rdu-mia]="clab-jfk-rdu-mia_ec"
)

# Source containers that originate traffic
declare -A TOPO_SOURCES=(
    [chi-stl-dfw]="CHI-client-managed"
    [jfk-rdu-mia]="JFK-client-managed JFK-client-unmanaged JFK-client-guest"
)

# All client containers (for stop/status)
declare -A TOPO_CLIENTS=(
    [chi-stl-dfw]="DFW-client-managed DFW-client-unmanaged DFW-client-guest STL-client-managed STL-client-unmanaged STL-client-guest CHI-client-managed CHI-client-unmanaged CHI-client-guest"
    [jfk-rdu-mia]="JFK-client-managed JFK-client-unmanaged JFK-client-guest RDU-client-managed RDU-client-unmanaged RDU-client-guest MIA-client-managed MIA-client-unmanaged MIA-client-guest"
)

usage() {
    echo "Usage: $0 <start|stop|status> <chi-stl-dfw|jfk-rdu-mia|all>"
    exit 1
}

# Resolve a container's eth1 DHCP IP
get_eth1_ip() {
    local container=$1
    docker exec "$container" ip -4 addr show eth1 2>/dev/null \
        | awk '/inet / {split($2,a,"/"); print a[1]; exit}'
}

# Launch a background ping from source to target
start_ping() {
    local src_container=$1
    local target=$2
    local label=$3
    docker exec "$src_container" sh -c "ping -i 5 $target > /dev/null 2>&1 &"
    echo "  ${label}: ${target}"
}

start_traffic() {
    local topo=$1
    local prefix="${TOPO_CLAB_PREFIX[$topo]}"

    echo "==> Starting traffic for $topo..."

    # Kill existing pings on source containers first
    for src in ${TOPO_SOURCES[$topo]}; do
        docker exec "${prefix}-${src}" killall ping 2>/dev/null || true
    done

    if [[ "$topo" == "jfk-rdu-mia" ]]; then
        # Resolve destination IPs
        local rdu_managed_ip rdu_unmanaged_ip mia_managed_ip mia_unmanaged_ip
        rdu_managed_ip=$(get_eth1_ip "${prefix}-RDU-client-managed")
        rdu_unmanaged_ip=$(get_eth1_ip "${prefix}-RDU-client-unmanaged")
        mia_managed_ip=$(get_eth1_ip "${prefix}-MIA-client-managed")
        mia_unmanaged_ip=$(get_eth1_ip "${prefix}-MIA-client-unmanaged")

        # Validate all IPs were resolved
        for var_name in rdu_managed mia_managed rdu_unmanaged mia_unmanaged; do
            local ip_var="${var_name}_ip"
            if [[ -z "${!ip_var}" ]]; then
                echo "ERROR: Could not resolve IP for ${var_name}, skipping $topo" >&2
                return 1
            fi
        done

        echo "  Resolved: RDU-managed=$rdu_managed_ip RDU-unmanaged=$rdu_unmanaged_ip"
        echo "  Resolved: MIA-managed=$mia_managed_ip MIA-unmanaged=$mia_unmanaged_ip"

        # JFK-client-managed: internet + cross-site managed
        local jfk_m="${prefix}-JFK-client-managed"
        start_ping "$jfk_m" "8.8.8.8" "JFK-managed → 8.8.8.8"
        start_ping "$jfk_m" "8.8.4.4" "JFK-managed → 8.8.4.4"
        start_ping "$jfk_m" "$rdu_managed_ip" "JFK-managed → RDU-managed"
        start_ping "$jfk_m" "$mia_managed_ip" "JFK-managed → MIA-managed"

        # JFK-client-unmanaged: internet + cross-site to managed
        local jfk_u="${prefix}-JFK-client-unmanaged"
        start_ping "$jfk_u" "4.2.2.1" "JFK-unmanaged → 4.2.2.1"
        start_ping "$jfk_u" "4.2.2.2" "JFK-unmanaged → 4.2.2.2"
        start_ping "$jfk_u" "$rdu_managed_ip" "JFK-unmanaged → RDU-managed"
        start_ping "$jfk_u" "$mia_managed_ip" "JFK-unmanaged → MIA-managed"

        # JFK-client-guest: internet + cross-site to managed + cross-site to unmanaged
        local jfk_g="${prefix}-JFK-client-guest"
        start_ping "$jfk_g" "1.0.0.1" "JFK-guest → 1.0.0.1"
        start_ping "$jfk_g" "1.1.1.1" "JFK-guest → 1.1.1.1"
        start_ping "$jfk_g" "$rdu_managed_ip" "JFK-guest → RDU-managed"
        start_ping "$jfk_g" "$mia_managed_ip" "JFK-guest → MIA-managed"
        start_ping "$jfk_g" "$rdu_unmanaged_ip" "JFK-guest → RDU-unmanaged"
        start_ping "$jfk_g" "$mia_unmanaged_ip" "JFK-guest → MIA-unmanaged"

    elif [[ "$topo" == "chi-stl-dfw" ]]; then
        # Resolve destination IPs
        local dfw_managed_ip stl_managed_ip
        dfw_managed_ip=$(get_eth1_ip "${prefix}-DFW-client-managed")
        stl_managed_ip=$(get_eth1_ip "${prefix}-STL-client-managed")

        for var_name in dfw_managed stl_managed; do
            local ip_var="${var_name}_ip"
            if [[ -z "${!ip_var}" ]]; then
                echo "ERROR: Could not resolve IP for ${var_name}, skipping $topo" >&2
                return 1
            fi
        done

        echo "  Resolved: DFW-managed=$dfw_managed_ip STL-managed=$stl_managed_ip"

        # CHI-client-managed: cross-site managed
        local chi_m="${prefix}-CHI-client-managed"
        start_ping "$chi_m" "$dfw_managed_ip" "CHI-managed → DFW-managed"
        start_ping "$chi_m" "$stl_managed_ip" "CHI-managed → STL-managed"
    fi
}

stop_traffic() {
    local topo=$1
    local prefix="${TOPO_CLAB_PREFIX[$topo]}"

    echo "==> Stopping traffic for $topo..."
    for client in ${TOPO_SOURCES[$topo]}; do
        local container="${prefix}-${client}"
        if docker exec "$container" killall ping 2>/dev/null; then
            echo "  $client: stopped"
        else
            echo "  $client: no pings running"
        fi
    done
}

show_status() {
    local topo=$1
    local prefix="${TOPO_CLAB_PREFIX[$topo]}"

    echo "==> Traffic status for $topo:"
    for client in ${TOPO_SOURCES[$topo]}; do
        local container="${prefix}-${client}"
        local pings
        pings=$(docker exec "$container" sh -c "ps -o args 2>/dev/null | grep '^ping' || true")
        if [[ -n "$pings" ]]; then
            local count
            count=$(echo "$pings" | wc -l)
            echo "  $client: ${count} flow(s)"
            echo "$pings" | while read -r line; do
                echo "    $line"
            done
        else
            echo "  $client: no pings running"
        fi
    done
}

# --- Main ---

if [ $# -ne 2 ]; then
    usage
fi

ACTION="${1,,}"
ARG="${2,,}"

if [[ "$ACTION" != "start" && "$ACTION" != "stop" && "$ACTION" != "status" ]]; then
    usage
fi

if [[ "$ARG" != "chi-stl-dfw" && "$ARG" != "jfk-rdu-mia" && "$ARG" != "all" ]]; then
    usage
fi

if [ "$ARG" = "all" ]; then
    TOPOS=("chi-stl-dfw" "jfk-rdu-mia")
else
    TOPOS=("$ARG")
fi

for topo in "${TOPOS[@]}"; do
    case "$ACTION" in
        start)  start_traffic "$topo" ;;
        stop)   stop_traffic "$topo" ;;
        status) show_status "$topo" ;;
    esac
done

echo "==> Done."
