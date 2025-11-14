# Kafka UI Helm Chart

Kafka UI는 Apache Kafka 클러스터를 관리하고 모니터링하기 위한 웹 UI입니다.

## 개요

이 Helm Chart는 [Kafka UI](https://github.com/provectus/kafka-ui)를 Kubernetes에 배포합니다.

### 주요 기능

- **Multi-Cluster Management** - 여러 Kafka 클러스터를 한 곳에서 관리
- **Topics 관리** - 토픽 생성, 삭제, 설정 변경
- **Messages 브라우징** - JSON, Avro, Protobuf 형식 지원
- **Consumer Groups 모니터링** - 컨슈머 그룹 상태 및 lag 확인
- **Kafka Connect 관리** - Connector 상태 확인 및 관리
- **Schema Registry 지원** - Avro, JSON Schema, Protobuf 스키마 관리

## 사전 요구사항

- Kubernetes 1.19+
- Helm 3.0+
- Kafka 클러스터 (Strimzi로 관리되는 클러스터 권장)

## 설치

### 기본 설치

```bash
helm upgrade --install kafka-ui ./helm/kafka-ui -n kafka
```

### 설정 커스터마이징

```bash
helm upgrade --install kafka-ui ./helm/kafka-ui \
  -n kafka \
  -f values.yaml
```

## 설정

### 주요 설정 값

| 파라미터 | 설명 | 기본값 |
|---------|------|--------|
| `namespace` | 배포할 네임스페이스 | `kafka` |
| `image.repository` | Docker 이미지 저장소 | `provectuslabs/kafka-ui` |
| `image.tag` | 이미지 태그 | `latest` |
| `replicas` | Replica 수 | `1` |
| `kafka.clusterName` | Kafka 클러스터 이름 | `c4-kafka` |
| `kafka.bootstrapServers` | Kafka Bootstrap 서버 주소 | `c4-kafka-kafka-bootstrap:9092` |
| `service.type` | Service 타입 | `ClusterIP` |
| `service.port` | Service 포트 | `8080` |
| `ingress.enabled` | Ingress 활성화 | `false` |

### Kafka Connect 연결 설정

Kafka Connect를 연결하려면 `values.yaml`에서 다음 설정을 활성화하세요:

```yaml
env:
  KAFKA_CLUSTERS_0_KAFKACONNECT_0_NAME: "c4-kafka-connect"
  KAFKA_CLUSTERS_0_KAFKACONNECT_0_ADDRESS: "http://c4-kafka-connect-connect-api:8083"
```

### Ingress 설정

외부에서 접근하려면 Ingress를 활성화하세요:

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: kafka-ui.example.com
      paths:
        - path: /
          pathType: Prefix
```

## 접속 방법

### ClusterIP로 접속 (포트 포워딩)

```bash
kubectl port-forward -n kafka svc/kafka-ui 8080:8080
```

그 다음 브라우저에서 `http://localhost:8080` 접속

### Ingress로 접속

Ingress를 활성화한 경우, 설정한 호스트명으로 접속:
- `http://kafka-ui.example.com`

## 사용 방법

### 1. Kafka 클러스터 확인

웹 UI에 접속하면 자동으로 설정된 Kafka 클러스터가 표시됩니다.

### 2. Topics 확인

- 좌측 메뉴에서 "Topics" 클릭
- `tracking.log` 토픽 확인 가능
- 메시지 브라우징, 메시지 발행 가능

### 3. Consumer Groups 확인

- 좌측 메뉴에서 "Consumer Groups" 클릭
- 컨슈머 그룹 상태 및 lag 확인 가능

### 4. Kafka Connect 확인

Kafka Connect가 연결되어 있으면:
- 좌측 메뉴에서 "Connectors" 클릭
- `s3-sink-connector` 상태 확인 가능

## 문제 해결

### Kafka UI가 Kafka 클러스터에 연결되지 않음

```bash
# Kafka UI Pod 로그 확인
kubectl logs -n kafka -l app.kubernetes.io/name=kafka-ui

# Kafka 클러스터 연결 확인
kubectl get kafka -n kafka
kubectl get pods -n kafka -l strimzi.io/cluster=c4-kafka
```

### 포트 포워딩이 작동하지 않음

```bash
# Service 확인
kubectl get svc -n kafka kafka-ui

# Pod 상태 확인
kubectl get pods -n kafka -l app.kubernetes.io/name=kafka-ui
```

## 참고 자료

- [Kafka UI GitHub](https://github.com/provectus/kafka-ui)
- [Kafka UI 문서](https://github.com/provectus/kafka-ui#readme)
- [Kafka UI 설정 가이드](https://github.com/provectus/kafka-ui/blob/master/documentation/docs/configuration.md)

