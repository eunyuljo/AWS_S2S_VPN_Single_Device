# Single CGW + Single VPN Connection (2 tunnels, static routing).
# Static routing chosen for implementation simplicity — strongSwan has official
# AWS support for IKEv1 + static routes but not for VTI-based BGP on Ubuntu.
# Tunnel-level HA is still provided by AWS: if tunnel 1 fails, AWS redirects
# traffic via tunnel 2 (the VPN Connection route in the VPC route table stays
# valid as long as at least one tunnel is UP).

resource "aws_customer_gateway" "this" {
  bgp_asn    = var.onprem_bgp_asn # Required even for static routes (AWS API)
  ip_address = aws_eip.vpn.public_ip
  type       = "ipsec.1"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-cgw"
  })
}

resource "aws_vpn_connection" "this" {
  vpn_gateway_id      = module.aws_vpc.vgw_id
  customer_gateway_id = aws_customer_gateway.this.id
  type                = "ipsec.1"
  static_routes_only  = true # Static routing (strongSwan-friendly)

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpn"
  })
}

# Static route: tell AWS VGW that our on-premise network is reachable via this VPN Connection.
resource "aws_vpn_connection_route" "onprem" {
  vpn_connection_id      = aws_vpn_connection.this.id
  destination_cidr_block = var.onprem_private_cidr
}
