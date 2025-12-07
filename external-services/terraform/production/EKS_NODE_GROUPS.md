# EKS 노드 그룹 상세 정보

## 📊 노드 그룹 목록 (5개)

### 1. **core-on** (코어 시스템)
- **인스턴스 타입**: `t3.large`
- **노드 수**: 최소 2개, 최대 4개, 기본 2개
- **디스크**: 40GB
- **용도**: 
  - CoreDNS, kube-proxy 등 시스템 컴포넌트
  - 공유 서비스 (모니터링, 로깅 등)
- **Taint**: 없음 (모든 Pod 스케줄링 가능)
- **비용**: On-Demand

### 2. **high-traffic** (고트래픽 워크로드)
- **인스턴스 타입**: `t3.large`
- **노드 수**: 최소 2개, 최대 4개, 기본 2개
- **디스크**: 40GB
- **용도**:
  - 높은 트래픽을 처리하는 애플리케이션
  - API 서버, 프론트엔드 서비스 등
- **Taint**: 없음
- **비용**: On-Demand

### 3. **low-traffic** (저트래픽 워크로드)
- **인스턴스 타입**: `t3.medium` (더 작은 인스턴스)
- **노드 수**: 최소 2개, 최대 4개, 기본 2개
- **디스크**: 40GB
- **용도**:
  - 낮은 트래픽을 처리하는 애플리케이션
  - 배치 작업, 백그라운드 서비스 등
- **Taint**: 없음
- **비용**: On-Demand (비용 절감)

### 4. **stateful-storage** (상태 저장 워크로드)
- **인스턴스 타입**: `m5.large`
- **노드 수**: 최소 2개, 최대 4개, 기본 2개
- **디스크**: 100GB (더 큰 디스크)
- **용도**:
  - 데이터베이스 (PostgreSQL, Redis 등)
  - 영구 스토리지가 필요한 애플리케이션
- **Taint**: `workload=stateful:NoSchedule` (전용 노드)
- **비용**: On-Demand

### 5. **kafka-storage** (Kafka 워크로드)
- **인스턴스 타입**: `m5.large`
- **노드 수**: 최소 3개, 최대 5개, 기본 3개
- **디스크**: 200GB (가장 큰 디스크)
- **용도**:
  - Kafka 브로커 (Strimzi 등)
  - 대용량 메시지 스토리지가 필요한 워크로드
- **Taint**: `workload=kafka:NoSchedule` (전용 노드)
- **비용**: On-Demand

---

## 📈 총 노드 수 예상

**기본 설정 (desired_size 기준):**
- core-on: 2개
- high-traffic: 2개
- low-traffic: 2개
- stateful-storage: 2개
- kafka-storage: 3개

**총 노드 수: 11개** (기본)

**최대 확장 시 (max_size 기준):**
- core-on: 4개
- high-traffic: 4개
- low-traffic: 4개
- stateful-storage: 4개
- kafka-storage: 5개

**총 노드 수: 21개** (최대)

---

## 💰 예상 비용 (시간당)

### 기본 설정 (11개 노드)
- core-on (t3.large × 2): ~$0.15/hour
- high-traffic (t3.large × 2): ~$0.15/hour
- low-traffic (t3.medium × 2): ~$0.08/hour
- stateful-storage (m5.large × 2): ~$0.19/hour
- kafka-storage (m5.large × 3): ~$0.29/hour

**총 노드 비용: 약 $0.86/hour (약 $620/월)**

### 추가 비용
- EKS 클러스터: $0.10/hour (약 $73/월)
- NAT Gateway: $0.045/hour + 데이터 전송 (약 $32/월)
- RDS: db.r6g.large Multi-AZ (약 $700/월)
- MSK: kafka.t3.small × 2 (약 $150/월)
- S3: 사용량 기반

**총 예상 비용: 약 $1,500-2,000/월** (모든 리소스 포함)

---

## 🎯 노드 그룹별 특징

### Taint가 있는 노드 그룹
- **stateful-storage**: `workload=stateful:NoSchedule`
  - 일반 Pod는 스케줄링 안 됨
  - `tolerations`가 있는 Pod만 스케줄링 가능
  
- **kafka-storage**: `workload=kafka:NoSchedule`
  - Kafka 전용 노드
  - 다른 워크로드와 격리

### Taint가 없는 노드 그룹
- **core-on**, **high-traffic**, **low-traffic**
  - 모든 Pod가 스케줄링 가능
  - 워크로드에 따라 자동으로 분산

---

## 🔧 노드 그룹 수정 방법

`terraform.tfvars`에서 각 노드 그룹 설정을 변경할 수 있습니다:

```hcl
# 예시: core-on 노드 그룹 수정
core_node_group = {
  instance_types = ["t3.large"]
  min_size       = 1      # 최소 노드 수
  max_size       = 3      # 최대 노드 수
  desired_size   = 1      # 기본 노드 수 (비용 절감)
  disk_size      = 40
}
```

---

## 📝 참고사항

- 모든 노드 그룹은 **On-Demand** 인스턴스 사용 (안정성 우선)
- Karpenter를 추가하면 Spot 인스턴스로 비용 절감 가능
- 각 노드 그룹은 독립적으로 스케일링됨
- Taint가 있는 노드 그룹은 전용 워크로드용

