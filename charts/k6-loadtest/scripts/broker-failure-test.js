/**
 * Broker Failure Test - Kafka Resilience Validation
 *
 * Purpose: Validate system resilience when a Kafka broker goes down
 * Target: Message loss = 0, Recovery time < 20s, URP returns to 0
 *
 * Usage: Run this test, then manually kill a broker during execution:
 *   kubectl delete pod c4-kafka-dual-role-0 -n kafka
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// ========================================
// Custom Metrics
// ========================================
const errorRate = new Rate('errors');
const orderLatency = new Trend('order_latency', true);
const ordersCreated = new Counter('orders_created');
const ordersFailed = new Counter('orders_failed');
const messagesProduced = new Counter('messages_produced');
const errorsDuringFailure = new Counter('errors_during_failure');

// Tracking for message count verification
const messageTracker = new Gauge('message_tracker');

// ========================================
// Test Configuration
// ========================================
export const options = {
  scenarios: {
    broker_failure: {
      executor: 'constant-arrival-rate',
      rate: parseInt(__ENV.TARGET_RPS || '500'),
      timeUnit: '1s',
      duration: __ENV.DURATION || '10m',
      preAllocatedVUs: 100,
      maxVUs: 300,
    },
  },
  thresholds: {
    // During broker failure, we expect some temporary errors
    // The key is that they recover quickly
    errors: ['rate<0.10'],  // Allow up to 10% errors during failure
    order_latency: ['p(95)<2000'],  // p95 < 2s (relaxed during failure)
  },
};

// ========================================
// Setup
// ========================================
export function setup() {
  const baseUrl = __ENV.BASE_URL || 'http://localhost:8080';
  const email = __ENV.CUSTOMER_EMAIL || 'loadtest-customer@c4ang.com';
  const password = __ENV.CUSTOMER_PASSWORD || 'LoadTest123!';

  console.log('='.repeat(60));
  console.log('BROKER FAILURE TEST');
  console.log('='.repeat(60));
  console.log('');
  console.log('IMPORTANT: During this test, manually kill a Kafka broker:');
  console.log('');
  console.log('  kubectl delete pod c4-kafka-dual-role-0 -n kafka');
  console.log('');
  console.log('Then observe:');
  console.log('  1. Under Replicated Partitions (URP) spike and recovery');
  console.log('  2. ISR Shrink/Expand events');
  console.log('  3. Leader Election time');
  console.log('  4. Consumer Lag changes');
  console.log('  5. Error rate during failure window');
  console.log('');
  console.log('='.repeat(60));

  // Login
  const loginRes = http.post(
    `${baseUrl}/api/v1/auth/customer/login`,
    JSON.stringify({ email, password }),
    { headers: { 'Content-Type': 'application/json' } }
  );

  if (loginRes.status !== 200) {
    throw new Error(`Login failed: ${loginRes.status}`);
  }

  return {
    token: loginRes.json('accessToken'),
    baseUrl,
    storeId: __ENV.STORE_ID,
    productId: __ENV.PRODUCT_ID,
    startTime: Date.now(),
  };
}

// ========================================
// Main Test Function
// ========================================
export default function (data) {
  const headers = {
    'Authorization': `Bearer ${data.token}`,
    'Content-Type': 'application/json',
  };

  const elapsedMinutes = Math.floor((Date.now() - data.startTime) / 60000);

  // Create order (this triggers Kafka message production)
  const start = Date.now();
  const orderPayload = {
    storeId: data.storeId,
    idempotencyKey: `k6-broker-${__VU}-${__ITER}-${Date.now()}`,
    items: [{
      productId: data.productId,
      productName: 'Broker Failure Test Product',
      quantity: 1,
      unitPrice: 10000,
    }],
    note: `Broker Failure Test - Minute ${elapsedMinutes}`,
  };

  const res = http.post(
    `${data.baseUrl}/api/v1/orders`,
    JSON.stringify(orderPayload),
    {
      headers,
      tags: { name: 'OrderCreate' },
      timeout: '10s',  // Longer timeout during broker failure
    }
  );

  const duration = Date.now() - start;
  orderLatency.add(duration);

  const success = check(res, {
    'order created': (r) => r.status === 201,
    'has orderId': (r) => r.status === 201 && r.json('orderId') !== undefined,
  });

  if (success) {
    ordersCreated.add(1);
    messagesProduced.add(1);  // At least 1 Kafka message per order
    errorRate.add(false);
  } else {
    ordersFailed.add(1);
    errorsDuringFailure.add(1);
    errorRate.add(true);

    // Log failures for analysis
    if (res.status !== 201) {
      console.log(`[FAILURE] Minute ${elapsedMinutes}: Status=${res.status}, Duration=${duration}ms`);
    }
  }

  // Update message tracker for verification
  messageTracker.add(__ITER);
}

// ========================================
// Teardown - Verification Instructions
// ========================================
export function teardown(data) {
  const totalDuration = Math.floor((Date.now() - data.startTime) / 1000);

  console.log('='.repeat(60));
  console.log('BROKER FAILURE TEST COMPLETED');
  console.log('='.repeat(60));
  console.log(`Total Duration: ${totalDuration} seconds`);
  console.log('');
  console.log('POST-TEST VERIFICATION:');
  console.log('');
  console.log('1. Message Count Verification:');
  console.log('   Compare orders_created counter with:');
  console.log('   - kafka-console-consumer --topic order.created --from-beginning | wc -l');
  console.log('');
  console.log('2. Grafana Metrics to Check:');
  console.log('   - kafka_controller_underreplicated_partitions (should return to 0)');
  console.log('   - kafka_server_replicamanager_isrshrinks_total');
  console.log('   - kafka_server_replicamanager_isrexpands_total');
  console.log('   - kafka_controller_leader_election_rate');
  console.log('   - kafka_consumergroup_lag');
  console.log('');
  console.log('3. Expected Timeline:');
  console.log('   - T+0s:    Broker killed');
  console.log('   - T+0-3s:  URP spikes, Leader Election');
  console.log('   - T+3-10s: ISR Shrink, Lag spike');
  console.log('   - T+10-20s: Recovery, Lag decreasing');
  console.log('   - T+20s+:  Normal operation resumed');
  console.log('');
  console.log('4. Document:');
  console.log('   - Exact broker kill timestamp');
  console.log('   - URP peak value and duration');
  console.log('   - Leader election time');
  console.log('   - Lag recovery time');
  console.log('   - Any message loss detected');
  console.log('='.repeat(60));
}
