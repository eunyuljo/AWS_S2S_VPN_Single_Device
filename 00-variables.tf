variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "single-vpn"
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

# --- AWS VPC ---

variable "vpc_cidr" {
  description = "CIDR block for AWS VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for AWS private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for AWS public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

# --- On-premise (single device) ---

variable "onprem_vpc_cidr" {
  description = "CIDR block for on-premise simulation VPC"
  type        = string
  default     = "192.168.0.0/16"
}

variable "onprem_public_subnet_cidr" {
  description = "Public subnet for the single VPN device"
  type        = string
  default     = "192.168.101.0/24"
}

variable "onprem_private_cidr" {
  description = "On-premise private network (advertised to AWS via BGP)"
  type        = string
  default     = "192.168.1.0/24"
}

# --- VPN ---
# Single CGW + Single VPN Connection (2 tunnels by default).
# The 2 tunnels provide HA at the tunnel level — if one goes down,
# traffic automatically flows through the other. This is the standard
# AWS pattern for single-device VPN deployments.

variable "onprem_bgp_asn" {
  description = "BGP ASN of the single on-premise VPN device"
  type        = number
  default     = 65000
}

variable "vpn_instance_type" {
  description = "Instance type for VPN device"
  type        = string
  default     = "t3.small"
}

# SSH key pair is optional — SSM Session Manager is the primary access method.
variable "key_pair_name" {
  description = "Optional EC2 Key Pair for SSH fallback (leave empty to disable SSH)"
  type        = string
  default     = ""
}
