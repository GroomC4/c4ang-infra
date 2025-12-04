# Step 2 빠른 시작 가이드

## 🚀 빠른 실행 순서

### 1. Metrics Server 설치 (필수)

HPA가 작동하려면 Metrics Server가 필요합니다:

```bash
cd external-services/terraform/production/k8s
./install-metrics-server.sh
```

또는 수동 설치:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl get pods -n kube-system -l k8s-app=metrics-server
```

### 2. Consumer + HPA 배포

```bash
cd external-services/terraform/production/k8s
kubectl apply -f kafka-consumer-hpa.yaml

# 상태 확인
kubectl get deployment -n kafka kafka-consumer
kubectl get hpa -n kafka kafka-consumer-hpa
kubectl get pods -n kafka -l app=kafka-consumer
```

### 3. 부하 생성 및 스케일링 관찰

**터미널 1: HPA 모니터링**
```bash
watch -n 2 'kubectl get hpa -n kafka kafka-consumer-hpa && echo "" && kubectl get pods -n kafka -l app=kafka-consumer'
```

**터미널 2: 부하 생성**
```bash
cd external-services/terraform/production/k8s
kubectl apply -f kafka-producer-load.yaml

# Job 로그 확인
kubectl logs -n kafka -l app=kafka-producer-load -f
```

### 4. 결과 확인

```bash
# HPA 이벤트 확인
kubectl describe hpa -n kafka kafka-consumer-hpa | grep -A 10 "Events:"

# Pod 스케일링 확인
kubectl get pods -n kafka -l app=kafka-consumer --sort-by=.metadata.creationTimestamp
```

---

## ✅ 예상 결과

1. **초기 상태**: 1개 Pod 실행
2. **부하 생성 후**: CPU 사용률 증가 → HPA가 Pod 수 증가 (2-10개)
3. **부하 감소 후**: CPU 사용률 감소 → 60초 후 Pod 수 감소

---

## 📋 전체 가이드

자세한 내용은 `STEP2_EXECUTE.md`를 참고하세요.

