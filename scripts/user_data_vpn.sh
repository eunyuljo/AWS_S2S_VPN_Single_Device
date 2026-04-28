#!/bin/bash
# VPN device bootstrap on Ubuntu 22.04 LTS — strongSwan + static routing.
# IPsec / route config is injected later via SSM Run Command (configure_ipsec.sh).

set -euxo pipefail

hostnamectl set-hostname ${hostname}

export DEBIAN_FRONTEND=noninteractive

apt-get update -y

# --force-confold: keep existing /etc/ipsec.conf (we overwrite it later anyway
# via SSM). Without this, dpkg stops at an interactive prompt if a prior run
# left ipsec.conf on disk, and user_data aborts mid-install.
apt-get install -y \
    -o 'Dpkg::Options::=--force-confdef' \
    -o 'Dpkg::Options::=--force-confold' \
    strongswan strongswan-pki libcharon-extra-plugins \
    tcpdump iptables-persistent bind9-dnsutils curl

# SSM Agent — not pre-installed on Ubuntu EC2
snap install amazon-ssm-agent --classic
snap start amazon-ssm-agent || true

# sysctl — enable IP forwarding (required for packet forwarding between
# IPsec tunnel and local NIC), disable reverse-path filter.
cat > /etc/sysctl.d/99-vpn.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
SYSCTL
# Apply only our file (sysctl --system can fail on unsupported keys and abort
# user_data under `set -e`).
sysctl -p /etc/sysctl.d/99-vpn.conf

# Firewall — allow IPsec (ESP, UDP/500 for IKE, UDP/4500 for NAT-T)
iptables -A INPUT -p esp -j ACCEPT
iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT
iptables -A FORWARD -j ACCEPT
netfilter-persistent save

mkdir -p /opt/vpn-config
systemctl enable strongswan-starter
