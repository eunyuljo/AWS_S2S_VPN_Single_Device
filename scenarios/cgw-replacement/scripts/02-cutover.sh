#!/bin/bash
# CGW replacement scenario — Phase 3: switch the VPN Connection to the NEW CGW.
# Requires NEW_CGW and the parent project outputs.

set -euo pipefail

PARENT_DIR="${PARENT_DIR:-../..}"
: "${NEW_CGW:?Run 01-provision-new-device.sh first and export NEW_CGW}"

OLD_VPN_CONN_ID=$(terraform -chdir="$PARENT_DIR" output -raw vpn_connection_id)

echo "==> Modifying VPN Connection $OLD_VPN_CONN_ID to use CGW $NEW_CGW"
aws ec2 modify-vpn-connection \
    --vpn-connection-id "$OLD_VPN_CONN_ID" \
    --customer-gateway-id "$NEW_CGW" >/dev/null

echo "==> Waiting for state 'available' (this may take 3-5 minutes)..."
while true; do
    STATE=$(aws ec2 describe-vpn-connections --vpn-connection-ids "$OLD_VPN_CONN_ID" \
        --query 'VpnConnections[0].State' --output text)
    echo "  $(date +%H:%M:%S) state=$STATE"
    [ "$STATE" = "available" ] && break
    sleep 15
done

echo ""
echo "==> Fetching (possibly rotated) tunnel options:"
aws ec2 describe-vpn-connections --vpn-connection-ids "$OLD_VPN_CONN_ID" \
    --query 'VpnConnections[0].Options.TunnelOptions[].[OutsideIpAddress,PreSharedKey]' \
    --output text

echo ""
echo "Next step: run the configure_ipsec.sh on the NEW device with these values."
echo "   aws ssm start-session --target \$NEW_INST"
