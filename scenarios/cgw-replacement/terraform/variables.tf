variable "aws_region" {
  description = "AWS region (must match the parent project)"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project prefix used for naming"
  type        = string
  default     = "single-vpn"
}

# --- Inputs from the parent project ---
# Run `terraform output` in the parent project to get these values.

variable "onprem_public_subnet_id" {
  description = "On-premise public subnet where the NEW VPN device lives (same subnet as OLD device)"
  type        = string
}

variable "onprem_vpn_sg_id" {
  description = "Security group for the on-premise VPN device (reuse parent's single-vpn-onprem-vpn SG)"
  type        = string
}

variable "ssm_instance_profile_name" {
  description = "IAM instance profile with SSM permissions (reuse parent's single-vpn-ssm-profile)"
  type        = string
  default     = "single-vpn-ssm-profile"
}

# Passed for reference / outputs only — NOT modified here
variable "old_vpn_connection_id" {
  description = "ID of the parent's VPN Connection (the target of the cutover)"
  type        = string
}

variable "old_customer_gateway_id" {
  description = "ID of the parent's (OLD) CGW — used for rollback instructions"
  type        = string
}

variable "onprem_private_route_table_id" {
  description = "On-premise private subnet route table id (target of the cutover's replace-route)"
  type        = string
}

variable "old_vpn_eni_id" {
  description = "ENI id of the parent's (OLD) VPN device — used for rollback instructions"
  type        = string
}

# --- BGP / Instance settings ---

variable "onprem_bgp_asn" {
  description = "BGP ASN to attach to the new CGW (must match old CGW for ModifyVpnConnection to accept)"
  type        = number
  default     = 65000
}

variable "vpn_instance_type" {
  description = "Instance type for the new VPN device"
  type        = string
  default     = "t3.small"
}
