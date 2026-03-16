#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Topology files ──────────────────────────────────────────────────
declare -A TOPO_FILES=(
    [chi-stl-dfw]="examples/CHI-STL-DFW_topology.clab.yml"
    [sea-sfo-lax]="examples/SEA-SFO-LAX_topology.clab.yml"
    [jfk-rdu-mia]="examples/JFK-RDU-MIA_topology.clab.yml"
    [chi-atl-phx]="examples/CHI-ATL-PHX_topology.clab.yml"
    [phl-iah-den]="examples/PHL-IAH-DEN_topology.clab.yml"
)

# Management IPs per topology (transport, EC-V, vCX)
declare -A TOPO_MGMT_IPS=(
    [chi-stl-dfw]="172.30.30.10 172.30.30.11 172.30.30.21 172.30.30.22 172.30.30.23 172.30.30.31 172.30.30.32 172.30.30.33"
    [sea-sfo-lax]="172.30.30.12 172.30.30.13 172.30.30.24 172.30.30.25 172.30.30.26 172.30.30.34 172.30.30.35 172.30.30.36"
    [jfk-rdu-mia]="172.30.30.14 172.30.30.15 172.30.30.27 172.30.30.28 172.30.30.29"
    [chi-atl-phx]="172.30.30.16 172.30.30.17 172.30.30.40 172.30.30.41 172.30.30.42"
    [phl-iah-den]="172.30.30.18 172.30.30.19 172.30.30.43 172.30.30.44 172.30.30.45"
)

# ── Helpers ─────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 <chi-stl-dfw|sea-sfo-lax|jfk-rdu-mia|chi-atl-phx|phl-iah-den|all>"
    exit 1
}

log() { echo "==> $*"; }
err() { echo "ERROR: $*" >&2; }

clean_known_hosts() {
    local topo=$1
    local ips="${TOPO_MGMT_IPS[$topo]}"
    local known_hosts="$HOME/.ssh/known_hosts"
    [ -f "$known_hosts" ] || return 0
    log "Removing stale SSH host keys for $topo..."
    for ip in $ips; do
        ssh-keygen -f "$known_hosts" -R "$ip" &>/dev/null
    done
}

destroy_topology() {
    local topo=$1
    local topo_file="${TOPO_FILES[$topo]}"
    local topo_path="$REPO_ROOT/$topo_file"

    if [ ! -f "$topo_path" ]; then
        err "Topology file not found: $topo_path"
        return 1
    fi

    log "Destroying topology: $topo_file"
    sudo clab destroy -t "$topo_path" --cleanup
    clean_known_hosts "$topo"
    log "Topology destroyed: $topo"
}

# ── Main ────────────────────────────────────────────────────────────
if [ $# -ne 1 ]; then
    usage
fi

ARG="${1,,}"  # lowercase

if [[ "$ARG" != "chi-stl-dfw" && "$ARG" != "sea-sfo-lax" && "$ARG" != "jfk-rdu-mia" && "$ARG" != "chi-atl-phx" && "$ARG" != "phl-iah-den" && "$ARG" != "all" ]]; then
    usage
fi

if [ "$ARG" = "all" ]; then
    TOPOS=("chi-stl-dfw" "sea-sfo-lax" "jfk-rdu-mia" "chi-atl-phx" "phl-iah-den")
else
    TOPOS=("$ARG")
fi

for topo in "${TOPOS[@]}"; do
    destroy_topology "$topo"
    echo
done

log "Done."
