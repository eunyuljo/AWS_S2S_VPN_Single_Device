#!/bin/bash
# CGW replacement scenario — Phase 5: point the on-premise private route table
# at the NEW VPN device's ENI.

set -euo pipefail

PARENT_DIR="${PARENT_DIR:-../..}"
: "${NEW_ENI:?Run 01-provision-new-device.sh first and export NEW_ENI}"

# Discover the on-premise private route table (not exposed as a parent output,
# so we look it up by tag).
ONPREM_VPC_ID=$(terraform -chdir="$PARENT_DIR" output -raw onprem_vpc_id)
ONPREM_RT=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$ONPREM_VPC_ID" \
              "Name=tag:Name,Values=*onprem-private-rt*" \
    --query 'RouteTables[0].RouteTableId' --output text)

echo "==> Replacing route 10.0.0.0/16 in $ONPREM_RT to point at $NEW_ENI"
aws ec2 replace-route \
    --route-table-id "$ONPREM_RT" \
    --destination-cidr-block 10.0.0.0/16 \
    --network-interface-id "$NEW_ENI"

echo "==> Verifying:"
aws ec2 describe-route-tables --route-table-ids "$ONPREM_RT" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`10.0.0.0/16`].[NetworkInterfaceId,State]' \
    --output table
