# Test vs Production 비교 (요약)

| 항목 | Test | Production | 비고 |
|------|------|------------|------|
| VPC | 단일 VPC | APP/DB 분리 | Production은 VPC Peering 사용 |
| EKS 버전 | 1.32 | 1.32 | 동일 |
| 노드 그룹 | core-on (소량) | core/high/low/stateful/kafka (최소 2~3노드) | Production은 On-Demand 중심 |
| 상태 저장 | 로컬/간단 | RDS + 전용 `stateful-storage`, `kafka-storage` 노드 | Spot 미사용 |
| S3 | 기본 로그 | Airflow 로그 | Spark 체크포인트 제거 |
| VPN | 미사용 | 옵션 | 기본 비활성화 |
| NAT | 선택 | 1개 (APP VPC) | 비용 최적화 (싱글 NAT) |

## 비용 메모
- Test: t3.medium 1~2노드 + NAT 미사용 → 일 9시간 기준 약 $4~5
- Production: t3.large/m5.large 9노드 + NAT → 일 9시간 기준 약 $11 (RDS, EBS 제외)

> Jenkins/Spark 관련 모든 리소스는 제거되었습니다.

