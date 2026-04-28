output "vpc_id" {
  value       = module.aws_vpc.vpc_id
  description = "AWS VPC ID"
}

output "vpc_cidr_block" {
  value       = module.aws_vpc.vpc_cidr_block
  description = "AWS VPC CIDR"
}

output "onprem_vpc_id" {
  value       = module.onprem_vpc.vpc_id
  description = "On-premise VPC ID"
}

output "onprem_private_cidr" {
  value       = var.onprem_private_cidr
  description = "On-premise private network"
}

output "vpn_gateway_id" {
  value       = module.aws_vpc.vgw_id
  description = "AWS VPN Gateway ID"
}

output "customer_gateway_id" {
  value       = aws_customer_gateway.this.id
  description = "Customer Gateway ID"
}

output "vpn_connection_id" {
  value       = aws_vpn_connection.this.id
  description = "VPN Connection ID"
}

output "vpn_tunnel_addresses" {
  value = {
    tunnel1 = aws_vpn_connection.this.tunnel1_address
    tunnel2 = aws_vpn_connection.this.tunnel2_address
  }
  description = "Public IPs of the 2 VPN tunnels"
}

output "vpn_public_ip" {
  value       = aws_eip.vpn.public_ip
  description = "Public IP of the single VPN device"
}

output "vpn_instance_id" {
  value       = aws_instance.vpn.id
  description = "VPN device Instance ID"
}

output "onprem_test_private_ip" {
  value       = aws_instance.onprem_test.private_ip
  description = "On-premise test instance private IP"
}

output "aws_test_instance_ids" {
  value       = { for k, v in aws_instance.aws_test : k => v.id }
  description = "AWS test instance IDs (SSM accessible)"
}

output "aws_test_private_ips" {
  value       = { for k, v in aws_instance.aws_test : k => v.private_ip }
  description = "AWS test instance private IPs"
}

output "ssm_commands" {
  value = {
    vpn_device  = "aws ssm start-session --target ${aws_instance.vpn.id}"
    aws_test_a  = "aws ssm start-session --target ${aws_instance.aws_test["a"].id}"
    aws_test_c  = "aws ssm start-session --target ${aws_instance.aws_test["c"].id}"
    onprem_test = "aws ssm start-session --target ${aws_instance.onprem_test.id}  # requires NAT/endpoint in onprem VPC"
  }
  description = "SSM access commands (no SSH key needed)"
}

output "ssm_association_id" {
  value       = aws_ssm_association.configure_vpn.association_id
  description = "SSM Association that configures IPsec + BGP"
}
