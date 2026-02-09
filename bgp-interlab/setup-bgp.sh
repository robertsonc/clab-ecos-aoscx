#!/bin/bash
# ============================================================
#  setup-bgp.sh — Install FRR and apply BGP config on a
#  network-multitool container for inter-lab peering
#
#  Usage (from the containerlab host):
#    docker exec clab-<topo>-<node> /bin/bash /tmp/bgp/setup-bgp.sh
#
#  Assumes the frr.conf and daemons files are bind-mounted
#  into the container at /tmp/bgp/
# ============================================================

set -euo pipefail

FRR_CONF="/tmp/bgp/frr.conf"
DAEMONS="/tmp/bgp/daemons"

echo ">>> Installing FRR..."
apk update -q
apk add -q frr

echo ">>> Copying daemons file..."
cp "$DAEMONS" /etc/frr/daemons

echo ">>> Copying FRR config..."
cp "$FRR_CONF" /etc/frr/frr.conf

echo ">>> Setting ownership..."
chown -R frr:frr /etc/frr/

echo ">>> Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null

echo ">>> Starting FRR..."
/usr/lib/frr/frrinit.sh start

echo ">>> FRR is running. Verifying BGP..."
sleep 2
vtysh -c "show bgp summary"
echo ""
echo ">>> Done. Use 'vtysh' inside the container for CLI access."
