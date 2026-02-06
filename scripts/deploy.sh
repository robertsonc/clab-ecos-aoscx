#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Topology → switch mappings ──────────────────────────────────────
declare -A TOPO_FILES=(
    [chi-stl-dfw]="examples/CHI-STL-DFW_topology.clab.yml"
    [sea-sfo-las]="examples/SEA-SFO-LAS_topology.clab.yml"
)

# Each topology's switches: "name:ip:config ..."
declare -A TOPO_SWITCHES=(
    [chi-stl-dfw]="DFW-vCX-01:172.30.30.31:configs/DFW-vCX-01.cfg STL-vCX-01:172.30.30.32:configs/STL-vCX-01.cfg CHI-vCX-01:172.30.30.33:configs/CHI-vCX-01.cfg"
    [sea-sfo-las]="SEA-vCX-01:172.30.30.34:configs/SEA-vCX-01.cfg SFO-vCX-01:172.30.30.35:configs/SFO-vCX-01.cfg LAS-vCX-01:172.30.30.36:configs/LAS-vCX-01.cfg"
)

# Clab container prefix per topology
declare -A TOPO_CLAB_PREFIX=(
    [chi-stl-dfw]="clab-chi-stl-dfw_ec-cx"
    [sea-sfo-las]="clab-sea-sfo-las_ec-cx"
)

# Each topology's test clients (container node names)
declare -A TOPO_CLIENTS=(
    [chi-stl-dfw]="DFW-client-managed DFW-client-unmanaged DFW-client-guest STL-client-managed STL-client-unmanaged STL-client-guest CHI-client-managed CHI-client-unmanaged CHI-client-guest"
    [sea-sfo-las]="SEA-client-managed SEA-client-unmanaged SEA-client-guest SFO-client-managed SFO-client-unmanaged SFO-client-guest LAS-client-managed LAS-client-unmanaged LAS-client-guest"
)

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"
SSH_TIMEOUT=300  # 5 minutes
SSH_POLL=10      # poll interval in seconds

# ── Helpers ─────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 <chi-stl-dfw|sea-sfo-las|all>"
    exit 1
}

log() { echo "==> $*"; }
err() { echo "ERROR: $*" >&2; }

wait_for_ssh() {
    local host=$1 name=$2
    local elapsed=0
    log "Waiting for SSH on $name ($host)..."
    while ! nc -z -w2 "$host" 22 &>/dev/null; do
        sleep "$SSH_POLL"
        elapsed=$((elapsed + SSH_POLL))
        if [ "$elapsed" -ge "$SSH_TIMEOUT" ]; then
            err "Timed out waiting for SSH on $name ($host) after ${SSH_TIMEOUT}s"
            return 1
        fi
    done
    log "SSH reachable on $name ($host) after ~${elapsed}s"
}

push_config() {
    local name=$1 host=$2 cfg=$3
    local cfg_path="$REPO_ROOT/$cfg"

    if [ ! -f "$cfg_path" ]; then
        err "Config file not found: $cfg_path"
        return 1
    fi

    log "Pushing config to $name ($host) from $cfg..."
    export SSHPASS="$AOSCX_ADMIN_PASSWORD"
    { echo "configure terminal"; cat "$cfg_path"; echo "end"; echo "write memory"; } | \
        sshpass -e ssh $SSH_OPTS admin@"$host" 2>/dev/null
    log "Config applied to $name"
}

renew_client_dhcp() {
    local topo=$1
    local prefix="${TOPO_CLAB_PREFIX[$topo]}"
    local clients="${TOPO_CLIENTS[$topo]}"

    log "Renewing DHCP leases on test clients..."
    for client in $clients; do
        local container="${prefix}-${client}"
        if docker exec "$container" sh -c "udhcpc -i eth1 -n -q && ip route del default dev eth0 2>/dev/null" &>/dev/null; then
            log "  $client: DHCP OK, default route via eth1"
        else
            err "  $client: DHCP failed"
        fi
    done
}

deploy_topology() {
    local topo=$1
    local topo_file="${TOPO_FILES[$topo]}"
    local topo_path="$REPO_ROOT/$topo_file"

    if [ ! -f "$topo_path" ]; then
        err "Topology file not found: $topo_path"
        return 1
    fi

    log "Deploying topology: $topo_file"
    sudo -E clab deploy -t "$topo_path"
    log "Topology deployed successfully"

    log "Waiting for vCX switches to boot and pushing configs..."
    local switches="${TOPO_SWITCHES[$topo]}"
    for entry in $switches; do
        IFS=: read -r name ip cfg <<< "$entry"
        wait_for_ssh "$ip" "$name"
        # Brief pause after SSH is reachable to let the CLI fully initialize
        sleep 5
        push_config "$name" "$ip" "$cfg"
    done

    renew_client_dhcp "$topo"
}

# ── Preflight checks ───────────────────────────────────────────────
if [ $# -ne 1 ]; then
    usage
fi

ARG="${1,,}"  # lowercase

if [[ "$ARG" != "chi-stl-dfw" && "$ARG" != "sea-sfo-las" && "$ARG" != "all" ]]; then
    usage
fi

# Source .env if present
if [ -f "$REPO_ROOT/.env" ]; then
    # shellcheck disable=SC1091
    source "$REPO_ROOT/.env"
fi

if ! command -v sshpass &>/dev/null; then
    err "sshpass is required but not installed."
    echo "  Install with: sudo apt install sshpass"
    exit 1
fi

if [ -z "${AOSCX_ADMIN_PASSWORD:-}" ]; then
    err "AOSCX_ADMIN_PASSWORD is not set."
    echo "  Set it in .env or export it before running this script."
    exit 1
fi

# ── Main ────────────────────────────────────────────────────────────
if [ "$ARG" = "all" ]; then
    TOPOS=("chi-stl-dfw" "sea-sfo-las")
else
    TOPOS=("$ARG")
fi

for topo in "${TOPOS[@]}"; do
    deploy_topology "$topo"
    echo
done

log "Done. All topologies deployed and vCX configs applied."
