# AWS 리소스 현황 (2025-12-08 백업)

Terraform 재생성 전 현재 AWS 리소스 설정값 백업

## VPC

| VPC ID | CIDR | Name | 용도 |
|--------|------|------|------|
| vpc-0f26099f532f44c82 | 10.0.0.0/16 | c4-vpc-app | EKS 사용 (메인) |
| vpc-005baa0446f0c787c | 10.1.0.0/16 | c4-vpc-db | RDS 전용 |
| vpc-02f4edcc64e7371a3 | 172.20.0.0/16 | c4-vpc-app | 미사용 (삭제 예정) |

### VPC-APP Subnets (10.0.0.0/16)
- Public: 10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
- Private: 10.0.48.0/20, 10.0.64.0/20, 10.0.80.0/20

### VPC-DB Subnets (10.1.0.0/16)
- Private: 10.1.0.0/20, 10.1.16.0/20, 10.1.32.0/20

### VPC Peering
- pcx-095c16bb098761295: vpc-0f26099f532f44c82 ↔ vpc-005baa0446f0c787c

## EKS Cluster

| 항목 | 값 |
|------|-----|
| Cluster Name | c4-cluster |
| Version | 1.32 |
| Status | ACTIVE |
| Platform Version | eks.30 |

### Node Groups

| Node Group | Instance Type | Min | Desired | Max |
|------------|--------------|-----|---------|-----|
| core-on | t3.large | 2 | 2 | 4 |
| high-traffic | t3.large | 1 | 1 | 4 |
| low-traffic | t3.medium | 2 | 2 | 4 |
| kafka-storage | m5.large | 0 | 0 | 1 |
| stateful-storage | m5.large | 0 | 0 | 1 |

## MSK (Kafka)

| 항목 | 값 |
|------|-----|
| Cluster Name | c4-kafka-m7g |
| Status | ACTIVE |
| Instance Type | kafka.m7g.large |
| Broker Count | 3 |
| Kafka Version | 3.7.x.kraft (KRaft mode) |

## ElastiCache (Redis)

| Cluster ID | Node Type | Engine | Version | Nodes |
|------------|-----------|--------|---------|-------|
| c4-cache-redis | cache.t3.micro | redis | 7.1.0 | 1 |
| c4-session-redis | cache.t3.micro | redis | 7.1.0 | 1 |

## RDS (PostgreSQL)

| Instance ID | Class | Engine | Version | Storage |
|-------------|-------|--------|---------|---------|
| c4-app-db | db.t3.micro | postgres | 17.6 | 100GB |
| c4-customer-db | db.t3.micro | postgres | 17.2 | 20GB |
| c4-order-db | db.t3.micro | postgres | 17.2 | 20GB |
| c4-payment-db | db.t3.micro | postgres | 17.2 | 20GB |
| c4-product-db | db.t3.micro | postgres | 17.2 | 20GB |
| c4-saga-db | db.t3.micro | postgres | 17.2 | 20GB |
| c4-store-db | db.t3.micro | postgres | 17.2 | 20GB |

### RDS Backup Snapshots (2025-12-08)
- c4-app-db-backup-20251208
- c4-customer-db-backup-20251208
- c4-order-db-backup-20251208
- c4-payment-db-backup-20251208
- c4-product-db-backup-20251208
- c4-saga-db-backup-20251208
- c4-store-db-backup-20251208

## 비용 예상 (5일 기준)

| 리소스 | 월 비용 | 5일 비용 |
|--------|--------|---------|
| EKS Control Plane | $73 | $12.17 |
| EC2 (5 nodes) | $300 | $49.92 |
| MSK (3 brokers) | $410 | $68.40 |
| RDS (7 instances) | $131 | $21.84 |
| ElastiCache (2) | $26 | $4.32 |
| NAT Gateway | $45 | $7.50 |
| EBS/Storage | $20 | $3.33 |
| **Total** | **~$1,005** | **~$167** |

## Terraform 재생성 시 참고사항

1. VPC CIDR은 10.0.0.0/16 (APP), 10.1.0.0/16 (DB) 유지
2. EKS 버전 1.32 지정
3. MSK는 KRaft 모드 (kafka.m7g.large)
4. RDS 비밀번호 변경 필요 (Terraform에서 새로 설정)
5. 미사용 VPC (172.20.0.0/16) 삭제 필요
