#!/bin/bash
# CGW replacement scenario — rollback everything to the original state and
# delete the NEW-side resources so `terraform plan` on the parent is clean.

set -euo pipefail

PARENT_DIR="${PARENT_DIR:-../..}"

OLD_VPN_CONN_ID=$(terraform -chdir="$PARENT_DIR" output -raw vpn_connection_id)
OLD_CGW_ID=$(terraform -chdir="$PARENT_DIR" output -raw customer_gateway_id)
OLD_ENI_ID=$(aws ec2 describe-instances \
    --instance-ids "$(terraform -chdir=$PARENT_DIR output -raw vpn_instance_id)" \
    --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' --output text)

ONPREM_VPC_ID=$(terraform -chdir="$PARENT_DIR" output -raw onprem_vpc_id)
ONPREM_RT=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$ONPREM_VPC_ID" \
              "Name=tag:Name,Values=*onprem-private-rt*" \
    --query 'RouteTables[0].RouteTableId' --output text)

echo "==> 1/4 Restoring original CGW on VPN Connection"
aws ec2 modify-vpn-connection \
    --vpn-connection-id "$OLD_VPN_CONN_ID" --customer-gateway-id "$OLD_CGW_ID" >/dev/null
while [ "$(aws ec2 describe-vpn-connections --vpn-connection-ids $OLD_VPN_CONN_ID \
    --query 'VpnConnections[0].State' --output text)" != "available" ]; do
    echo "  waiting for VPN Connection..."
    sleep 15
done

echo "==> 2/4 Restoring original on-premise route"
aws ec2 replace-route --route-table-id "$ONPREM_RT" \
    --destination-cidr-block 10.0.0.0/16 --network-interface-id "$OLD_ENI_ID"

echo "==> 3/4 Restarting strongSwan on the original VPN device (PSK may have rotated)"
OLD_INST=$(terraform -chdir="$PARENT_DIR" output -raw vpn_instance_id)
SSM_ASSOC_ID=$(terraform -chdir="$PARENT_DIR" output -raw ssm_association_id)
aws ssm start-associations-once --association-ids "$SSM_ASSOC_ID"

echo "==> 4/4 Deleting NEW-side resources"
if [ -n "${NEW_INST:-}" ]; then
    aws ec2 terminate-instances --instance-ids "$NEW_INST" >/dev/null
    aws ec2 wait instance-terminated --instance-ids "$NEW_INST"
fi
if [ -n "${NEW_CGW:-}" ]; then
    aws ec2 delete-customer-gateway --customer-gateway-id "$NEW_CGW"
fi
if [ -n "${NEW_EIP_ALLOC:-}" ]; then
    aws ec2 release-address --allocation-id "$NEW_EIP_ALLOC" || true
fi
if [ -n "${NEW_ENI:-}" ]; then
    aws ec2 delete-network-interface --network-interface-id "$NEW_ENI" || true
fi

echo ""
echo "==> Done. Run 'terraform plan' in the parent project — drift should be empty."
