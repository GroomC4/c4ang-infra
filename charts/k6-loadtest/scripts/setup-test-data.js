/**
 * Test Data Setup Script
 *
 * Purpose: Create all necessary test data before running load tests
 * Creates: Owner account, Store, Product (with large stock), Customer account
 *
 * Run this once before load testing:
 *   k6 run setup-test-data.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';

// ========================================
// Configuration - Run once
// ========================================
export const options = {
  vus: 1,
  iterations: 1,
};

// ========================================
// Test Data Configuration
// ========================================
const config = {
  baseUrl: __ENV.BASE_URL || 'http://localhost:8080',
  owner: {
    email: __ENV.OWNER_EMAIL || 'loadtest-owner@c4ang.com',
    password: __ENV.OWNER_PASSWORD || 'LoadTest123!',
    username: __ENV.OWNER_USERNAME || 'loadtest-owner',
    phoneNumber: '010-0000-0001',
  },
  customer: {
    email: __ENV.CUSTOMER_EMAIL || 'loadtest-customer@c4ang.com',
    password: __ENV.CUSTOMER_PASSWORD || 'LoadTest123!',
    username: __ENV.CUSTOMER_USERNAME || 'loadtest-customer',
    phoneNumber: '010-0000-0002',
    address: 'K6 Load Test Address, Seoul',
  },
  store: {
    name: 'K6 Load Test Store',
    description: 'Store created for K6 load testing',
  },
  product: {
    name: __ENV.PRODUCT_NAME || 'K6 Load Test Product',
    price: parseInt(__ENV.PRODUCT_PRICE || '10000'),
    stockQuantity: parseInt(__ENV.PRODUCT_STOCK || '1000000'),
    description: 'Product with large stock for load testing',
  },
};

// ========================================
// Main Setup Function
// ========================================
export default function () {
  const headers = { 'Content-Type': 'application/json' };
  let ownerToken = '';
  let customerToken = '';
  let ownerId = '';
  let customerId = '';
  let storeId = '';
  let productId = '';

  console.log('='.repeat(60));
  console.log('K6 LOAD TEST - DATA SETUP');
  console.log('='.repeat(60));
  console.log(`Base URL: ${config.baseUrl}`);
  console.log('');

  // ========================================
  // Step 1: Create Owner Account
  // ========================================
  console.log('[Step 1/6] Creating Owner Account...');

  // Try login first (account might already exist)
  let ownerLoginRes = http.post(
    `${config.baseUrl}/api/v1/auth/owner/login`,
    JSON.stringify({
      email: config.owner.email,
      password: config.owner.password,
    }),
    { headers }
  );

  if (ownerLoginRes.status === 200) {
    console.log('  -> Owner already exists, logged in successfully');
    ownerToken = ownerLoginRes.json('accessToken');
    ownerId = ownerLoginRes.json('userId') || 'existing';
  } else {
    // Create new owner
    const signupRes = http.post(
      `${config.baseUrl}/api/v1/auth/owner/signup`,
      JSON.stringify({
        username: config.owner.username,
        email: config.owner.email,
        password: config.owner.password,
        phoneNumber: config.owner.phoneNumber,
      }),
      { headers }
    );

    if (!check(signupRes, { 'owner signup success': (r) => r.status === 201 })) {
      console.error(`  -> Owner signup failed: ${signupRes.status} - ${signupRes.body}`);
      return;
    }

    ownerId = signupRes.json('user.id') || signupRes.json('userId');
    console.log(`  -> Owner created: ${ownerId}`);

    // Login to get token
    ownerLoginRes = http.post(
      `${config.baseUrl}/api/v1/auth/owner/login`,
      JSON.stringify({
        email: config.owner.email,
        password: config.owner.password,
      }),
      { headers }
    );

    if (!check(ownerLoginRes, { 'owner login success': (r) => r.status === 200 })) {
      console.error(`  -> Owner login failed: ${ownerLoginRes.status}`);
      return;
    }
    ownerToken = ownerLoginRes.json('accessToken');
  }

  console.log(`  -> Owner Token obtained`);
  sleep(1);

  // ========================================
  // Step 2: Create Store
  // ========================================
  console.log('[Step 2/6] Creating Store...');

  const authHeaders = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${ownerToken}`,
  };

  // Check if store already exists
  const storesRes = http.get(
    `${config.baseUrl}/api/v1/stores?page=0&size=10`,
    { headers: authHeaders }
  );

  if (storesRes.status === 200) {
    const stores = storesRes.json('content') || [];
    const existingStore = stores.find(s => s.name === config.store.name);
    if (existingStore) {
      storeId = existingStore.storeId || existingStore.id;
      console.log(`  -> Store already exists: ${storeId}`);
    }
  }

  if (!storeId) {
    const storeRes = http.post(
      `${config.baseUrl}/api/v1/stores`,
      JSON.stringify({
        name: config.store.name,
        description: config.store.description,
      }),
      { headers: authHeaders }
    );

    if (!check(storeRes, { 'store creation success': (r) => r.status === 201 })) {
      console.error(`  -> Store creation failed: ${storeRes.status} - ${storeRes.body}`);
      return;
    }

    storeId = storeRes.json('storeId') || storeRes.json('id');
    console.log(`  -> Store created: ${storeId}`);
  }

  sleep(1);

  // ========================================
  // Step 3: Create Product with Large Stock
  // ========================================
  console.log('[Step 3/6] Creating Product...');

  // Check if product already exists
  const productsRes = http.get(
    `${config.baseUrl}/api/v1/products?storeId=${storeId}&page=0&size=10`,
    { headers: authHeaders }
  );

  if (productsRes.status === 200) {
    const products = productsRes.json('content') || [];
    const existingProduct = products.find(p => p.name === config.product.name);
    if (existingProduct) {
      productId = existingProduct.productId || existingProduct.id;
      console.log(`  -> Product already exists: ${productId}`);

      // Update stock if needed
      console.log(`  -> Checking stock levels...`);
    }
  }

  if (!productId) {
    const productRes = http.post(
      `${config.baseUrl}/api/v1/products`,
      JSON.stringify({
        storeId: storeId,
        name: config.product.name,
        price: config.product.price,
        stockQuantity: config.product.stockQuantity,
        description: config.product.description,
      }),
      { headers: authHeaders }
    );

    if (!check(productRes, { 'product creation success': (r) => r.status === 201 })) {
      console.error(`  -> Product creation failed: ${productRes.status} - ${productRes.body}`);
      return;
    }

    productId = productRes.json('productId') || productRes.json('id');
    console.log(`  -> Product created: ${productId}`);
    console.log(`  -> Stock: ${config.product.stockQuantity} units`);
  }

  sleep(1);

  // ========================================
  // Step 4: Create Customer Account
  // ========================================
  console.log('[Step 4/6] Creating Customer Account...');

  // Try login first
  let customerLoginRes = http.post(
    `${config.baseUrl}/api/v1/auth/customer/login`,
    JSON.stringify({
      email: config.customer.email,
      password: config.customer.password,
    }),
    { headers }
  );

  if (customerLoginRes.status === 200) {
    console.log('  -> Customer already exists, logged in successfully');
    customerToken = customerLoginRes.json('accessToken');
    customerId = customerLoginRes.json('userId') || 'existing';
  } else {
    // Create new customer
    const signupRes = http.post(
      `${config.baseUrl}/api/v1/auth/customer/signup`,
      JSON.stringify({
        username: config.customer.username,
        email: config.customer.email,
        password: config.customer.password,
        defaultAddress: config.customer.address,
        defaultPhoneNumber: config.customer.phoneNumber,
      }),
      { headers }
    );

    if (!check(signupRes, { 'customer signup success': (r) => r.status === 201 })) {
      console.error(`  -> Customer signup failed: ${signupRes.status} - ${signupRes.body}`);
      return;
    }

    customerId = signupRes.json('userId') || signupRes.json('user.id');
    console.log(`  -> Customer created: ${customerId}`);

    // Login to get token
    customerLoginRes = http.post(
      `${config.baseUrl}/api/v1/auth/customer/login`,
      JSON.stringify({
        email: config.customer.email,
        password: config.customer.password,
      }),
      { headers }
    );

    if (!check(customerLoginRes, { 'customer login success': (r) => r.status === 200 })) {
      console.error(`  -> Customer login failed: ${customerLoginRes.status}`);
      return;
    }
    customerToken = customerLoginRes.json('accessToken');
  }

  console.log(`  -> Customer Token obtained`);
  sleep(1);

  // ========================================
  // Step 5: Verify Setup
  // ========================================
  console.log('[Step 5/6] Verifying Setup...');

  const customerHeaders = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${customerToken}`,
  };

  // Verify product is accessible
  const verifyProductRes = http.get(
    `${config.baseUrl}/api/v1/products/${productId}`,
    { headers: customerHeaders }
  );

  if (!check(verifyProductRes, { 'product accessible': (r) => r.status === 200 })) {
    console.error('  -> Product verification failed!');
    return;
  }
  console.log('  -> Product verified');

  // Verify store is accessible
  const verifyStoreRes = http.get(
    `${config.baseUrl}/api/v1/stores/${storeId}`,
    { headers: customerHeaders }
  );

  if (!check(verifyStoreRes, { 'store accessible': (r) => r.status === 200 })) {
    console.error('  -> Store verification failed!');
    return;
  }
  console.log('  -> Store verified');

  // ========================================
  // Step 6: Output Configuration
  // ========================================
  console.log('[Step 6/6] Setup Complete!');
  console.log('');
  console.log('='.repeat(60));
  console.log('TEST DATA SETUP COMPLETE');
  console.log('='.repeat(60));
  console.log('');
  console.log('Use these values for load tests:');
  console.log('');
  console.log('Environment Variables:');
  console.log(`  BASE_URL=${config.baseUrl}`);
  console.log(`  STORE_ID=${storeId}`);
  console.log(`  PRODUCT_ID=${productId}`);
  console.log(`  CUSTOMER_EMAIL=${config.customer.email}`);
  console.log(`  CUSTOMER_PASSWORD=${config.customer.password}`);
  console.log(`  OWNER_EMAIL=${config.owner.email}`);
  console.log(`  OWNER_PASSWORD=${config.owner.password}`);
  console.log('');
  console.log('Helm Values (add to values.yaml):');
  console.log('  testData:');
  console.log(`    storeId: "${storeId}"`);
  console.log(`    productId: "${productId}"`);
  console.log('');
  console.log('ConfigMap Output:');
  console.log(`  STORE_ID: ${storeId}`);
  console.log(`  PRODUCT_ID: ${productId}`);
  console.log('='.repeat(60));
}
