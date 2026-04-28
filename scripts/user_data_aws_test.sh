#!/bin/bash
set -eux
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y tcpdump nmap iperf3 htop netcat-openbsd telnet traceroute curl

# SSM Agent — Ubuntu on EC2 needs this installed (not pre-installed)
snap install amazon-ssm-agent --classic
snap start amazon-ssm-agent || true

hostnamectl set-hostname ${hostname}

mkdir -p /opt/ha-tests

cat > /opt/ha-tests/test_connectivity.sh << 'SCRIPT'
#!/bin/bash
TARGET="${onprem_target}"
echo "=== AWS -> OnPrem connectivity test ==="
echo "Target: $TARGET"
ping -c 5 $TARGET
echo ""
echo "=== Route to onprem ==="
ip route get $TARGET
echo ""
echo "=== Traceroute ==="
traceroute -n $TARGET
SCRIPT

cat > /opt/ha-tests/test_tunnel_failover.sh << 'SCRIPT'
#!/bin/bash
TARGET="${onprem_target}"
echo "=== VPN Tunnel Failover Test ==="
echo "Target: $TARGET"
echo ""
echo "Simulate a tunnel failure from the AWS Console:"
echo "  VPN Connections -> Modify Tunnel 1 Options (change PSK)"
echo "  BGP should withdraw tunnel 1 route -> tunnel 2 takes over in ~30s."
echo ""
ping -i 0.5 $TARGET
SCRIPT

chmod +x /opt/ha-tests/*.sh
