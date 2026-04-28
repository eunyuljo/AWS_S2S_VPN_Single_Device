# Terraform Registry: terraform-aws-modules/security-group/aws v5.3.1

module "sg_onprem_vpn" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.project_name}-onprem-vpn"
  description = "Security group for on-premise VPN device (IPsec + BGP)"
  vpc_id      = module.onprem_vpc.vpc_id

  ingress_with_cidr_blocks = [
    # SSH removed — SSM Session Manager is the access method
    { rule = "ipsec-500-udp", cidr_blocks = "0.0.0.0/0" },
    { rule = "ipsec-4500-udp", cidr_blocks = "0.0.0.0/0" },
    {
      from_port   = 0
      to_port     = 0
      protocol    = "50"
      description = "ESP protocol for IPSec"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 179
      to_port     = 179
      protocol    = "tcp"
      description = "BGP between VPN device and VGW tunnel endpoints"
      cidr_blocks = "0.0.0.0/0"
    },
    { rule = "all-tcp", cidr_blocks = "${var.onprem_vpc_cidr},${var.vpc_cidr}" },
    { rule = "all-icmp", cidr_blocks = "${var.onprem_vpc_cidr},${var.vpc_cidr}" },
  ]

  egress_rules = ["all-all"]
  tags         = local.common_tags
}

module "sg_onprem_internal" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.project_name}-onprem-internal"
  description = "Security group for on-premise internal instances"
  vpc_id      = module.onprem_vpc.vpc_id

  ingress_with_cidr_blocks = [
    # SSH removed — SSM Session Manager is the access method
    { rule = "all-icmp", cidr_blocks = "${var.onprem_vpc_cidr},${var.vpc_cidr}" },
    { rule = "all-tcp", cidr_blocks = "${var.onprem_vpc_cidr},${var.vpc_cidr}" },
    {
      from_port   = 5201
      to_port     = 5201
      protocol    = "tcp"
      description = "iperf3 server port"
      cidr_blocks = "${var.onprem_vpc_cidr},${var.vpc_cidr}"
    },
  ]

  egress_rules = ["all-all"]
  tags         = local.common_tags
}

module "sg_vpc_endpoints" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.project_name}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = module.aws_vpc.vpc_id

  ingress_with_cidr_blocks = [
    { rule = "https-443-tcp", cidr_blocks = var.vpc_cidr },
  ]

  egress_rules = ["all-all"]
  tags         = local.common_tags
}

module "sg_aws_test" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.project_name}-aws-test"
  description = "Security group for AWS test instances"
  vpc_id      = module.aws_vpc.vpc_id

  ingress_with_cidr_blocks = [
    # SSH removed — SSM Session Manager is the access method
    { rule = "all-icmp", cidr_blocks = "${var.vpc_cidr},${var.onprem_vpc_cidr}" },
    { rule = "all-tcp", cidr_blocks = "${var.vpc_cidr},${var.onprem_vpc_cidr}" },
    {
      from_port   = 5201
      to_port     = 5201
      protocol    = "tcp"
      description = "iperf3 server port"
      cidr_blocks = "${var.vpc_cidr},${var.onprem_vpc_cidr}"
    },
  ]

  egress_rules = ["all-all"]
  tags         = local.common_tags
}
