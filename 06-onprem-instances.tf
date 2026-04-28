# Ubuntu 22.04 LTS (Canonical). Chosen over Amazon Linux 2023 because
# the official FRR RPM repo conflicts with AL2023's json-c library version.
# Ubuntu's apt FRR package works cleanly and is the industry standard for
# Linux VPN appliances.
data "aws_ami" "vpn_base" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_network_interface" "vpn" {
  subnet_id         = module.onprem_vpc.public_subnets[0]
  security_groups   = [module.sg_onprem_vpn.security_group_id]
  source_dest_check = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpn-eni"
  })
}

resource "aws_eip" "vpn" {
  domain            = "vpc"
  network_interface = aws_network_interface.vpn.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpn-eip"
  })

  depends_on = [module.onprem_vpc]
}

# Single VPN device that terminates BOTH VPN Connections (4 tunnels total).
# Configuration is injected via SSM Run Command (see 08-post-deployment.tf).
resource "aws_instance" "vpn" {
  ami                  = data.aws_ami.vpn_base.id
  instance_type        = var.vpn_instance_type
  key_name             = var.key_pair_name != "" ? var.key_pair_name : null
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  network_interface {
    network_interface_id = aws_network_interface.vpn.id
    device_index         = 0
  }

  user_data = templatefile("${path.module}/scripts/user_data_vpn.sh", {
    hostname = "${var.project_name}-vpn-device"
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpn-device"
  })

  depends_on = [
    aws_vpn_connection.this,
    aws_eip.vpn
  ]
}

resource "aws_instance" "onprem_test" {
  ami                    = data.aws_ami.vpn_base.id
  instance_type          = "t3.micro"
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  subnet_id              = aws_subnet.onprem_private.id
  vpc_security_group_ids = [module.sg_onprem_internal.security_group_id]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-onprem-test"
  })
}
