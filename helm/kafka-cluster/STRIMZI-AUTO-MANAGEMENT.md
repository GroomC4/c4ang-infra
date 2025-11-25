# Strimzi Operator 자동 관리 기능 확인 및 설정 가이드

## 📋 현재 설정 상태

### ✅ 이미 구현된 자동 관리 기능

1. **StatefulSet 자동 관리**
   - ✅ Strimzi Operator가 StatefulSet을 자동으로 생성하고 관리
   - ✅ Pod 이름: `c4-kafka-kafka-pool-0`, `c4-kafka-kafka-pool-1`, `c4-kafka-kafka-pool-2`
   - ✅ 각 Pod는 고유한 ID와 PVC를 가짐

2. **노드 추가/제거 자동 관리**
   - ✅ KafkaNodePool의 `replicas` 변경 시 자동으로 Pod 추가/제거
   - ✅ Strimzi가 브로커 추가/제거를 안전하게 처리

3. **장애 자동 복구**
   - ✅ Pod가 실패하면 Kubernetes가 자동으로 재시작
   - ✅ Strimzi가 클러스터 상태를 모니터링하고 복구
   - ✅ Health Check 및 Readiness Probe 자동 설정

4. **K8s 리소스 자동 관리**
   - ✅ Service, ConfigMap, Secret 자동 생성
   - ✅ RBAC (ServiceAccount, Role, RoleBinding) 자동 설정
   - ✅ NetworkPolicy 자동 생성 (설정 시)

### ⚠️ 현재 설정의 문제점 및 개선 필요 사항

1. **Replication Factor가 너무 낮음**
   ```yaml
   # 현재 설정 (setup-eks-kafka.sh)
   default.replication.factor: 1  # ❌ 단일 복제본
   min.insync.replicas: 1          # ❌ 고가용성 없음
   ```
   - **문제**: 브로커 1개가 실패하면 데이터 손실 가능
   - **개선**: replication.factor를 3으로, min.insync.replicas를 2로 설정

2. **자동 스케일링 설정 없음**
   - 현재: KafkaNodePool의 replicas가 고정값 (3)
   - 개선: HPA (Horizontal Pod Autoscaler) 추가 필요

3. **파티션 리밸런싱 자동화**
   - Strimzi는 브로커 추가/제거 시 자동으로 리밸런싱을 처리하지만
   - Kafka 자체의 파티션 리밸런싱은 추가 설정 필요

4. **스토리지가 Ephemeral**
   ```yaml
   storage:
     type: ephemeral  # ❌ 데이터가 영구 저장되지 않음
   ```
   - **문제**: Pod 재시작 시 데이터 손실
   - **개선**: PersistentVolume 사용 권장

---

## 🔧 개선된 설정

### 1. 고가용성 설정 (권장)

`setup-eks-kafka.sh` 수정:

```yaml
spec:
  kafka:
    config:
      default.replication.factor: 3              # ✅ 3개 복제본
      min.insync.replicas: 2                     # ✅ 최소 2개 동기화
      offsets.topic.replication.factor: 3        # ✅ 오프셋 토픽도 3개 복제
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
```

### 2. 영구 스토리지 설정

```yaml
spec:
  kafka:
    storage:
      type: persistent-claim
      size: 100Gi
      deleteClaim: false
      class: gp3  # EBS 스토리지 클래스
```

### 3. 자동 스케일링 설정 (HPA)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: kafka-pool-hpa
  namespace: kafka
spec:
  scaleTargetRef:
    apiVersion: kafka.strimzi.io/v1beta2
    kind: KafkaNodePool
    name: kafka-pool
  minReplicas: 3
  maxReplicas: 6
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

**주의**: Kafka는 StatefulSet이므로 스케일링 시 주의 필요. Strimzi가 안전하게 처리하지만 점진적으로 진행됨.

### 4. 파티션 리밸런싱 자동화

#### 방법 1: Cruise Control 사용 (권장)

Strimzi는 Cruise Control을 통합하여 자동 리밸런싱을 제공합니다:

```yaml
spec:
  kafka:
    # Cruise Control 활성화
    cruiseControl:
      replicas: 1
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
        limits:
          cpu: 500m
          memory: 1Gi
```

#### 방법 2: Kafka 자동 리밸런싱 설정

```yaml
spec:
  kafka:
    config:
      # 리더 자동 선출
      auto.leader.rebalance.enable: "true"
      # 파티션 리밸런싱 간격 (밀리초)
      leader.imbalance.check.interval.seconds: "300"
      # 리밸런싱 임계값 (퍼센트)
      leader.imbalance.per.broker.percentage: "10"
```

### 5. 리소스 제한 설정

```yaml
spec:
  kafka:
    resources:
      requests:
        cpu: "1000m"
        memory: "2Gi"
      limits:
        cpu: "2000m"
        memory: "4Gi"
```

---

## 📊 Strimzi 자동 관리 기능 상세

### 1. StatefulSet 자동 관리

Strimzi Operator는 Kafka 브로커를 StatefulSet으로 배포합니다:

```bash
# StatefulSet 확인 (Strimzi가 자동 생성)
kubectl get statefulset -n kafka

# Pod 확인
kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka
```

**특징**:
- 각 Pod는 고유한 ID (0, 1, 2, ...)
- Pod 이름: `{cluster-name}-kafka-{node-pool-name}-{id}`
- PVC 자동 생성 및 관리
- Pod 삭제 시 자동으로 재생성

### 2. 노드 추가/제거 자동 처리

```bash
# 노드 추가 (replicas 증가)
kubectl patch kafkanodepool kafka-pool -n kafka --type='json' \
  -p='[{"op": "replace", "path": "/spec/replicas", "value": 5}]'

# Strimzi가 자동으로:
# 1. 새 Pod 생성
# 2. 브로커를 클러스터에 추가
# 3. 파티션 리밸런싱 (Cruise Control 사용 시)
```

### 3. 장애 자동 복구

**Pod 장애 시**:
1. Kubernetes가 Pod를 자동으로 재시작
2. Strimzi가 브로커 상태를 모니터링
3. 클러스터가 자동으로 리더 재선출
4. 복제본이 자동으로 동기화

**브로커 완전 실패 시**:
- 다른 브로커가 리더 역할 인수
- 복제본이 자동으로 재동기화
- Pod 재시작 후 자동으로 클러스터에 재조인

### 4. 파티션 리밸런싱

**브로커 추가 시**:
- Strimzi가 새 브로커를 클러스터에 안전하게 추가
- Cruise Control이 자동으로 파티션 리밸런싱 계획 수립
- 리밸런싱 실행 (자동 또는 수동 승인)

**브로커 제거 시**:
- Strimzi가 브로커를 안전하게 제거하기 전에 파티션 이동
- 데이터 손실 없이 브로커 제거

---

## 🔍 현재 설정 확인 명령어

```bash
# Kafka 클러스터 상태
kubectl get kafka c4-kafka -n kafka

# KafkaNodePool 상태
kubectl get kafkanodepool kafka-pool -n kafka

# Pod 상태
kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka

# StatefulSet (Strimzi가 자동 생성)
kubectl get statefulset -n kafka

# PVC (영구 스토리지 사용 시)
kubectl get pvc -n kafka

# 브로커 상태 확인
kubectl exec -n kafka c4-kafka-kafka-pool-0 -- \
  /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server localhost:9092
```

---

## ✅ 결론

### 현재 설정이 지원하는 자동 관리 기능

1. ✅ **StatefulSet 자동 관리**: Strimzi가 완전히 처리
2. ✅ **노드 추가/제거 자동 처리**: KafkaNodePool replicas 변경 시 자동 처리
3. ✅ **K8s 리소스 자동 관리**: Service, ConfigMap, RBAC 등 자동 생성
4. ✅ **장애 자동 복구**: Pod 재시작 및 클러스터 복구 자동 처리

### 개선이 필요한 부분

1. ⚠️ **Replication Factor**: 현재 1 → 3으로 변경 필요 (고가용성)
2. ⚠️ **스토리지**: Ephemeral → PersistentVolume 변경 권장
3. ⚠️ **자동 스케일링**: HPA 추가 고려
4. ⚠️ **파티션 리밸런싱**: Cruise Control 활성화 권장

### 파티션 리밸런싱 자동화

- ✅ **브로커 추가/제거 시**: Strimzi가 자동으로 처리 (Cruise Control 사용 시)
- ⚠️ **일반적인 리밸런싱**: Kafka 자체 설정 필요 (`auto.leader.rebalance.enable`)
- ⚠️ **최적화된 리밸런싱**: Cruise Control 활성화 필요

---

## 📝 권장 설정 파일

개선된 설정을 적용하려면 `setup-eks-kafka.sh`를 업데이트하거나 별도의 프로덕션 설정 파일을 사용하세요.

