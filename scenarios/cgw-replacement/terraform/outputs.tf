output "new_vpn_instance_id" {
  value       = aws_instance.new_vpn.id
  description = "Instance ID of the NEW VPN device (for SSM access)"
}

output "new_vpn_private_ip" {
  value       = aws_network_interface.new_vpn.private_ip
  description = "Private IP of the NEW VPN device ENI (used as LOCAL_IP in configure_ipsec.sh)"
}

output "new_vpn_public_ip" {
  value       = aws_eip.new_vpn.public_ip
  description = "Public IP of the NEW VPN device (attached to the NEW CGW)"
}

output "new_vpn_eni_id" {
  value       = aws_network_interface.new_vpn.id
  description = "ENI ID of the NEW VPN device (target of the on-premise route-table replace-route)"
}

output "new_customer_gateway_id" {
  value       = aws_customer_gateway.new.id
  description = "NEW CGW id — feed this into `aws ec2 modify-vpn-connection`"
}

# --- Ready-to-run commands for the manual steps ---

output "cutover_command" {
  value = "aws ec2 modify-vpn-connection --vpn-connection-id ${var.old_vpn_connection_id} --customer-gateway-id ${aws_customer_gateway.new.id}"
  description = "Step 1: switch the VPN Connection to the NEW CGW (downtime starts)"
}

output "onprem_route_replace_command" {
  value = "aws ec2 replace-route --route-table-id ${var.onprem_private_route_table_id} --destination-cidr-block 10.0.0.0/16 --network-interface-id ${aws_network_interface.new_vpn.id}"
  description = "Step 2: point on-premise private subnet traffic at the NEW ENI"
}

output "fetch_tunnel_options_command" {
  value = "aws ec2 describe-vpn-connections --vpn-connection-ids ${var.old_vpn_connection_id} --query 'VpnConnections[0].Options.TunnelOptions[].[OutsideIpAddress,PreSharedKey]' --output text"
  description = "Step 3: fetch the (possibly new) tunnel IPs + PSKs to feed into configure_ipsec.sh"
}

output "ssm_session_to_new_device" {
  value = "aws ssm start-session --target ${aws_instance.new_vpn.id}"
  description = "Step 4: SSM into the NEW device to run configure_ipsec.sh"
}

# --- Rollback commands ---

output "rollback_cgw_command" {
  value = "aws ec2 modify-vpn-connection --vpn-connection-id ${var.old_vpn_connection_id} --customer-gateway-id ${var.old_customer_gateway_id}"
  description = "Rollback 1: restore the ORIGINAL CGW on the VPN Connection"
}

output "rollback_route_command" {
  value = "aws ec2 replace-route --route-table-id ${var.onprem_private_route_table_id} --destination-cidr-block 10.0.0.0/16 --network-interface-id ${var.old_vpn_eni_id}"
  description = "Rollback 2: restore the on-premise RT to the ORIGINAL ENI"
}
