# AWS S2S VPN — Single Device (strongSwan) Pattern

온프레미스 VPN 장비 **1대 + 1 VPN Connection + 2 tunnels** 구성.
**실동작 검증 완료** (Ubuntu 22.04 + strongSwan 5.9.5 + SSM).

## 🎯 핵심 설계

- **1 CGW + 1 VPN Connection**: AWS는 동일 `(CGW, VGW)` 조합에 VPN Connection 1개만 허용함 (idempotent). 여러 Connection을 `for_each`로 만들려 하면 state가 꼬임.
- **Static Routing**: BGP 대신 AWS static route + `aws_vpn_connection_route`로 192.168.1.0/24 광고. 단순하고 안정적.
- **2 tunnels (기본 제공)**: AWS가 자동으로 2개 터널 + 다른 AZ endpoint 배치. 한 터널 장애 시 strongSwan이 다른 터널로 자동 전환.
- **SSM 기반 관리**: SSH 키 대신 SSM Session Manager + SSM Run Command. VPN 장비에도 `iam_instance_profile` 부여.

## 🏗️ 구조

- `02-aws-network.tf`: `terraform-aws-modules/vpc/aws` + `enable_vpn_gateway=true` + `propagate_private_route_tables_vgw=true`
- `03-onprem-network.tf`: onprem VPC + private subnet + route `10.0.0.0/16 → VPN device ENI` (source_dest_check=false)
- `04-vpn-connections.tf`: 1 raw `aws_customer_gateway` + 1 raw `aws_vpn_connection` + `aws_vpn_connection_route`
- `08-post-deployment.tf`: `aws_ssm_document` + `aws_ssm_association`로 configure_ipsec.sh 주입. `time_sleep` 180s로 user_data 완료 대기.
- `scripts/user_data_vpn.sh`: Ubuntu 22.04 + strongSwan 설치. **dpkg `--force-confold` 필수** (그렇지 않으면 ipsec.conf 프롬프트 대기로 user_data 실패).
- `scripts/configure_ipsec.sh`: strongSwan ipsec.conf/secrets 작성 + `ipsec restart`. IP forwarding 재확인 + onprem CIDR route 추가 + systemd service로 영구화.

## ⚠️ 이 코드베이스에서 지킬 규칙

### 절대 하지 말 것
- **`for_each`로 `aws_vpn_connection` 여러 개 만들기** — AWS가 1개로 합쳐서 반환 (태그만 덮어쓰기). state 중복 참조로 꼬임.
- **`aws_vpn_connection`을 `terraform-aws-modules/vpn-gateway`로 `for_each` 사용** — 같은 버그 발생.
- **Amazon Linux 2023 사용** — FRR EL9 RPM이 `libjson-c 0.15`를 요구하는데 AL2023은 `0.14`. 쓰려면 FRR 구버전을 소스빌드하거나 json-c 업그레이드 필요 (비추천).
- **`set -o pipefail`을 SSM Document runCommand에서 사용** — Ubuntu의 `/bin/sh`는 dash. `set -eu`까지만 허용. 실제 로직은 `bash /tmp/script.sh`로 호출.
- **`sysctl --system` 사용** — `set -e` 환경에서 지원 안되는 키가 있으면 아예 user_data 전체가 중단됨. `sysctl -p /etc/sysctl.d/99-vpn.conf`로 우리 파일만 적용.

### 꼭 해야 할 것
- **VPN 장비에 IP forwarding**: `net.ipv4.ip_forward=1`, 모든 rp_filter 0. user_data + configure 스크립트 양쪽에서 적용.
- **VPN 장비에 onprem CIDR route**: `ip route add $ONPREM_CIDR via <local_gw> metric 50`. 복호화된 패킷이 kernel forward 시 경로 못찾아 drop되기 때문. systemd oneshot unit으로 영구화.
- **strongSwan 재시작 후 `ipsec restart`**: `systemctl restart strongswan-starter`만으로는 기존 SA가 stale할 수 있음. `ipsec restart`가 SPI를 초기화하고 IKE 재협상을 강제.
- **VPN 장비 `source_dest_check = false`**: ENI 설정. 다른 IP로 향하는 패킷이 이 ENI를 통과할 수 있어야 함.

## 🔍 AWS VPN의 숨은 동작 (직접 확인한 사실)

1. **VPN Connection은 같은 (CGW, VGW)로 1개만** — 두번째 CreateVpnConnection 요청은 기존 것의 ID를 그대로 반환하고 태그만 업데이트.
2. **동일 VGW에 대한 병렬 CreateVpnConnection은 거부** — `ConcurrentMutationLimitExceeded`. 여러 connection 만들 때 `depends_on`으로 직렬화 필요 (이 프로젝트는 Connection 1개라 무관).
3. **CGW는 BGP ASN 필수** — static routes 쓰더라도 API가 요구함. `var.onprem_bgp_asn` 유지.
4. **IPsec 터널 SA 동기화 지연** — VPN 장비 replace 직후에는 AWS VGW가 구 SA를 잠시 유지. strongSwan을 `ipsec restart`로 재협상 강제하면 해결.

## 🧰 디버깅 팁

```bash
# VPN 장비 접속
aws ssm start-session --target $(terraform output -raw vpn_instance_id)

# 터널 상태
sudo ipsec status              # ESTABLISHED 2개 나와야 정상
sudo ipsec statusall | grep bytes  # bytes_i > 0 이어야 실제 트래픽 흐름

# xfrm (커널 IPsec 상태)
sudo ip xfrm state | head
sudo ip xfrm policy | head

# 라우팅
ip route show | grep 192.168
ip route get 192.168.1.10      # onprem 쪽으로 가는 경로 확인

# 패킷 캡처 (터널 외부)
sudo tcpdump -n -i ens5 'esp or port 500 or port 4500'

# AWS 측 터널 상태
aws ec2 describe-vpn-connections \
  --vpn-connection-ids $(terraform output -raw vpn_connection_id) \
  --query 'VpnConnections[0].VgwTelemetry[].[OutsideIpAddress,Status,AcceptedRouteCount]' \
  --output table
```

## 🔗 외부 참고
- AWS Site-to-Site VPN User Guide: https://docs.aws.amazon.com/vpn/latest/s2svpn/
- strongSwan: https://docs.strongswan.org/
- `aws_vpn_connection` provider doc: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_connection
