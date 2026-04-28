#!/bin/bash
# CGW replacement scenario — Phase 1: provision the NEW VPN device via AWS CLI.
# This is the pure-CLI alternative to the terraform/ version — pick one.
#
# Reads required values from the parent Terraform project's outputs.
# Outputs new resource IDs as env-style lines (pipe into `source /dev/stdin`).

set -euo pipefail

PARENT_DIR="${PARENT_DIR:-../..}"

OLD_VPN_EC2=$(terraform -chdir="$PARENT_DIR" output -raw vpn_instance_id)
SUBNET_ID=$(aws ec2 describe-instances --instance-ids "$OLD_VPN_EC2" \
    --query 'Reservations[0].Instances[0].SubnetId' --output text)
SG_ID=$(aws ec2 describe-instances --instance-ids "$OLD_VPN_EC2" \
    --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)
IAM_PROFILE=$(aws ec2 describe-instances --instance-ids "$OLD_VPN_EC2" \
    --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text | awk -F/ '{print $NF}')

AMI=$(aws ec2 describe-images --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
    --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)

# Rendered user_data (reuse parent project's script, inject hostname)
sed "s/\${hostname}/single-vpn-vpn-device-NEW/g" \
    "$PARENT_DIR/scripts/user_data_vpn.sh" > /tmp/ud_new.sh

# ENI with source_dest_check=false
NEW_ENI=$(aws ec2 create-network-interface \
    --subnet-id "$SUBNET_ID" --groups "$SG_ID" \
    --tag-specifications 'ResourceType=network-interface,Tags=[{Key=Name,Value=single-vpn-vpn-eni-NEW}]' \
    --query 'NetworkInterface.NetworkInterfaceId' --output text)
aws ec2 modify-network-interface-attribute \
    --network-interface-id "$NEW_ENI" --source-dest-check "{\"Value\":false}"
NEW_ENI_IP=$(aws ec2 describe-network-interfaces --network-interface-ids "$NEW_ENI" \
    --query 'NetworkInterfaces[0].PrivateIpAddress' --output text)

# EIP
NEW_EIP_ALLOC=$(aws ec2 allocate-address --domain vpc \
    --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=single-vpn-vpn-eip-NEW}]' \
    --query 'AllocationId' --output text)
NEW_EIP=$(aws ec2 describe-addresses --allocation-ids "$NEW_EIP_ALLOC" \
    --query 'Addresses[0].PublicIp' --output text)
aws ec2 associate-address --allocation-id "$NEW_EIP_ALLOC" --network-interface-id "$NEW_ENI" >/dev/null

# EC2 instance
NEW_INST=$(aws ec2 run-instances \
    --image-id "$AMI" --instance-type t3.small \
    --iam-instance-profile "Name=$IAM_PROFILE" \
    --network-interfaces "NetworkInterfaceId=$NEW_ENI,DeviceIndex=0" \
    --user-data file:///tmp/ud_new.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=single-vpn-vpn-device-NEW}]' \
    --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --instance-ids "$NEW_INST"

# New CGW (uses the new EIP as its IP address; ASN must match the old one)
OLD_CGW_ID=$(terraform -chdir="$PARENT_DIR" output -raw customer_gateway_id)
OLD_CGW_ASN=$(aws ec2 describe-customer-gateways --customer-gateway-ids "$OLD_CGW_ID" \
    --query 'CustomerGateways[0].BgpAsn' --output text)
NEW_CGW=$(aws ec2 create-customer-gateway \
    --bgp-asn "$OLD_CGW_ASN" --public-ip "$NEW_EIP" --type ipsec.1 \
    --tag-specifications 'ResourceType=customer-gateway,Tags=[{Key=Name,Value=single-vpn-cgw-NEW}]' \
    --query 'CustomerGateway.CustomerGatewayId' --output text)

cat <<EOF
# --- Provisioning complete. Export these into your shell: ---
export NEW_ENI="$NEW_ENI"
export NEW_ENI_IP="$NEW_ENI_IP"
export NEW_EIP="$NEW_EIP"
export NEW_EIP_ALLOC="$NEW_EIP_ALLOC"
export NEW_INST="$NEW_INST"
export NEW_CGW="$NEW_CGW"
EOF
