# Scenario: Customer Gateway Replacement

**온프레미스 VPN 장비를 새 하드웨어로 교체**하는 시나리오를 Terraform 밖에서 수동 실습.
기존 VPN 장비를 **살려둔 채** 새 장비를 올려 트래픽을 전환한 뒤, 구 장비를 정리하는 흐름.

---

## 🎯 학습 목표

- `aws ec2 modify-vpn-connection`으로 **VPN Connection을 재생성하지 않고 CGW 교체**
- 교체 중 **downtime 측정** (연속 ping)
- 새 VPN 장비에 strongSwan 설정 주입 (PSK 재협상)
- OnPrem 라우팅 테이블 전환
- Terraform state 바깥에서 변경된 리소스 **drift 체크 및 복구** 경험

---

## 🚦 전제 조건

- 부모 프로젝트 (`../../`)가 `terraform apply`로 **정상 배포된 상태**여야 합니다.
- 현재 VPN 통신(AWS → OnPrem) 이 **실제로 동작 중**이어야 함 (baseline).

---

## 🗺️ 아키텍처 변화

### Before
```
AWS VPC ── VGW ── VPN Connection ── CGW(old) ── VPN Device(old)
                                      │ EIP: 3.39.117.31
OnPrem private RT: 10.0.0.0/16 → ENI(old)
```

### After
```
AWS VPC ── VGW ── VPN Connection ── CGW(new) ── VPN Device(new)
                                      │ EIP: 43.203.73.105
OnPrem private RT: 10.0.0.0/16 → ENI(new)
```

**VPN Connection ID는 유지** (vpn-xxx), CGW/장비만 교체.

---

## ⚠️ 사전 주의

- **Terraform은 건드리지 않습니다** — 시나리오는 AWS CLI + SSM만 사용.
- 이 실습 후 `terraform plan`을 돌리면 **drift** 발생 (원래 CGW가 돌아오려 함).
- 실습 종료 후 **롤백 또는 state import** 중 하나를 반드시 수행해야 Terraform 정합성 복구.

---

## 🛠️ 실습 도구 — 3가지 방식 제공

1. **순수 AWS CLI** — 아래 Phase 0~6을 직접 실행 (가장 학습 효과 큼)
2. **래퍼 스크립트** — `scripts/01-provision-new-device.sh` → `02-cutover.sh` → `03-switch-onprem-rt.sh` → `99-rollback.sh` 순으로 실행
3. **Terraform** — `terraform/` 폴더. 새 인프라 생성만 선언적 IaC로, CGW 교체/RT 변경은 여전히 CLI

자세한 비교: [`terraform/README.md`](./terraform/README.md)

---

## 📖 실행 순서 (순수 AWS CLI)

### Phase 0 — Baseline 기록

```bash
# 부모 프로젝트 폴더로 이동
cd ../..

# Baseline 값 기록 (변수로 저장하거나 따로 메모)
OLD_VPN_CONN_ID=$(terraform output -raw vpn_connection_id)
OLD_CGW_ID=$(terraform output -raw customer_gateway_id)
OLD_VPN_EC2=$(terraform output -raw vpn_instance_id)
OLD_EIP=$(terraform output -raw vpn_public_ip)

# 온프레 private RT와 구 ENI
ONPREM_RT=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$(terraform output -raw onprem_vpc_id)" \
            "Name=tag:Name,Values=*onprem-private-rt*" \
  --query 'RouteTables[0].RouteTableId' --output text)
OLD_ENI=$(aws ec2 describe-route-tables --route-table-ids $ONPREM_RT \
  --query 'RouteTables[0].Routes[?DestinationCidrBlock==`10.0.0.0/16`].NetworkInterfaceId | [0]' \
  --output text)

# VPN 장비와 같은 서브넷/SG (새 장비도 같은 위치에 배치)
SUBNET_ID=$(aws ec2 describe-instances --instance-ids $OLD_VPN_EC2 \
  --query 'Reservations[0].Instances[0].SubnetId' --output text)
SG_ID=$(aws ec2 describe-instances --instance-ids $OLD_VPN_EC2 \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

cat <<EOF
=== Baseline ===
VPN Connection : $OLD_VPN_CONN_ID
Old CGW        : $OLD_CGW_ID
Old VPN EC2    : $OLD_VPN_EC2
Old EIP        : $OLD_EIP
Old ENI        : $OLD_ENI
OnPrem RT      : $ONPREM_RT
Subnet         : $SUBNET_ID
SG             : $SG_ID
EOF
```

### Phase 1 — 새 VPN 장비 생성

```bash
# Ubuntu 22.04 AMI
AMI=$(aws ec2 describe-images --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)

# user_data 준비 (부모 프로젝트의 것과 동일, hostname만 변경)
sed "s/\${hostname}/single-vpn-vpn-device-NEW/g" ../../scripts/user_data_vpn.sh > /tmp/ud_new.sh

# 새 ENI (source_dest_check=false 필수)
NEW_ENI=$(aws ec2 create-network-interface \
  --subnet-id $SUBNET_ID --groups $SG_ID \
  --tag-specifications 'ResourceType=network-interface,Tags=[{Key=Name,Value=single-vpn-vpn-eni-NEW}]' \
  --query 'NetworkInterface.NetworkInterfaceId' --output text)
aws ec2 modify-network-interface-attribute \
  --network-interface-id $NEW_ENI --source-dest-check "{\"Value\":false}"
NEW_ENI_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $NEW_ENI \
  --query 'NetworkInterfaces[0].PrivateIpAddress' --output text)

# 새 EIP 할당 + 연결
NEW_EIP_ALLOC=$(aws ec2 allocate-address --domain vpc \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=single-vpn-vpn-eip-NEW}]' \
  --query 'AllocationId' --output text)
NEW_EIP=$(aws ec2 describe-addresses --allocation-ids $NEW_EIP_ALLOC \
  --query 'Addresses[0].PublicIp' --output text)
aws ec2 associate-address --allocation-id $NEW_EIP_ALLOC --network-interface-id $NEW_ENI

# 새 EC2 장비 (같은 IAM profile 사용 — SSM 가능)
NEW_INST=$(aws ec2 run-instances \
  --image-id $AMI --instance-type t3.small \
  --iam-instance-profile Name=single-vpn-ssm-profile \
  --network-interfaces "NetworkInterfaceId=$NEW_ENI,DeviceIndex=0" \
  --user-data file:///tmp/ud_new.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=single-vpn-vpn-device-NEW}]' \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --instance-ids $NEW_INST

echo "New EC2 : $NEW_INST ($NEW_ENI_IP / $NEW_EIP)"

# user_data 완료까지 대기 (strongSwan 설치 ~2-3분)
sleep 180
```

### Phase 2 — 연속 ping 시작 (별도 터미널)

downtime 측정용. AWS 테스트 인스턴스에 SSM으로 접속:

```bash
aws ssm start-session --target $(terraform output -json aws_test_instance_ids | jq -r '.a')

# 세션 안에서
ping -i 1 $(terraform output -raw onprem_test_private_ip)
# 화면 보면서 얼마나 끊기는지 관찰
```

### Phase 3 — 새 CGW 등록 + VPN Connection CGW 교체

```bash
# 새 CGW (새 EIP 기준)
NEW_CGW=$(aws ec2 create-customer-gateway \
  --bgp-asn 65000 --public-ip $NEW_EIP --type ipsec.1 \
  --tag-specifications 'ResourceType=customer-gateway,Tags=[{Key=Name,Value=single-vpn-cgw-NEW}]' \
  --query 'CustomerGateway.CustomerGatewayId' --output text)
echo "New CGW: $NEW_CGW"

# VPN Connection의 CGW 교체 → downtime 시작
aws ec2 modify-vpn-connection \
  --vpn-connection-id $OLD_VPN_CONN_ID --customer-gateway-id $NEW_CGW

# State가 modifying → available 로 바뀔 때까지 대기
while true; do
  STATE=$(aws ec2 describe-vpn-connections --vpn-connection-ids $OLD_VPN_CONN_ID \
    --query 'VpnConnections[0].State' --output text)
  echo "$(date +%H:%M:%S) state=$STATE"
  [ "$STATE" = "available" ] && break
  sleep 10
done
```

### Phase 4 — 새 장비에 strongSwan 설정 주입

```bash
# 새 PSK/tunnel IP 조회 (CGW 교체 후 AWS가 재발급)
aws ec2 describe-vpn-connections --vpn-connection-ids $OLD_VPN_CONN_ID \
  --query 'VpnConnections[0].Options.TunnelOptions[].[OutsideIpAddress,PreSharedKey]' \
  --output text
# 출력:
# <T1_PUB>  <T1_PSK>
# <T2_PUB>  <T2_PSK>
```

환경 변수로 받기:
```bash
eval $(aws ec2 describe-vpn-connections --vpn-connection-ids $OLD_VPN_CONN_ID \
  --query 'VpnConnections[0].Options.TunnelOptions' --output json | python3 -c "
import json,sys
t = json.load(sys.stdin)
print(f'T1_PUB={t[0][\"OutsideIpAddress\"]}')
print(f'T2_PUB={t[1][\"OutsideIpAddress\"]}')
print(f'T1_PSK={t[0][\"PreSharedKey\"]}')
print(f'T2_PSK={t[1][\"PreSharedKey\"]}')
")
```

새 장비 SSM 접속 후 configure 스크립트 실행:
```bash
aws ssm start-session --target $NEW_INST

# 세션 안 (sudo -i 후)
wget -q -O /tmp/configure_ipsec.sh https://raw.githubusercontent.com/.../configure_ipsec.sh
# 또는 ../../scripts/configure_ipsec.sh 내용을 복사

bash /tmp/configure_ipsec.sh \
  "192.168.101.X" \        # 새 ENI의 private IP (NEW_ENI_IP 확인)
  "192.168.1.0/24" \
  "10.0.0.0/16" \
  "<T1_PUB>" "<T2_PUB>" \
  "<T1_PSK>" "<T2_PSK>"
```

⚠️ **설정 2번째 실행 시 주의**: `ipsec restart`로 charon이 완전히 안 죽을 때가 있음.
```bash
sudo ipsec stop
sudo pkill -9 charon || true
sudo pkill -9 starter || true
sudo rm -f /var/run/charon.pid /var/run/starter.charon.pid
sudo ip xfrm policy flush
sudo ip xfrm state flush
sudo ipsec start
```

양방향 SA ESTABLISHED 확인:
```bash
sudo ipsec statusall | grep -E "ESTABLISHED|INSTALLED|bytes"
```

### Phase 5 — OnPrem RT 전환

```bash
aws ec2 replace-route \
  --route-table-id $ONPREM_RT \
  --destination-cidr-block 10.0.0.0/16 \
  --network-interface-id $NEW_ENI
```

### Phase 6 — 검증

```bash
# 새 터널 실제 트래픽
aws ec2 describe-vpn-connections --vpn-connection-ids $OLD_VPN_CONN_ID \
  --query 'VpnConnections[0].VgwTelemetry[].[OutsideIpAddress,Status,AcceptedRouteCount]' \
  --output table

# CloudWatch로 양방향 바이트 확인
aws cloudwatch get-metric-statistics --namespace AWS/VPN \
  --metric-name TunnelDataOut --dimensions Name=VpnId,Value=$OLD_VPN_CONN_ID \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 --statistics Sum

# E2E ping (ping 세션으로 돌아가서 확인)
```

---

## 🔙 롤백 (실습 종료 후)

Terraform 상태로 복귀:

```bash
# 1. VPN Connection을 구 CGW로 되돌림
aws ec2 modify-vpn-connection \
  --vpn-connection-id $OLD_VPN_CONN_ID --customer-gateway-id $OLD_CGW_ID

# State 대기
while [ "$(aws ec2 describe-vpn-connections --vpn-connection-ids $OLD_VPN_CONN_ID \
  --query 'VpnConnections[0].State' --output text)" != "available" ]; do
  sleep 10
done

# 2. OnPrem RT 구 ENI로 복귀
aws ec2 replace-route --route-table-id $ONPREM_RT \
  --destination-cidr-block 10.0.0.0/16 --network-interface-id $OLD_ENI

# 3. 구 VPN 장비의 strongSwan 재시작 (새 PSK로 재협상)
#    (CGW 교체로 구 PSK는 invalid. 부모 프로젝트의 SSM Association 재실행)
aws ssm start-associations-once \
  --association-ids $(terraform output -raw ssm_association_id)

# 4. 새로 만든 리소스 삭제
aws ec2 terminate-instances --instance-ids $NEW_INST
aws ec2 wait instance-terminated --instance-ids $NEW_INST

aws ec2 delete-customer-gateway --customer-gateway-id $NEW_CGW
aws ec2 release-address --allocation-id $NEW_EIP_ALLOC
aws ec2 delete-network-interface --network-interface-id $NEW_ENI
```

롤백 후 **`terraform plan`**을 돌려 drift가 없는지 최종 확인.

---

## 💡 이 시나리오에서 배운 것 (실습 중 해결한 이슈)

| 문제 | 원인 | 해결 |
|------|------|------|
| strongSwan 재실행 시 "charon is already running" | `ipsec restart`가 새 데몬 시작 전 pid 충돌 감지 | `ipsec stop` + `pkill -9 charon` + pid 파일 삭제 후 `ipsec start` |
| 터널 2개 ESTABLISHED인데 bytes 0 | 같은 selector 공유하는 2 SA 중 하나만 fwd policy 설치됨 | `xfrm policy/state flush` 후 완전 재시작 |
| AWS 터널 IP와 장비 EIP 혼동 | `43.203.73.105`는 장비 EIP (CGW), AWS 터널은 별개 | AWS 터널은 `describe-vpn-connections`의 `OutsideIpAddress` |
| `net.ipv4.conf.ens5.rp_filter = 2` | Ubuntu 기본값이 loose reverse-path filter | `sysctl -w net.ipv4.conf.ens5.rp_filter=0` |

**핵심 교훈**: strongSwan이 여러 SA를 같은 selector로 협상할 때는 **완전 재시작이 필수**. 단순 `systemctl restart`로는 xfrm state가 stale하게 남음.

---

## 📜 참고

- [ModifyVpnConnection API](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_ModifyVpnConnection.html)
- [Change the customer gateway](https://docs.aws.amazon.com/vpn/latest/s2svpn/change-vpn-cgw.html)
- strongSwan status / xfrm: `man ipsec`, `man ip-xfrm`
