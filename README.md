# AWS Site-to-Site VPN — Single Device (strongSwan) Reference

온프레미스에 **VPN 장비 1대**와 AWS VPC 간의 **IPsec Site-to-Site VPN**을 Terraform으로 구축하는 레퍼런스 프로젝트입니다.
AWS S2S VPN의 가장 기본적이고 표준적인 배포 패턴으로, **실동작 검증이 완료된** 상태입니다.

---

## 🎯 이 프로젝트가 보여주는 것

- AWS VPC ↔ 온프레미스(시뮬레이션) 간 **IPsec VPN** 구축
- **1 Customer Gateway + 1 VPN Connection (2 tunnels)** 구성
- **strongSwan 5.9.5** on Ubuntu 22.04 LTS
- **SSM Session Manager 기반 관리** (SSH 키 불필요)
- **Terraform AWS 공식 모듈** 사용 (`vpc`, `security-group`)
- **실동작 검증됨**: AWS 테스트 인스턴스 → OnPrem 테스트 인스턴스 ping 성공

---

## 🏗️ 아키텍처

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    AWS Account (ap-northeast-2)                         │
│                                                                         │
│  ┌─── On-premise VPC (192.168.0.0/16) ─────────────┐                    │
│  │                                                  │                    │
│  │  Public Subnet (AZ-a) 192.168.101.0/24          │                    │
│  │  ┌─────────────────────────┐                     │                    │
│  │  │ VPN Device              │                     │                    │
│  │  │  Ubuntu 22.04 + strongSwan 5.9.5              │                    │
│  │  │  1 ENI (source_dest_check=false)              │                    │
│  │  │  1 EIP (static public IP)                     │                    │
│  │  │  IP forwarding enabled                        │                    │
│  │  └─────┬───────────────────┘                     │                    │
│  │        │ IPsec policy:                           │                    │
│  │        │  192.168.1.0/24 <-> 10.0.0.0/16         │                    │
│  │        │                                         │                    │
│  │  Private Subnet (AZ-a) 192.168.1.0/24            │                    │
│  │  ┌──────────────┐                                │                    │
│  │  │ OnPrem Test  │ <-- 192.168.1.x                │                    │
│  │  └──────────────┘                                │                    │
│  │  (route table: 10.0.0.0/16 → VPN device ENI)     │                    │
│  └───────────┬──────────────────────────────────────┘                    │
│              │ 2 IPsec tunnels over Internet                             │
│              │ (UDP 4500 NAT-T, AES-128, SHA1, DH Group 2)               │
│              ▼                                                           │
│  ┌─────────────────────────────────────────────────┐                     │
│  │ VPN Gateway (VGW)                               │                     │
│  │ Static route: 192.168.1.0/24 → VPN Connection   │                     │
│  │ Route propagation to VPC private route table    │                     │
│  └───────────┬─────────────────────────────────────┘                     │
│              │                                                           │
│  ┌─── AWS VPC (10.0.0.0/16) ────────────────────────┐                    │
│  │                                                  │                    │
│  │  Private Subnets (AZ-a, AZ-c)                    │                    │
│  │  ┌──────────────┐  ┌──────────────┐              │                    │
│  │  │ AWS Test a   │  │ AWS Test c   │              │                    │
│  │  │ 10.0.1.x     │  │ 10.0.2.x     │              │                    │
│  │  └──────────────┘  └──────────────┘              │                    │
│  │                                                  │                    │
│  │  NAT Gateway + VPC Endpoints (SSM)               │                    │
│  └──────────────────────────────────────────────────┘                    │
└─────────────────────────────────────────────────────────────────────────┘
```

### 동작 원리 (AWS test → OnPrem test 방향, 검증 완료)

1. AWS Test 인스턴스가 `ping 192.168.1.x` 발송
2. AWS VPC 라우팅 테이블: `192.168.1.0/24 → VGW` (route propagation)
3. VGW가 static route 조회 → VPN Connection으로 전달
4. IPsec 터널로 암호화 → 인터넷 경유 → VPN 장비 EIP로 도달
5. VPN 장비 strongSwan이 복호화 → kernel이 `192.168.1.0/24 via 192.168.101.1`로 forward
6. OnPrem VPC 라우팅이 192.168.1.0/24 private subnet의 인스턴스로 전달

### Tunnel-Level HA

- AWS는 VPN Connection당 **2개 터널을 서로 다른 AZ에 자동 배치**
- strongSwan이 `AWS-Tunnel-1`, `AWS-Tunnel-2`를 모두 `auto=start`로 유지
- **한 터널 장애 시 두번째로 자동 전환** (DPD 30초)

### 한계 (의도적)

- **VPN 장비 1대 = SPOF**: 장비 고장 시 전체 통신 단절
- **BGP 대신 Static Routing**: 구현 단순화 (strongSwan의 BGP+VTI 조합은 AWS 공식 레퍼런스 기준에서도 설정이 복잡함)

---

## 📁 프로젝트 구조

```
.
├── 00-variables.tf          # 변수 (CIDR, BGP ASN, 키페어 등)
├── 01-versions.tf           # Terraform / AWS provider / time provider
├── 02-aws-network.tf        # AWS VPC (terraform-aws-modules/vpc) + VGW
├── 03-onprem-network.tf     # 온프레미스 VPC + Private 서브넷 라우팅
├── 04-vpn-connections.tf    # CGW + VPN Connection (static routes)
├── 05-security-groups.tf    # 4개 SG (VPN, onprem internal, VPC endpoints, AWS test)
├── 06-onprem-instances.tf   # VPN 장비 + OnPrem Test 인스턴스
├── 07-aws-test-instances.tf # AWS 테스트 × 2 + IAM/SSM + VPC Endpoints
├── 08-post-deployment.tf    # SSM Document + Association으로 IPsec 설정 주입
├── 99-outputs.tf            # vpc id, tunnel addresses, SSM commands
├── terraform.tfvars.example # 변수 값 예시
├── scripts/
│   ├── user_data_vpn.sh       # Ubuntu + strongSwan 설치 (dpkg force-confold)
│   ├── configure_ipsec.sh     # strongSwan 설정 + IP forwarding + onprem route
│   └── user_data_aws_test.sh  # 테스트 도구 설치
├── README.md                # 본 문서
└── CLAUDE.md                # 작업자용 컨텍스트
```

---

## 🧩 사용 기술 스택

| 레이어 | 구성 요소 | 버전 |
|--------|-----------|------|
| Terraform | | ≥ 1.3 |
| AWS Provider | `hashicorp/aws` | ≥ 5.42 |
| Time Provider | `hashicorp/time` | ~> 0.11 |
| VPC Module | `terraform-aws-modules/vpc/aws` | ~> 6.0 (6.6.1) |
| Security Group Module | `terraform-aws-modules/security-group/aws` | ~> 5.0 (5.3.1) |
| VPN 장비 OS | Ubuntu 22.04 LTS (Canonical AMI) | |
| IPsec | strongSwan | 5.9.5 |
| 관리 | AWS SSM Session Manager + Run Command | |

---

## 🚀 배포 방법

### 1. 사전 요구사항
- Terraform ≥ 1.3 설치
- AWS CLI 설정 (`aws configure`)
- 사용자 계정에 EC2/VPC/VPN/SSM 권한

### 2. 변수 설정
```bash
cp terraform.tfvars.example terraform.tfvars
# 대부분의 값은 기본값 그대로 사용 가능
```

**기본값**:
- `aws_region = "ap-northeast-2"`
- `vpc_cidr = "10.0.0.0/16"` (AWS)
- `onprem_vpc_cidr = "192.168.0.0/16"`, `onprem_private_cidr = "192.168.1.0/24"`
- `key_pair_name = ""` (SSM만 사용, SSH 키 불필요)

### 3. 배포
```bash
terraform init
terraform apply
```

**배포 시간 약 10~15분**:
- VPC/Subnets/IGW: ~2분
- NAT Gateway + VPC Endpoints: ~2분
- EC2 인스턴스 4대: ~30초
- VPN Connection: **~4분** (가장 오래 걸림)
- time_sleep (user_data 완료 대기): 3분
- SSM Association (IPsec 설정 주입): ~30초

---

## ✅ 동작 검증

### AWS 콘솔에서 확인
```
VPC → Site-to-Site VPN Connections → (single-vpn-vpn)
  → Tunnel Details → 두 터널 모두 "UP"
```

### SSM 기반 Ping 테스트
```bash
# AWS 테스트 인스턴스로 접속
aws ssm start-session --target $(terraform output -json aws_test_instance_ids | jq -r '.a')

# 인스턴스 내부에서
/opt/ha-tests/test_connectivity.sh
# 또는 직접
ping 192.168.1.X   # onprem_test_private_ip (terraform output으로 확인)
```

### VPN 장비 상태 확인
```bash
aws ssm start-session --target $(terraform output -raw vpn_instance_id)
sudo ipsec status
# AWS-Tunnel-1[1]: ESTABLISHED ...
# AWS-Tunnel-2[2]: ESTABLISHED ...
```

### 실제 검증 결과 (배포 시점)
```
PING 192.168.1.58 → 0% packet loss, avg RTT 2.94ms
Tunnels: both UP
strongSwan: 2 SA ESTABLISHED
```

---

## 🔍 트러블슈팅 로그 (개발 중 실제로 겪은 이슈)

| 이슈 | 원인 | 해결 |
|------|------|------|
| AL2023의 FRR 설치 실패 | AL2023 `libjson-c`와 FRR EL9 RPM 호환 안 됨 | Ubuntu 22.04로 전환 |
| strongSwan dpkg interactive 대기 | 기존 `/etc/ipsec.conf` 감지 시 prompt | `Dpkg::Options::=--force-confold` |
| IP forwarding 비활성화 | cloud-init 중간 실패로 `sysctl --system` 스킵 | `sysctl -p /etc/sysctl.d/99-vpn.conf` + configure 스크립트에서 재확인 |
| 복호화 후 패킷 drop | VPN 장비에 `192.168.1.0/24` route 없음 | configure 스크립트에서 `ip route add` + systemd service로 영구화 |
| SSM Document `set -o pipefail` 에러 | Ubuntu의 `/bin/sh`는 dash (pipefail 미지원) | `set -eu`로 변경, 실제 로직은 `bash` 호출 |
| `aws_vpn_connection`을 `for_each`로 2개 | AWS는 동일 (CGW, VGW) 조합에 VPN Connection 1개만 허용 (idempotent) | 단일 Connection으로 단순화 |

---

## 🔐 보안 특징

- **SSH 포트(22) 열지 않음**: SG에 SSH rule 없음
- **SSH 키 파일 불필요**: SSM Session Manager 사용
- **VPN 장비는 EIP만 public**, 나머지는 Private 서브넷
- IPsec **Pre-Shared Key는 Terraform output에서 sensitive 마킹**
- AWS 기본 IPsec 파라미터: AES-128-CBC + SHA1 + DH Group 2
  - 프로덕션에서는 `aws_vpn_connection`의 tunnel options로 AES-256/SHA-256으로 강화 권장

---

## 💰 비용 (ap-northeast-2 기준)

| 리소스 | 대략 시간당 요금 | 수량 |
|--------|------------------|------|
| VPN Connection | $0.05/hr | 1 |
| NAT Gateway | $0.059/hr + 데이터 | 1 |
| VPC Interface Endpoint (SSM × 3) | $0.014/hr × 3 × 2 AZ | 6 |
| EC2 (t3.small × 1, t3.micro × 3) | 변동 | 4 |

**일일 대략 $6~8** (데이터 전송량 제외). 실습이 끝나면 반드시 `terraform destroy`.

---

## 🧹 정리
```bash
terraform destroy
```

**주의**: VPN Connection 삭제는 수 분 걸립니다. 최대 10분까지 소요될 수 있음.

---

## 📚 참고 문서

- [AWS Site-to-Site VPN User Guide](https://docs.aws.amazon.com/vpn/latest/s2svpn/)
- [strongSwan Documentation](https://docs.strongswan.org/)
- [Amazon SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [terraform-aws-modules/vpc](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest)
