/**
 * Load Test - Product Service
 * 
 * 목적: 상품 서비스 부하 테스트
 * 시나리오: 상품 조회, 검색, 추천 조회
 */

import http from 'k6/http';
import { check, group } from 'k6';
import { Rate } from 'k6/metrics';
import { BASE_URL, commonHeaders, API_VERSION, commonThresholds } from '../../config/common.js';
import { loadTestScenario } from '../../config/scenarios.js';
import { checkResponse, randomSleep, logInfo } from '../../utils/helpers.js';
import { generateProduct, generateSearchQuery } from '../../utils/data-generators.js';

// 커스텀 메트릭
const productSearchErrorRate = new Rate('product_search_errors');
const recommendationErrorRate = new Rate('recommendation_errors');

export const options = {
  scenarios: {
    load: loadTestScenario,
  },
  thresholds: {
    ...commonThresholds,
    'product_search_errors': ['rate<0.02'],
    'recommendation_errors': ['rate<0.05'],
  },
};

const PRODUCT_ENDPOINT = `${BASE_URL}${API_VERSION}/products`;
const RECOMMENDATION_ENDPOINT = `${BASE_URL}${API_VERSION}/recommendations`;

export function setup() {
  logInfo('🚀 Starting Product Service Load Test');
  
  // 테스트용 상품 미리 생성
  const testProducts = [];
  for (let i = 0; i < 20; i++) {
    const product = generateProduct();
    const response = http.post(
      PRODUCT_ENDPOINT,
      JSON.stringify(product),
      { headers: commonHeaders }
    );
    
    if (response.status === 201 || response.status === 200) {
      testProducts.push(product);
    }
  }
  
  logInfo(`Created ${testProducts.length} test products`);
  return { testProducts };
}

export default function (data) {
  const { testProducts } = data;

  // 시나리오 1: 상품 목록 조회 (50% 비중)
  if (Math.random() < 0.5) {
    group('GET /products (list)', () => {
      const response = http.get(
        `${PRODUCT_ENDPOINT}?page=1&size=20`,
        {
          headers: commonHeaders,
          tags: { endpoint: 'list', service: 'product' },
        }
      );
      
      checkResponse(response, 200, 'product-list');
    });
    
    randomSleep(1, 2);
  }

  // 시나리오 2: 상품 검색 (30% 비중)
  else if (Math.random() < 0.8) {
    group('GET /products/search (search)', () => {
      const searchQuery = generateSearchQuery();
      const response = http.get(
        `${PRODUCT_ENDPOINT}/search?keyword=${searchQuery.keyword}&page=${searchQuery.page}&size=${searchQuery.size}`,
        {
          headers: commonHeaders,
          tags: { endpoint: 'search', service: 'product' },
        }
      );
      
      const success = checkResponse(response, 200, 'product-search');
      productSearchErrorRate.add(!success);
    });
    
    randomSleep(1, 3);
  }

  // 시나리오 3: 상품 상세 조회 + 추천 조회 (20% 비중)
  else {
    group('GET /products/{id} + recommendations', () => {
      if (testProducts.length > 0) {
        const randomProduct = testProducts[Math.floor(Math.random() * testProducts.length)];
        
        // 상품 상세 조회
        const productResponse = http.get(
          `${PRODUCT_ENDPOINT}/${randomProduct.product_id}`,
          {
            headers: commonHeaders,
            tags: { endpoint: 'detail', service: 'product' },
          }
        );
        
        checkResponse(productResponse, 200, 'product-detail');
        
        randomSleep(0.5, 1);
        
        // 해당 상품 추천 조회
        const recommendationResponse = http.get(
          `${RECOMMENDATION_ENDPOINT}/${randomProduct.product_id}`,
          {
            headers: commonHeaders,
            tags: { endpoint: 'recommendation', service: 'recommendation' },
          }
        );
        
        const success = check(recommendationResponse, {
          'recommendation: status is 200 or 404': (r) => r.status === 200 || r.status === 404,
        });
        recommendationErrorRate.add(!success);
      }
    });
    
    randomSleep(2, 4);
  }
}

export function teardown(data) {
  logInfo('✅ Product Service Load Test Completed');
}

