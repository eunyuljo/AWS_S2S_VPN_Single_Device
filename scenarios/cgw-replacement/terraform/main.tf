# CGW Replacement Scenario — Terraform version
#
# Creates the "new" side of the cutover: new VPN device, new ENI, new EIP,
# and new Customer Gateway. The actual switch-over is still done via AWS CLI
# (see outputs for ready-to-run commands) because the VPN Connection and the
# on-premise route table are owned by the parent project's Terraform state.

locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform-scenario-cgw-replacement"
    Purpose   = "CGW-replacement-drill"
  }
}

# Reuse the same Ubuntu 22.04 LTS that the parent project uses
data "aws_ami" "ubuntu" {
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

# --- New VPN device network interface ---
# source_dest_check=false is MANDATORY so the ENI can forward decrypted traffic
# from the IPsec tunnel to the on-premise private subnet.
resource "aws_network_interface" "new_vpn" {
  subnet_id         = var.onprem_public_subnet_id
  security_groups   = [var.onprem_vpn_sg_id]
  source_dest_check = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpn-eni-NEW"
  })
}

# --- New EIP (this public IP becomes the NEW Customer Gateway's IP) ---
resource "aws_eip" "new_vpn" {
  domain            = "vpc"
  network_interface = aws_network_interface.new_vpn.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpn-eip-NEW"
  })
}

# --- New CGW (registered in AWS with the NEW EIP) ---
# Note: bgp_asn must match the old CGW — AWS ModifyVpnConnection rejects a
# change that would alter the connection's advertised ASN.
resource "aws_customer_gateway" "new" {
  bgp_asn    = var.onprem_bgp_asn
  ip_address = aws_eip.new_vpn.public_ip
  type       = "ipsec.1"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-cgw-NEW"
  })
}

# --- New VPN device EC2 ---
# Runs the SAME user_data as the parent project (strongSwan + SSM Agent) so
# that operational procedures (SSM Run Command, logs, etc.) stay identical.
resource "aws_instance" "new_vpn" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.vpn_instance_type
  iam_instance_profile = var.ssm_instance_profile_name

  network_interface {
    network_interface_id = aws_network_interface.new_vpn.id
    device_index         = 0
  }

  # Reuse the parent project's user_data script — keeps both devices identical
  user_data = templatefile("${path.module}/../../../scripts/user_data_vpn.sh", {
    hostname = "${var.project_name}-vpn-device-NEW"
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpn-device-NEW"
  })
}
