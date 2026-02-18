#!/usr/bin/env bash
set -euo pipefail

# Renew DHCP leases on test clients
# Kills any existing udhcpc process before requesting a fresh lease

declare -A TOPO_CLAB_PREFIX=(
    [chi-stl-dfw]="clab-chi-stl-dfw_ec-cx"
    [sea-sfo-las]="clab-sea-sfo-las_ec-cx"
    [jfk-rdu-mia]="clab-jfk-rdu-mia_ec"
)

declare -A TOPO_CLIENTS=(
    [chi-stl-dfw]="DFW-client-managed DFW-client-unmanaged DFW-client-guest STL-client-managed STL-client-unmanaged STL-client-guest CHI-client-managed CHI-client-unmanaged CHI-client-guest"
    [sea-sfo-las]="SEA-client-managed SEA-client-unmanaged SEA-client-guest SFO-client-managed SFO-client-unmanaged SFO-client-guest LAS-client-managed LAS-client-unmanaged LAS-client-guest"
    [jfk-rdu-mia]="JFK-client-managed JFK-client-unmanaged JFK-client-guest RDU-client-managed RDU-client-unmanaged RDU-client-guest MIA-client-managed MIA-client-unmanaged MIA-client-guest"
)

usage() {
    echo "Usage: $0 <chi-stl-dfw|sea-sfo-las|jfk-rdu-mia|all>"
    exit 1
}

renew_dhcp() {
    local topo=$1
    local prefix="${TOPO_CLAB_PREFIX[$topo]}"
    local clients="${TOPO_CLIENTS[$topo]}"

    echo "==> Renewing DHCP leases for $topo..."
    for client in $clients; do
        local container="${prefix}-${client}"
        if docker exec "$container" sh -c \
            "killall dhclient 2>/dev/null; sleep 1; dhclient eth1 2>/dev/null; sleep 3; ip route del default dev eth0 2>/dev/null" \
            &>/dev/null; then
            echo "  $client: OK"
        else
            echo "ERROR: $client: DHCP failed" >&2
        fi
    done
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
    renew_dhcp "$topo"
done

echo "==> Done."
