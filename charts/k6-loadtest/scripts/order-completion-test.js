/**
 * Order Completion E2E Test - 200 Orders/sec with SAGA Tracking
 *
 * Purpose: Validate complete order flow from creation to payment completion
 * Target: SAGA completion p95 < 5s, completion rate > 99%
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// ========================================
// Custom Metrics
// ========================================
const sagaCompletionTime = new Trend('saga_completion_time', true);
const orderCreateTime = new Trend('order_create_time', true);
const ordersCreated = new Counter('orders_created');
const ordersCompleted = new Counter('orders_completed');
const ordersFailed = new Counter('orders_failed');
const ordersTimeout = new Counter('orders_timeout');
const completionRate = new Rate('completion_rate');

// ========================================
// Test Configuration
// ========================================
export const options = {
  scenarios: {
    order_completion: {
      executor: 'constant-arrival-rate',
      rate: parseInt(__ENV.TARGET_ORDERS_PER_SEC || '200'),
      timeUnit: '1s',
      duration: __ENV.DURATION || '5m',
      preAllocatedVUs: 300,
      maxVUs: 600,
    },
  },
  thresholds: {
    saga_completion_time: ['p(95)<5000'],  // SAGA completion p95 < 5s
    completion_rate: ['rate>0.99'],         // > 99% completion rate
    order_create_time: ['p(95)<1000'],      // Order creation p95 < 1s
  },
};

// ========================================
// Setup
// ========================================
export function setup() {
  const baseUrl = __ENV.BASE_URL || 'http://localhost:8080';
  const email = __ENV.CUSTOMER_EMAIL || 'loadtest-customer@c4ang.com';
  const password = __ENV.CUSTOMER_PASSWORD || 'LoadTest123!';

  console.log(`Order Completion Test - Target: ${__ENV.TARGET_ORDERS_PER_SEC || 200} orders/sec`);

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
    maxWaitTime: parseInt(__ENV.MAX_SAGA_WAIT_TIME || '30'),
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

  // Step 1: Create Order
  const orderPayload = {
    storeId: data.storeId,
    idempotencyKey: `k6-order-${__VU}-${__ITER}-${Date.now()}`,
    items: [{
      productId: data.productId,
      productName: 'Load Test Product',
      quantity: 1,
      unitPrice: 10000,
    }],
    note: 'K6 Order Completion Test',
  };

  const createStart = Date.now();
  const createRes = http.post(
    `${data.baseUrl}/api/v1/orders`,
    JSON.stringify(orderPayload),
    { headers, tags: { name: 'OrderCreate' } }
  );
  orderCreateTime.add(Date.now() - createStart);

  if (createRes.status !== 201) {
    ordersFailed.add(1);
    completionRate.add(false);
    console.error(`Order creation failed: ${createRes.status} - ${createRes.body}`);
    return;
  }

  ordersCreated.add(1);
  const orderId = createRes.json('orderId');
  const sagaStartTime = Date.now();

  // Step 2: Wait for Order Confirmation (Stock Reserved)
  let orderConfirmed = false;
  let attempts = 0;
  const maxAttempts = data.maxWaitTime;

  while (attempts < maxAttempts && !orderConfirmed) {
    sleep(1);
    attempts++;

    const statusRes = http.get(
      `${data.baseUrl}/api/v1/orders/${orderId}`,
      { headers, tags: { name: 'OrderStatusPoll' } }
    );

    if (statusRes.status === 200) {
      const status = statusRes.json('status');

      if (status === 'ORDER_CONFIRMED') {
        orderConfirmed = true;
        break;
      } else if (status === 'ORDER_FAILED') {
        ordersFailed.add(1);
        completionRate.add(false);
        console.error(`Order ${orderId} failed at confirmation stage`);
        return;
      }
    }
  }

  if (!orderConfirmed) {
    ordersTimeout.add(1);
    completionRate.add(false);
    console.error(`Order ${orderId} confirmation timeout after ${maxAttempts}s`);
    return;
  }

  // Step 3: Request Payment
  const paymentPayload = {
    paymentId: `k6-payment-${__VU}-${__ITER}-${Date.now()}`,
    paymentMethod: 'CARD',
    totalAmount: 10000,
    paymentAmount: 10000,
    discountAmount: 0,
    deliveryFee: 0,
  };

  const paymentRes = http.post(
    `${data.baseUrl}/api/v1/payments/request`,
    JSON.stringify(paymentPayload),
    { headers, tags: { name: 'PaymentRequest' } }
  );

  if (paymentRes.status !== 201 && paymentRes.status !== 200) {
    ordersFailed.add(1);
    completionRate.add(false);
    console.error(`Payment request failed: ${paymentRes.status}`);
    return;
  }

  // Step 4: Wait for Payment Completion
  let paymentCompleted = false;
  attempts = 0;

  while (attempts < maxAttempts && !paymentCompleted) {
    sleep(1);
    attempts++;

    const statusRes = http.get(
      `${data.baseUrl}/api/v1/orders/${orderId}`,
      { headers, tags: { name: 'PaymentStatusPoll' } }
    );

    if (statusRes.status === 200) {
      const status = statusRes.json('status');

      if (status === 'PAYMENT_COMPLETED' || status === 'COMPLETED') {
        paymentCompleted = true;
        sagaCompletionTime.add(Date.now() - sagaStartTime);
        ordersCompleted.add(1);
        completionRate.add(true);
        break;
      } else if (status === 'PAYMENT_FAILED' || status === 'ORDER_FAILED') {
        ordersFailed.add(1);
        completionRate.add(false);
        console.error(`Order ${orderId} failed at payment stage: ${status}`);
        return;
      }
    }
  }

  if (!paymentCompleted) {
    ordersTimeout.add(1);
    completionRate.add(false);
    console.error(`Order ${orderId} payment completion timeout`);
  }
}

// ========================================
// Teardown
// ========================================
export function teardown(data) {
  console.log('='.repeat(60));
  console.log('Order Completion Test Summary');
  console.log('='.repeat(60));
  console.log(`Target: ${__ENV.TARGET_ORDERS_PER_SEC || 200} orders/sec`);
  console.log('Check Grafana dashboard for detailed metrics');
  console.log('='.repeat(60));
}
