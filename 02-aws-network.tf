# Terraform Registry: terraform-aws-modules/vpc/aws v6.6.1

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "zone-name"
    values = ["${var.aws_region}a", "${var.aws_region}c"]
  }
}

locals {
  azs = data.aws_availability_zones.available.names
  common_tags = merge(var.common_tags, {
    Project   = var.project_name
    ManagedBy = "terraform"
    HAPattern = "single-cgw-dual-connection"
  })
}

module "aws_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_nat_gateway = true
  single_nat_gateway = true

  # VGW learns BGP routes from both VPN connections via route propagation
  enable_vpn_gateway                 = true
  propagate_private_route_tables_vgw = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.common_tags
}
