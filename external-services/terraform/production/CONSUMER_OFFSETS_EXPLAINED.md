# `__consumer_offsets` 토픽 파티션 수가 50인 이유

## 📋 요약

`__consumer_offsets` 토픽의 파티션 수가 **50개**인 것은 **Kafka의 기본 설정값**입니다.

---

## 🔍 `__consumer_offsets` 토픽이란?

`__consumer_offsets`는 Kafka의 **내부 시스템 토픽**으로, Consumer Group의 오프셋(offset) 정보를 저장합니다.

- **목적**: Consumer Group이 어느 메시지까지 읽었는지 추적
- **특징**: Compacted 토픽 (오래된 데이터 자동 삭제)
- **자동 생성**: Kafka가 자동으로 생성하고 관리

---

## 🎯 파티션 수가 50인 이유

### 1. Kafka 기본값
- Kafka의 기본 설정값: `offsets.topic.num.partitions = 50`
- MSK Configuration에서 명시적으로 설정하지 않으면 기본값 사용

### 2. Consumer Group 분산
- Consumer Group ID의 해시값을 기반으로 파티션 선택
- 많은 Consumer Group을 효율적으로 처리하기 위해 파티션 분산 필요
- 예: Consumer Group이 100개면 평균적으로 파티션당 2개씩 분산

### 3. 성능 최적화
- 파티션이 많을수록:
  - ✅ 쓰기 성능 향상 (병렬 처리)
  - ✅ 읽기 성능 향상 (Consumer Group별 분산)
  - ✅ 브로커 간 부하 분산

### 4. 권장 사항
- **Consumer Group 수 < 50**: 파티션 수를 줄여도 됨 (예: 10-20)
- **Consumer Group 수 > 50**: 기본값 50이 적절
- **Consumer Group 수 >> 50**: 파티션 수를 늘릴 수 있음 (예: 100)

---

## ⚙️ 파티션 수 변경 방법

MSK Configuration에서 `offsets.topic.num.partitions` 설정을 추가하면 변경 가능합니다:

```hcl
# msk.tf의 server_properties에 추가
offsets.topic.num.partitions=20  # 원하는 파티션 수
```

**주의사항:**
- ⚠️ 이미 생성된 토픽의 파티션 수는 변경 불가
- ⚠️ 클러스터 재시작 후에만 적용됨
- ⚠️ 일반적으로 기본값 50이면 충분함

---

## 📊 현재 상태

현재 MSK Configuration에는 `offsets.topic.num.partitions` 설정이 없으므로:
- ✅ Kafka 기본값 **50** 사용
- ✅ 모든 Consumer Group이 50개 파티션에 분산됨
- ✅ 동기화되지 않은 복제본: **0** (정상)

---

## 💡 참고사항

### 다른 내부 토픽들
- `__consumer_offsets`: Consumer Group 오프셋 저장 (50 파티션)
- `__amazon_msk_canary`: MSK 헬스체크 토픽 (3 파티션)
- `__transaction_state`: 트랜잭션 상태 저장 (기본값: 50 파티션)

### Consumer Group과 파티션 매핑
```
Consumer Group ID → 해시 → 파티션 번호 (0-49)
예: "my-consumer-group" → 해시 → 파티션 23
```

---

## ✅ 결론

**`__consumer_offsets` 토픽의 파티션 수가 50개인 것은 정상이며, Kafka의 기본 설정값입니다.**

- 변경이 필요하지 않으면 그대로 두면 됩니다
- Consumer Group이 매우 적다면 (예: 5개 미만) 파티션 수를 줄일 수 있지만, 일반적으로는 불필요합니다
- 현재 상태는 정상이며, 모든 복제본이 동기화되어 있습니다 (Unsynced replicas: 0)

