#!/bin/bash
# Configure strongSwan for 2 IPsec tunnels + static routing to AWS VPC.
# No BGP — routing is static based on the `rightsubnet` in each conn.
#
# Arguments (positional):
#   $1  LOCAL_IP              Private IP of this VPN device ENI
#   $2  ONPREM_CIDR           Local private network CIDR (for leftsubnet)
#   $3  VPC_CIDR              AWS VPC CIDR (for rightsubnet)
#   $4  TUNNEL1_PUBLIC_IP     AWS-side public IP for tunnel 1
#   $5  TUNNEL2_PUBLIC_IP     AWS-side public IP for tunnel 2
#   $6  TUNNEL1_PSK           Pre-shared key for tunnel 1
#   $7  TUNNEL2_PSK           Pre-shared key for tunnel 2

set -euo pipefail

LOCAL_IP="$1"
ONPREM_CIDR="$2"
VPC_CIDR="$3"
T1_PUB="$4"
T2_PUB="$5"
T1_PSK="$6"
T2_PSK="$7"

echo "=== strongSwan VPN configuration ==="
echo "Local IP       : $LOCAL_IP"
echo "OnPrem CIDR    : $ONPREM_CIDR (advertised as leftsubnet)"
echo "VPC CIDR       : $VPC_CIDR (rightsubnet)"
echo "Tunnel 1 peer  : $T1_PUB"
echo "Tunnel 2 peer  : $T2_PUB"

# --- Preconditions ---
# Ensure IP forwarding is on. user_data sets this, but re-assert here in case
# a stale VPN device was booted with an older sysctl file.
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0

# Add a route to the on-premise private subnet via the VPC's default gateway.
# Reason: traffic arriving from AWS through the IPsec tunnel is decrypted with
# inner dst = <onprem_cidr ip>, but the VPN device only knows about its own
# /24. Without this route, the decrypted packet is dropped before reaching
# the onprem subnet. The "onmetric 50" is lower than DHCP default (100) so
# it wins against the default route.
LOCAL_GW="$(ip route | awk '/^default/ {print $3; exit}')"
if [ -n "$LOCAL_GW" ] && ! ip route show "$ONPREM_CIDR" | grep -q "$LOCAL_GW"; then
    ip route replace "$ONPREM_CIDR" via "$LOCAL_GW" metric 50
fi
# Persist the route across reboots via a systemd-networkd drop-in. Ubuntu's
# netplan overwrites /etc/network/interfaces, so we use a simple oneshot unit.
cat > /etc/systemd/system/vpn-onprem-route.service <<EOF
[Unit]
Description=Add static route to on-premise private subnet
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/ip route replace $ONPREM_CIDR via $LOCAL_GW metric 50
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now vpn-onprem-route.service

# --- strongSwan main configuration ---
# Uses classic ipsec.conf format. We replace the default to avoid interference.
cat > /etc/ipsec.conf <<EOF
# AWS Site-to-Site VPN — managed by configure_ipsec.sh
# Do not edit manually; re-run the SSM association to regenerate.

config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn %default
    type=tunnel
    authby=secret
    keyexchange=ikev1
    # AWS default proposals: AES128 / SHA1 / DH2 for Phase 1 and Phase 2
    ike=aes128-sha1-modp1024!
    esp=aes128-sha1-modp1024!
    ikelifetime=28800s
    lifetime=3600s
    margintime=540s
    keyingtries=%forever
    # DPD — detect dead peer, restart on loss (enables tunnel auto-recovery)
    dpddelay=10s
    dpdtimeout=30s
    dpdaction=restart
    # Left = this on-prem VPN device; right = AWS VPN endpoint
    left=%defaultroute
    leftid=$LOCAL_IP
    leftsubnet=$ONPREM_CIDR
    rightsubnet=$VPC_CIDR

conn AWS-Tunnel-1
    right=$T1_PUB
    auto=start

conn AWS-Tunnel-2
    right=$T2_PUB
    auto=start
EOF

# --- Pre-shared keys ---
cat > /etc/ipsec.secrets <<EOF
# Per-tunnel PSK. %any = accept any local ID (we set leftid in conn)
$LOCAL_IP $T1_PUB : PSK "$T1_PSK"
$LOCAL_IP $T2_PUB : PSK "$T2_PSK"
EOF
chmod 600 /etc/ipsec.secrets

# --- Restart strongSwan so it picks up the new configuration ---
# `ipsec restart` flushes stale SAs and triggers fresh IKE negotiation, which
# avoids a case where AWS VGW has an SA from a previous CGW instance with
# mismatched SPIs (symptom: tunnel is UP but 0 bytes flow through).
systemctl restart strongswan-starter
sleep 3
ipsec restart || systemctl restart strongswan-starter
sleep 10

echo "=== IPsec status ==="
ipsec status || true

echo "=== IPsec statusall (detail) ==="
ipsec statusall 2>&1 | head -50 || true

echo "strongSwan configuration completed"
