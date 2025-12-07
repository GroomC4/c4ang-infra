# 트러블슈팅: 고아(Orphan) NLB 정리 (2025-12-08)

## 개요
- **문제**: AWS NLB 9개가 존재하나 실제 사용되는 것이 없음
- **원인**: Kubernetes Service 삭제 시 AWS NLB가 자동 정리되지 않음
- **영향**: 불필요한 비용 발생

---

## Before (현재 상태)

### AWS NLB 목록 (9개)
| NLB ID | K8s Service Tag | 상태 |
|--------|-----------------|------|
| afd0c5cbd80e742c09f037ae94330420 | monitoring/prometheus | **고아** |
| a4c5fe0350a274db2a031bfef7a5cea8 | monitoring/grafana | **고아** |
| a1b79e3326b1b4df59773bf618b1197b | monitoring/grafana | **고아** |
| a1c848443fb2940c2b32741ccfc26da6 | monitoring/grafana | **고아** |
| a382f6cb543564c79b254e967dd5999b | monitoring/prometheus | **고아** |
| a4d355492a5fa414ca1da1a66ab6f34c | monitoring/prometheus | **고아** |
| afca9f80af4b3434ebba3610e44c3086 | monitoring/prometheus | **고아** |
| aa13f5b2b086e4c4fbfaf96084cf3f35 | monitoring/grafana | **고아** |
| a05e02ad998af4856afff264cc01a852 | monitoring/prometheus | **고아** |

### 현재 Kubernetes Service 상태
```
$ kubectl get svc -n monitoring

NAME                 TYPE        CLUSTER-IP       PORT(S)
grafana              ClusterIP   172.20.89.114    3000/TCP
prometheus           ClusterIP   172.20.189.44    9090/TCP
loki                 ClusterIP   172.20.105.116   3100/TCP
tempo                ClusterIP   172.20.205.181   3200/TCP
```

**결론**: 모든 monitoring 서비스가 **ClusterIP** 타입 → LoadBalancer가 필요 없음

### 비용 영향
| 항목 | 수량 | 시간당 비용 | 5일 비용 |
|------|------|------------|----------|
| NLB | 9개 | $0.027 × 9 = $0.243 | **$29.16** |

---

## 분석 결과

### 문제 발생 원인

1. **과거 배포 이력**: Grafana/Prometheus를 `LoadBalancer` 타입으로 여러 차례 배포
2. **서비스 타입 변경**: 이후 `ClusterIP`로 변경하여 재배포
3. **NLB 미삭제**: AWS Load Balancer Controller가 기존 NLB를 정리하지 못함

### 고아 NLB가 발생하는 일반적 원인

| 원인 | 설명 |
|------|------|
| Service 강제 삭제 | `kubectl delete svc --force` 사용 시 finalizer 미실행 |
| Controller 장애 | AWS Load Balancer Controller Pod 문제로 삭제 이벤트 미처리 |
| 네임스페이스 삭제 | 네임스페이스 전체 삭제 시 리소스 정리 순서 문제 |
| 타입 변경 | LoadBalancer → ClusterIP 변경 시 기존 NLB 미삭제 |

### NLB 생성 시점 추정

AWS 태그에서 Kubernetes 서비스 이름(`monitoring/grafana`, `monitoring/prometheus`)이 확인되므로, 과거 monitoring 스택 배포 시 Service를 `type: LoadBalancer`로 설정했던 것으로 추정됩니다.

---

## 변경 계획

### 삭제 대상
모든 9개 NLB 삭제 (현재 사용 중인 K8s Service 없음)

```bash
# 삭제 명령어
aws elbv2 delete-load-balancer --load-balancer-arn <ARN>
```

### 삭제 순서
1. Target Group 연결 확인
2. NLB 삭제
3. 연결된 Target Group 삭제 (있을 경우)
4. Security Group 정리 (필요시)

### 주의사항
- 삭제 전 실제로 트래픽이 없는지 최종 확인
- 삭제 후 서비스 정상 동작 확인

---

## After (예상)

### 삭제 후 상태
| 항목 | Before | After |
|------|--------|-------|
| NLB 수 | 9개 | **0개** |
| NLB 비용 (5일) | $29.16 | **$0** |

### 절감 효과
- **5일 절감액**: $29.16 (약 ₩40,800)
- 월간 환산: ~$175 (약 ₩245,000)

### 서비스 영향
- **영향 없음**: 현재 모든 monitoring 서비스는 ClusterIP 타입
- Grafana 접근: `kubectl port-forward` 또는 Ingress 사용

---

## 실행 내역

### 삭제 명령어
```bash
# 모든 고아 NLB 삭제
aws elbv2 delete-load-balancer --load-balancer-arn arn:aws:elasticloadbalancing:ap-northeast-2:963403601423:loadbalancer/net/afd0c5cbd80e742c09f037ae94330420/08013de59cacaba8
aws elbv2 delete-load-balancer --load-balancer-arn arn:aws:elasticloadbalancing:ap-northeast-2:963403601423:loadbalancer/net/a4c5fe0350a274db2a031bfef7a5cea8/242897230410541b
aws elbv2 delete-load-balancer --load-balancer-arn arn:aws:elasticloadbalancing:ap-northeast-2:963403601423:loadbalancer/net/a1b79e3326b1b4df59773bf618b1197b/3462764a989abdbf
aws elbv2 delete-load-balancer --load-balancer-arn arn:aws:elasticloadbalancing:ap-northeast-2:963403601423:loadbalancer/net/a1c848443fb2940c2b32741ccfc26da6/6ccbcda8b8f7a44a
aws elbv2 delete-load-balancer --load-balancer-arn arn:aws:elasticloadbalancing:ap-northeast-2:963403601423:loadbalancer/net/a382f6cb543564c79b254e967dd5999b/769305b1bcf67d81
aws elbv2 delete-load-balancer --load-balancer-arn arn:aws:elasticloadbalancing:ap-northeast-2:963403601423:loadbalancer/net/a4d355492a5fa414ca1da1a66ab6f34c/8845cdc46c1cb2c4
aws elbv2 delete-load-balancer --load-balancer-arn arn:aws:elasticloadbalancing:ap-northeast-2:963403601423:loadbalancer/net/afca9f80af4b3434ebba3610e44c3086/89458d7fc794e8b9
aws elbv2 delete-load-balancer --load-balancer-arn arn:aws:elasticloadbalancing:ap-northeast-2:963403601423:loadbalancer/net/aa13f5b2b086e4c4fbfaf96084cf3f35/b536b37c70d9759d
aws elbv2 delete-load-balancer --load-balancer-arn arn:aws:elasticloadbalancing:ap-northeast-2:963403601423:loadbalancer/net/a05e02ad998af4856afff264cc01a852/ce2a8cc26aef8e91
```

### 실행 결과
- [ ] 삭제 완료
- [ ] 서비스 정상 확인

---

## 재발 방지 대책

### 1. Service 삭제 시 주의사항
```bash
# 올바른 삭제 방법 (finalizer 실행 대기)
kubectl delete svc <service-name> -n <namespace>

# 잘못된 방법 (NLB 고아 발생 가능)
kubectl delete svc <service-name> --force --grace-period=0
```

### 2. 정기 점검 스크립트
```bash
# 고아 NLB 탐지 스크립트
#!/bin/bash
echo "=== Checking for orphan NLBs ==="

# K8s LoadBalancer 서비스 목록
K8S_LBS=$(kubectl get svc -A -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

# AWS NLB 목록
AWS_NLBS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?Type==`network`].DNSName' --output text)

# 비교하여 고아 NLB 찾기
for nlb in $AWS_NLBS; do
  if ! echo "$K8S_LBS" | grep -q "$nlb"; then
    echo "Potential orphan NLB: $nlb"
  fi
done
```

### 3. AWS Load Balancer Controller 모니터링
- Controller Pod 상태 정기 확인
- 로그에서 삭제 실패 이벤트 모니터링

---

## 비고
- 문서 작성일: 2025-12-08
- 작성자: Claude Code
- 관련 문서: [cost-optimization-2025-12-08.md](./cost-optimization-2025-12-08.md)
