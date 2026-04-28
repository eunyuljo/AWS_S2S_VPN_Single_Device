# Configure strongSwan (IPsec + static routing) on the single VPN device
# via SSM Run Command. No SSH key required.

locals {
  # 7 positional args for configure_ipsec.sh:
  # local_ip, onprem_cidr, vpc_cidr, t1_pub, t2_pub, t1_psk, t2_psk
  configure_args = [
    aws_network_interface.vpn.private_ip,
    var.onprem_private_cidr,
    var.vpc_cidr,
    aws_vpn_connection.this.tunnel1_address,
    aws_vpn_connection.this.tunnel2_address,
    aws_vpn_connection.this.tunnel1_preshared_key,
    aws_vpn_connection.this.tunnel2_preshared_key,
  ]

  configure_script = file("${path.module}/scripts/configure_ipsec.sh")
}

resource "aws_ssm_document" "configure_vpn" {
  name            = "${var.project_name}-configure-vpn"
  document_type   = "Command"
  document_format = "YAML"
  tags            = local.common_tags

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Configure strongSwan IPsec on the VPN device"
    parameters = {
      args = {
        type        = "String"
        description = "Positional arguments for configure_ipsec.sh"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "configureVpn"
        inputs = {
          timeoutSeconds = "600"
          runCommand = [
            # SSM runs via /bin/sh (dash on Ubuntu) — avoid bash-only syntax
            "set -eu",
            "cat > /tmp/configure_ipsec.sh <<'CONFIGURE_SCRIPT_EOF'",
            local.configure_script,
            "CONFIGURE_SCRIPT_EOF",
            "chmod +x /tmp/configure_ipsec.sh",
            "bash /tmp/configure_ipsec.sh {{ args }}",
          ]
        }
      }
    ]
  })
}

resource "time_sleep" "wait_for_user_data" {
  create_duration = "180s"

  depends_on = [
    aws_instance.vpn,
    aws_vpn_connection.this
  ]
}

resource "aws_ssm_association" "configure_vpn" {
  name             = aws_ssm_document.configure_vpn.name
  association_name = "${var.project_name}-configure-vpn"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.vpn.id]
  }

  parameters = {
    args = join(" ", [for a in local.configure_args : "\"${a}\""])
  }

  depends_on = [time_sleep.wait_for_user_data]
}
