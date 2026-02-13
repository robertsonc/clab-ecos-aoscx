#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Topology files ──────────────────────────────────────────────────
declare -A TOPO_FILES=(
    [chi-stl-dfw]="examples/CHI-STL-DFW_topology.clab.yml"
    [sea-sfo-las]="examples/SEA-SFO-LAS_topology.clab.yml"
    [jfk-rdu-mia]="examples/JFK-RDU-MIA_topology.clab.yml"
)

# ── Helpers ─────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 <chi-stl-dfw|sea-sfo-las|jfk-rdu-mia|all>"
    exit 1
}

log() { echo "==> $*"; }
err() { echo "ERROR: $*" >&2; }

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
    log "Topology destroyed: $topo"
}

# ── Main ────────────────────────────────────────────────────────────
if [ $# -ne 1 ]; then
    usage
fi

ARG="${1,,}"  # lowercase

if [[ "$ARG" != "chi-stl-dfw" && "$ARG" != "sea-sfo-las" && "$ARG" != "jfk-rdu-mia" && "$ARG" != "all" ]]; then
    usage
fi

if [ "$ARG" = "all" ]; then
    TOPOS=("chi-stl-dfw" "sea-sfo-las" "jfk-rdu-mia")
else
    TOPOS=("$ARG")
fi

for topo in "${TOPOS[@]}"; do
    destroy_topology "$topo"
    echo
done

log "Done."
