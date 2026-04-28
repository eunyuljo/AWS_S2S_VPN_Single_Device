resource "aws_instance" "aws_test" {
  for_each = toset(["a", "c"])

  ami                    = data.aws_ami.vpn_base.id
  instance_type          = "t3.micro"
  subnet_id              = module.aws_vpc.private_subnets[index(["a", "c"], each.key)]
  vpc_security_group_ids = [module.sg_aws_test.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name

  user_data = templatefile("${path.module}/scripts/user_data_aws_test.sh", {
    hostname      = "aws-test-${each.key}"
    onprem_target = cidrhost(var.onprem_private_cidr, 10)
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-aws-test-${each.key}"
  })
}

# --- IAM for SSM ---

resource "aws_iam_role" "ssm_role" {
  name = "${var.project_name}-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "${var.project_name}-ssm-profile"
  role = aws_iam_role.ssm_role.name
  tags = local.common_tags
}

# --- VPC Endpoints for SSM ---

resource "aws_vpc_endpoint" "ssm" {
  for_each = toset(["ssm", "ssmmessages", "ec2messages"])

  vpc_id              = module.aws_vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.aws_vpc.private_subnets
  security_group_ids  = [module.sg_vpc_endpoints.security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${each.key}-endpoint"
  })
}
