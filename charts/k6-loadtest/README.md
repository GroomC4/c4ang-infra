# K6 Load Test Chart for C4ang

Helm chart for running K6 load tests against C4ang MSA system on EKS.

## Test Scenarios

| Scenario | Target | Duration | Purpose |
|----------|--------|----------|---------|
| API Throughput | 1,000 RPS | 18min | Validate capacity-planning goals |
| Order Completion | 200 orders/sec | 5min | E2E SAGA flow validation |
| Stress Test | 600→2000 RPS | 20min | Find breaking point |
| Broker Failure | 500 RPS | 10min | Kafka resilience test |

## Prerequisites

1. EKS cluster with services deployed
2. Istio Gateway configured
3. Grafana dashboards for monitoring

## Installation

### Step 1: Install the chart (creates namespace and setup job)

```bash
# Navigate to infra repo
cd /path/to/c4ang-infra

# Install chart - this will run the setup job automatically
helm install k6-loadtest ./charts/k6-loadtest \
  --namespace loadtest \
  --create-namespace
```

### Step 2: Wait for setup job to complete

```bash
# Watch setup job
kubectl logs -f job/k6-loadtest-setup -n loadtest

# Get the STORE_ID and PRODUCT_ID from the output
# Then upgrade the release with these values
```

### Step 3: Update values with test data IDs

```bash
helm upgrade k6-loadtest ./charts/k6-loadtest \
  --namespace loadtest \
  --set testData.storeId="<STORE_ID_FROM_SETUP>" \
  --set testData.productId="<PRODUCT_ID_FROM_SETUP>"
```

## Running Tests

### Option A: Run individual test jobs

```bash
# 1. API Throughput Test (1,000 RPS validation)
kubectl create job k6-api-test --from=job/k6-loadtest-api-throughput -n loadtest

# Watch progress
kubectl logs -f job/k6-api-test -n loadtest

# 2. Order Completion Test (200 orders/sec)
kubectl create job k6-order-test --from=job/k6-loadtest-order-completion -n loadtest

# 3. Stress Test (find breaking point)
kubectl create job k6-stress-test --from=job/k6-loadtest-stress -n loadtest

# 4. Broker Failure Test
kubectl create job k6-broker-test --from=job/k6-loadtest-broker-failure -n loadtest
```

### Option B: Run with custom parameters

```bash
# Run API test with custom RPS target
kubectl run k6-custom-test \
  --image=grafana/k6:0.50.0 \
  --restart=Never \
  --env="BASE_URL=http://ecommerce-gateway.ecommerce.svc.cluster.local" \
  --env="STORE_ID=<your-store-id>" \
  --env="PRODUCT_ID=<your-product-id>" \
  --env="CUSTOMER_EMAIL=loadtest-customer@c4ang.com" \
  --env="CUSTOMER_PASSWORD=LoadTest123!" \
  -n loadtest \
  -- k6 run /scripts/api-throughput-test.js
```

## Test Scenarios Detail

### 1. API Throughput Test (1,000 RPS)

**Purpose**: Validate system can handle 1,000 RPS with acceptable latency

**Load Profile**:
```
RPS: 200 → 400 → 600 → 800 → 1000 (4min hold) → 1200 → 500 → 0
```

**Pass Criteria**:
- p95 latency < 300ms
- p99 latency < 500ms
- Error rate < 1%

**What it tests**:
- 40% Product Search
- 25% Product Detail
- 15% Order Creation
- 10% Order Status
- 10% Store List

### 2. Order Completion Test (200 orders/sec)

**Purpose**: Validate E2E order flow with SAGA completion

**Flow**:
```
Order Create → Stock Reserved → Payment Request → Payment Complete
```

**Pass Criteria**:
- SAGA completion p95 < 5s
- Completion rate > 99%

### 3. Stress Test

**Purpose**: Find system breaking point

**Load Profile**:
```
RPS: 600 → 800 → 1000 → 1200 → 1400 → 1600 → 1800 → 2000
```

**Breaking Point Indicators**:
- p99 latency > 1s
- Error rate > 5%

### 4. Broker Failure Test

**Purpose**: Validate Kafka resilience

**Procedure**:
1. Start test (500 RPS load)
2. After 2min, kill broker: `kubectl delete pod c4-kafka-dual-role-0 -n kafka`
3. Observe recovery metrics
4. Wait for auto-recovery

**Pass Criteria**:
- Message loss = 0%
- URP returns to 0 within 20s
- Lag recovers within 30s

## Monitoring

### Grafana Dashboards

During tests, monitor these dashboards:

1. **kafka-lag-dashboard**: Consumer lag per group
2. **kafka-broker-failure-test**: URP, ISR, Leader Election
3. **Service dashboards**: CPU, Memory, Pod count

### Key Metrics

| Metric | Location | Alert Threshold |
|--------|----------|-----------------|
| http_req_duration | k6 output | p99 > 500ms |
| errors | k6 output | rate > 1% |
| kafka_consumergroup_lag | Grafana | > 2000 |
| CPU usage | Grafana | > 80% |

## Cleanup

```bash
# Delete all test jobs
kubectl delete jobs -l app.kubernetes.io/name=k6-loadtest -n loadtest

# Uninstall chart
helm uninstall k6-loadtest -n loadtest

# Delete namespace
kubectl delete namespace loadtest
```

## Customization

### Custom test parameters

Edit `values.yaml` or use `--set`:

```bash
helm upgrade k6-loadtest ./charts/k6-loadtest \
  --set scenarios.apiThroughput.targetRps=500 \
  --set scenarios.orderCompletion.targetOrdersPerSec=100
```

### Custom test scripts

Mount custom scripts via ConfigMap:

```bash
kubectl create configmap custom-scripts \
  --from-file=my-test.js \
  -n loadtest
```

## Troubleshooting

### Test fails to start

```bash
# Check pod logs
kubectl describe pod -l k6-test -n loadtest

# Check secret
kubectl get secret k6-loadtest-credentials -n loadtest -o yaml
```

### High error rate

1. Check service pods: `kubectl get pods -n ecommerce`
2. Check HPA: `kubectl get hpa -n ecommerce`
3. Check DB connections in Grafana
4. Check Kafka Consumer Lag

### Broker failure test doesn't recover

1. Check broker pods: `kubectl get pods -n kafka`
2. Check partition status: `kubectl exec -it c4-kafka-dual-role-1 -n kafka -- kafka-topics.sh --describe --topic order.created`
