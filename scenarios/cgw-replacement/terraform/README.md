# Terraform Implementation of CGW Replacement Scenario

이 폴더는 상위 [시나리오 README](../README.md)에서 **AWS CLI로 수동 실행한 동일 동작을 Terraform으로 표현**한 버전입니다.
선언적 IaC로 CGW 교체 시나리오를 재현하여, 수동 작업과 IaC 작업의 차이를 비교 학습할 수 있습니다.

---

## 🎯 이 폴더의 목적

- **부모 프로젝트(`../../../`)는 건드리지 않습니다** — 별도 state 파일, 별도 워크스페이스
- 시나리오의 Phase 1 (새 EC2/ENI/EIP/CGW 생성)을 **Terraform 리소스로 관리**
- Phase 3 (VPN Connection의 CGW 변경)은 여전히 **AWS CLI로 수행** — Terraform이 관리하는 VPN Connection은 부모 프로젝트에 있기 때문

## ⚠️ 이 Terraform의 한계 & 설계 원칙

**VPN Connection 자체는 부모 프로젝트 소유** → `modify-vpn-connection`은 Terraform으로 표현하기 어려움:

1. `aws_vpn_connection`의 `customer_gateway_id`를 바꾸면 Terraform은 **리소스 destroy + recreate**하려 함 (`ForceNew`). 이건 downtime도 더 크고 시나리오 취지와 다름.
2. 이 서브 Terraform은 **새 CGW와 새 VPN 장비만 생성**. VPN Connection 교체는 별도 단계.

→ 결론: **Terraform으로 "새 인프라 생성"까지만, CGW 교체는 CLI/수동**.

## 📁 구조

```
scenarios/cgw-replacement/terraform/
├── README.md                    # 본 문서
├── main.tf                      # 새 CGW + 새 VPN 장비 + 새 ENI/EIP
├── variables.tf                 # 부모 프로젝트 참조 변수
├── outputs.tf                   # 새 리소스 id 출력 + 수동 단계 힌트
├── providers.tf                 # Terraform / AWS provider
├── terraform.tfvars.example
└── README.md
```

## 🚀 사용법

### 1. 부모 프로젝트가 배포된 상태에서 시작

```bash
cd ../../../          # 부모 프로젝트
terraform output      # 값 확인

# 새 서브 Terraform으로
cd scenarios/cgw-replacement/terraform
cp terraform.tfvars.example terraform.tfvars
# 부모 프로젝트의 output 값을 tfvars에 복사
```

### 2. 새 인프라 생성

```bash
terraform init
terraform apply
```

생성되는 것:
- 새 CGW (`aws_customer_gateway.new`)
- 새 ENI (`aws_network_interface.new_vpn`)
- 새 EIP (`aws_eip.new_vpn`)
- 새 EC2 (`aws_instance.new_vpn`) — strongSwan이 설치된 상태

### 3. VPN Connection의 CGW 교체 (CLI)

Terraform이 output으로 명령어를 안내합니다:

```bash
terraform output -raw cutover_command | bash
```

또는 수동으로:
```bash
aws ec2 modify-vpn-connection \
  --vpn-connection-id <OLD_VPN_CONN_ID> \
  --customer-gateway-id $(terraform output -raw new_customer_gateway_id)
```

### 4. 새 장비에 strongSwan 설정 주입 + OnPrem RT 전환
상위 [README](../README.md)의 Phase 4 / Phase 5 참고.

### 5. 정리 (롤백)

```bash
# 1. 먼저 부모 프로젝트의 CGW로 VPN Connection 되돌림
aws ec2 modify-vpn-connection \
  --vpn-connection-id <OLD_VPN_CONN_ID> \
  --customer-gateway-id <OLD_CGW_ID>

# 2. OnPrem RT 구 ENI로 복귀

# 3. 이 서브 프로젝트 destroy
terraform destroy
```

## 💡 수동 CLI vs Terraform 비교

| 단계 | 수동 CLI | Terraform |
|------|----------|-----------|
| 새 CGW 생성 | `aws ec2 create-customer-gateway ...` | `resource "aws_customer_gateway" "new"` |
| 새 ENI 생성 | `aws ec2 create-network-interface ...` | `resource "aws_network_interface" "new_vpn"` |
| 새 EIP 할당+연결 | `allocate-address` + `associate-address` | `resource "aws_eip" "new_vpn"` 한 리소스로 |
| 새 EC2 launch | `aws ec2 run-instances ...` | `resource "aws_instance" "new_vpn"` |
| **VPN Connection CGW 변경** | `aws ec2 modify-vpn-connection` | **불가 (부모 소유)** → CLI 필요 |
| **OnPrem RT 변경** | `aws ec2 replace-route` | **불가 (부모 소유)** → CLI 필요 |

**IaC의 장점**: idempotent, 한번에 destroy 가능, drift 추적
**IaC의 한계**: 이미 다른 state에 있는 리소스 수정에는 CLI가 더 적합
