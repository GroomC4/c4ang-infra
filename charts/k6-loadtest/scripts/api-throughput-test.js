/**
 * API Throughput Test - 1,000 RPS Capacity Validation
 *
 * Purpose: Validate that the system can handle 1,000 RPS with acceptable latency
 * Target: p99 latency < 500ms, error rate < 1%
 */

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { SharedArray } from 'k6/data';

// ========================================
// Custom Metrics
// ========================================
const errorRate = new Rate('errors');
const orderLatency = new Trend('order_latency', true);
const productSearchLatency = new Trend('product_search_latency', true);
const requestsTotal = new Counter('requests_total');

// ========================================
// Test Configuration
// ========================================
export const options = {
  scenarios: {
    api_throughput: {
      executor: 'ramping-arrival-rate',
      startRate: 50,
      timeUnit: '1s',
      preAllocatedVUs: 500,
      maxVUs: 2000,
      stages: JSON.parse(__ENV.STAGES || '[{"duration":"2m","target":200},{"duration":"2m","target":400},{"duration":"2m","target":600},{"duration":"2m","target":800},{"duration":"4m","target":1000},{"duration":"2m","target":1200},{"duration":"2m","target":500},{"duration":"2m","target":0}]'),
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<300', 'p(99)<500'],
    errors: ['rate<0.01'],
    order_latency: ['p(95)<1000'],
    product_search_latency: ['p(95)<200'],
  },
};

// ========================================
// API Call Weights (Real traffic pattern)
// ========================================
const API_WEIGHTS = {
  productSearch: 40,   // 40% - Product listing/search
  productDetail: 25,   // 25% - Product detail view
  orderCreate: 15,     // 15% - Order creation (most important)
  orderStatus: 10,     // 10% - Order status check
  storeList: 5,        // 5%  - Store listing
  other: 5,            // 5%  - Other APIs
};

// ========================================
// Setup: Login and get token
// ========================================
export function setup() {
  const baseUrl = __ENV.BASE_URL || 'http://localhost:8080';
  const email = __ENV.CUSTOMER_EMAIL || 'loadtest-customer@c4ang.com';
  const password = __ENV.CUSTOMER_PASSWORD || 'LoadTest123!';

  console.log(`Setting up test with base URL: ${baseUrl}`);

  // Login to get access token
  const loginRes = http.post(
    `${baseUrl}/api/v1/auth/customer/login`,
    JSON.stringify({ email, password }),
    { headers: { 'Content-Type': 'application/json' } }
  );

  if (loginRes.status !== 200) {
    console.error(`Login failed: ${loginRes.status} - ${loginRes.body}`);
    throw new Error('Setup failed: Could not login');
  }

  const token = loginRes.json('accessToken');
  console.log('Login successful, token obtained');

  return {
    token,
    baseUrl,
    storeId: __ENV.STORE_ID,
    productId: __ENV.PRODUCT_ID,
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

  const rand = Math.random() * 100;
  let cumulative = 0;

  // Product Search (40%)
  cumulative += API_WEIGHTS.productSearch;
  if (rand < cumulative) {
    productSearch(data.baseUrl, headers);
    return;
  }

  // Product Detail (25%)
  cumulative += API_WEIGHTS.productDetail;
  if (rand < cumulative) {
    productDetail(data.baseUrl, headers, data.productId);
    return;
  }

  // Order Create (15%)
  cumulative += API_WEIGHTS.orderCreate;
  if (rand < cumulative) {
    orderCreate(data.baseUrl, headers, data.storeId, data.productId);
    return;
  }

  // Order Status (10%)
  cumulative += API_WEIGHTS.orderStatus;
  if (rand < cumulative) {
    orderStatus(data.baseUrl, headers);
    return;
  }

  // Store List (5%)
  cumulative += API_WEIGHTS.storeList;
  if (rand < cumulative) {
    storeList(data.baseUrl, headers);
    return;
  }

  // Other (5%) - Default to product search
  productSearch(data.baseUrl, headers);
}

// ========================================
// API Functions
// ========================================

function productSearch(baseUrl, headers) {
  group('Product Search', () => {
    const start = Date.now();
    const page = Math.floor(Math.random() * 5);
    const res = http.get(
      `${baseUrl}/api/v1/products?page=${page}&size=20`,
      { headers, tags: { name: 'ProductSearch' } }
    );
    productSearchLatency.add(Date.now() - start);
    requestsTotal.add(1);

    const success = check(res, {
      'product search status 200': (r) => r.status === 200,
      'product search has content': (r) => r.json('content') !== undefined,
    });
    errorRate.add(!success);
  });
}

function productDetail(baseUrl, headers, productId) {
  group('Product Detail', () => {
    const res = http.get(
      `${baseUrl}/api/v1/products/${productId}`,
      { headers, tags: { name: 'ProductDetail' } }
    );
    requestsTotal.add(1);

    const success = check(res, {
      'product detail status 200': (r) => r.status === 200,
      'product detail has id': (r) => r.json('productId') !== undefined,
    });
    errorRate.add(!success);
  });
}

function orderCreate(baseUrl, headers, storeId, productId) {
  group('Order Create', () => {
    const start = Date.now();
    const payload = {
      storeId: storeId,
      idempotencyKey: `k6-${__VU}-${__ITER}-${Date.now()}`,
      items: [{
        productId: productId,
        productName: 'Load Test Product',
        quantity: 1,
        unitPrice: 10000,
      }],
      note: 'K6 Load Test Order',
    };

    const res = http.post(
      `${baseUrl}/api/v1/orders`,
      JSON.stringify(payload),
      { headers, tags: { name: 'OrderCreate' } }
    );
    orderLatency.add(Date.now() - start);
    requestsTotal.add(1);

    const success = check(res, {
      'order created status 201': (r) => r.status === 201,
      'order has orderId': (r) => r.json('orderId') !== undefined,
    });
    errorRate.add(!success);
  });
}

function orderStatus(baseUrl, headers) {
  group('Order Status', () => {
    const res = http.get(
      `${baseUrl}/api/v1/orders?page=0&size=10`,
      { headers, tags: { name: 'OrderStatus' } }
    );
    requestsTotal.add(1);

    const success = check(res, {
      'order list status 200': (r) => r.status === 200,
    });
    errorRate.add(!success);
  });
}

function storeList(baseUrl, headers) {
  group('Store List', () => {
    const res = http.get(
      `${baseUrl}/api/v1/stores?page=0&size=10`,
      { headers, tags: { name: 'StoreList' } }
    );
    requestsTotal.add(1);

    const success = check(res, {
      'store list status 200': (r) => r.status === 200,
    });
    errorRate.add(!success);
  });
}

// ========================================
// Teardown: Print summary
// ========================================
export function teardown(data) {
  console.log('='.repeat(60));
  console.log('API Throughput Test Completed');
  console.log('='.repeat(60));
}
