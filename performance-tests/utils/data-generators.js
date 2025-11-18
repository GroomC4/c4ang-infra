import { generateUUID, generateEmail, generatePhone, generateName, randomInt, randomChoice } from './helpers.js';

/**
 * 고객 데이터 생성
 */
export function generateCustomer() {
  return {
    customer_id: generateUUID(),
    email: generateEmail(),
    name: generateName(),
    phone: generatePhone(),
  };
}

/**
 * 상품 데이터 생성
 */
export function generateProduct() {
  const categories = ['전자제품', '의류', '식품', '도서', '가구', '화장품'];
  const brands = ['삼성', '애플', '나이키', '아디다스', '롯데', '풀무원'];

  return {
    product_id: generateUUID(),
    name: `테스트 상품 ${randomInt(1000, 9999)}`,
    category: randomChoice(categories),
    brand: randomChoice(brands),
    price: randomInt(10000, 500000),
    stock: randomInt(10, 1000),
  };
}

/**
 * 주문 데이터 생성
 * @param {string} customerId - 고객 ID
 * @param {Array<string>} productIds - 상품 ID 배열
 */
export function generateOrder(customerId, productIds = []) {
  const orderItems = productIds.length > 0
    ? productIds.map(pid => ({
        product_id: pid,
        quantity: randomInt(1, 5),
        price: randomInt(10000, 100000),
      }))
    : [
        {
          product_id: generateUUID(),
          quantity: randomInt(1, 3),
          price: randomInt(10000, 50000),
        },
      ];

  const totalAmount = orderItems.reduce((sum, item) => sum + item.price * item.quantity, 0);

  return {
    order_id: generateUUID(),
    customer_id: customerId,
    items: orderItems,
    total_amount: totalAmount,
  };
}

/**
 * 결제 데이터 생성
 * @param {string} orderId - 주문 ID
 * @param {number} amount - 결제 금액
 */
export function generatePayment(orderId, amount) {
  const paymentMethods = ['card', 'bank_transfer', 'kakao_pay', 'naver_pay'];

  return {
    payment_id: generateUUID(),
    order_id: orderId,
    amount: amount,
    payment_method: randomChoice(paymentMethods),
    card_number: '1234-5678-9012-3456', // 테스트용
  };
}

/**
 * 리뷰 데이터 생성
 * @param {string} productId - 상품 ID
 * @param {string} customerId - 고객 ID
 */
export function generateReview(productId, customerId) {
  const comments = [
    '정말 좋은 상품이에요!',
    '배송이 빠르고 상품 품질이 우수합니다.',
    '가격 대비 만족스러워요.',
    '다시 구매하고 싶습니다.',
    '친구에게 추천했어요.',
  ];

  return {
    review_id: generateUUID(),
    product_id: productId,
    customer_id: customerId,
    rating: randomInt(3, 5),
    comment: randomChoice(comments),
  };
}

/**
 * 검색 쿼리 생성
 */
export function generateSearchQuery() {
  const keywords = [
    '노트북',
    '스마트폰',
    '티셔츠',
    '운동화',
    '책',
    '커피',
    '의자',
    '립스틱',
    '헤드폰',
    '가방',
  ];

  return {
    keyword: randomChoice(keywords),
    page: 1,
    size: 20,
  };
}

/**
 * 실제 사용자 시나리오를 위한 데이터 세트
 */
export class UserSession {
  constructor() {
    this.customer = generateCustomer();
    this.cart = [];
    this.orders = [];
  }

  /**
   * 장바구니에 상품 추가
   * @param {string} productId - 상품 ID
   * @param {number} quantity - 수량
   */
  addToCart(productId, quantity = 1) {
    this.cart.push({
      product_id: productId,
      quantity: quantity,
      price: randomInt(10000, 100000),
    });
  }

  /**
   * 장바구니 비우기
   */
  clearCart() {
    this.cart = [];
  }

  /**
   * 주문 생성
   */
  createOrder() {
    const order = generateOrder(
      this.customer.customer_id,
      this.cart.map(item => item.product_id)
    );
    this.orders.push(order);
    return order;
  }

  /**
   * 최근 주문 가져오기
   */
  getLastOrder() {
    return this.orders[this.orders.length - 1];
  }
}

