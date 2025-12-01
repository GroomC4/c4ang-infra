# 빠른 시작 가이드

## 1. Consumer 실행
```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local/scripts/kafka-broker-failure-test
./run-consumer.sh
```

## 2. Producer 실행 (새 터미널)
```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local/scripts/kafka-broker-failure-test
./run-producer.sh
```

## 3. Grafana 대시보드 확인 (새 터미널)
```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local
export KUBECONFIG=$(pwd)/kubeconfig/config
kubectl port-forward -n monitoring svc/grafana 3000:3000
```
브라우저: http://localhost:3000

## 4. 브로커 강제 삭제 (새 터미널)
```bash
cd /Users/sanga/Desktop/c4/code/c4ang-infra/environments/local
export KUBECONFIG=$(pwd)/kubeconfig/config
kubectl delete pod -n kafka $(kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka -o jsonpath='{.items[0].metadata.name}') --force --grace-period=0
```

## 5. 관찰
- Producer 로그: 에러 → 재시도 → 정상 전송 재개
- Consumer 로그: 메시지 중단 → 재개 → Gap/중복 체크
- Grafana: Broker Status, Messages In/sec, Consumer Lag 변화

자세한 내용은 `EXECUTION_ORDER.md` 참조
