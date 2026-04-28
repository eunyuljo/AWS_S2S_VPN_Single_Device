# Single on-premise VPN device, single public subnet for it,
# single private subnet — the whole network advertised through both VPN Connections.

module "onprem_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project_name}-onprem"
  cidr = var.onprem_vpc_cidr
  azs  = [local.azs[0]]

  public_subnets = [var.onprem_public_subnet_cidr]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.common_tags
}

resource "aws_subnet" "onprem_private" {
  vpc_id            = module.onprem_vpc.vpc_id
  cidr_block        = var.onprem_private_cidr
  availability_zone = local.azs[0]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-onprem-private"
  })
}

resource "aws_route_table" "onprem_private" {
  vpc_id = module.onprem_vpc.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-onprem-private-rt"
  })
}

# Single VPN device ENI is the only egress for OnPrem -> AWS traffic.
# Single device = single point of failure on the on-premise side (by design).
# The dual VPN connections protect against AWS-side / tunnel-side failures only.
resource "aws_route" "onprem_to_aws" {
  route_table_id         = aws_route_table.onprem_private.id
  destination_cidr_block = var.vpc_cidr
  network_interface_id   = aws_network_interface.vpn.id
}

resource "aws_route_table_association" "onprem_private" {
  subnet_id      = aws_subnet.onprem_private.id
  route_table_id = aws_route_table.onprem_private.id
}
