/**
 * Stress Test - Find System Breaking Point
 *
 * Purpose: Identify the maximum RPS the system can handle before degradation
 * Method: Gradually increase load until p99 > 1s or error rate > 5%
 */

import http from 'k6/http';
import { check, group } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// ========================================
// Custom Metrics
// ========================================
const errorRate = new Rate('errors');
const latencyP99 = new Trend('latency_p99', true);
const currentRps = new Gauge('current_rps');
const requestsPerSecond = new Counter('requests_per_second');
const breakingPointRps = new Gauge('breaking_point_rps');

// Track when degradation starts
let degradationStarted = false;
let lastGoodRps = 0;

// ========================================
// Test Configuration
// ========================================
export const options = {
  scenarios: {
    stress_test: {
      executor: 'ramping-arrival-rate',
      startRate: 100,
      timeUnit: '1s',
      preAllocatedVUs: 1000,
      maxVUs: 3000,
      stages: JSON.parse(__ENV.STAGES || '[{"duration":"2m","target":600},{"duration":"2m","target":800},{"duration":"2m","target":1000},{"duration":"2m","target":1200},{"duration":"2m","target":1400},{"duration":"2m","target":1600},{"duration":"2m","target":1800},{"duration":"2m","target":2000},{"duration":"2m","target":0}]'),
    },
  },
  thresholds: {
    // These are observation thresholds, not hard failures
    http_req_duration: ['p(99)<1000'],  // p99 < 1s
    errors: ['rate<0.05'],               // Error rate < 5%
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
  console.log('STRESS TEST - Finding Breaking Point');
  console.log('='.repeat(60));
  console.log('Stages: 600 -> 800 -> 1000 -> 1200 -> 1400 -> 1600 -> 1800 -> 2000 RPS');
  console.log('Breaking criteria: p99 > 1s OR error rate > 5%');
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
  };
}

// ========================================
// Main Test Function - Mixed Workload
// ========================================
export default function (data) {
  const headers = {
    'Authorization': `Bearer ${data.token}`,
    'Content-Type': 'application/json',
  };

  const rand = Math.random() * 100;
  let res;
  let start = Date.now();

  if (rand < 50) {
    // 50% - Product Search (Read-heavy)
    res = http.get(
      `${data.baseUrl}/api/v1/products?page=0&size=20`,
      { headers, tags: { name: 'ProductSearch' } }
    );
  } else if (rand < 70) {
    // 20% - Product Detail
    res = http.get(
      `${data.baseUrl}/api/v1/products/${data.productId}`,
      { headers, tags: { name: 'ProductDetail' } }
    );
  } else if (rand < 85) {
    // 15% - Order Creation (Write-heavy, triggers Kafka)
    const payload = {
      storeId: data.storeId,
      idempotencyKey: `k6-stress-${__VU}-${__ITER}-${Date.now()}`,
      items: [{
        productId: data.productId,
        productName: 'Stress Test Product',
        quantity: 1,
        unitPrice: 10000,
      }],
    };
    res = http.post(
      `${data.baseUrl}/api/v1/orders`,
      JSON.stringify(payload),
      { headers, tags: { name: 'OrderCreate' } }
    );
  } else {
    // 15% - Order List
    res = http.get(
      `${data.baseUrl}/api/v1/orders?page=0&size=10`,
      { headers, tags: { name: 'OrderList' } }
    );
  }

  const duration = Date.now() - start;
  latencyP99.add(duration);
  requestsPerSecond.add(1);

  // Check for success
  const success = check(res, {
    'status is 2xx': (r) => r.status >= 200 && r.status < 300,
    'response time < 1s': (r) => r.timings.duration < 1000,
  });

  errorRate.add(!success);

  // Track degradation
  if (!success && !degradationStarted) {
    degradationStarted = true;
    console.log(`[DEGRADATION] Started at iteration ${__ITER}, VU ${__VU}`);
    console.log(`[DEGRADATION] Response time: ${duration}ms, Status: ${res.status}`);
  }
}

// ========================================
// Teardown - Report Breaking Point
// ========================================
export function teardown(data) {
  console.log('='.repeat(60));
  console.log('STRESS TEST COMPLETED');
  console.log('='.repeat(60));
  console.log('');
  console.log('Check the following in Grafana:');
  console.log('1. At what RPS did p99 exceed 1s?');
  console.log('2. At what RPS did error rate exceed 5%?');
  console.log('3. Which service hit resource limits first?');
  console.log('4. Did HPA trigger? How many pods were added?');
  console.log('');
  console.log('Key metrics to analyze:');
  console.log('- http_req_duration (p99)');
  console.log('- errors (rate)');
  console.log('- CPU/Memory usage per service');
  console.log('- Kafka Consumer Lag');
  console.log('- DB Connection Pool usage');
  console.log('='.repeat(60));
}
