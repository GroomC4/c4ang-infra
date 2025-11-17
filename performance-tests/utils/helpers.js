import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// 커스텀 메트릭
export const errorRate = new Rate('errors');
export const customDuration = new Trend('custom_duration');

/**
 * HTTP 응답 검증
 * @param {Response} response - k6 HTTP 응답 객체
 * @param {number} expectedStatus - 기대하는 HTTP 상태 코드
 * @param {string} endpoint - 엔드포인트 이름 (메트릭용)
 * @returns {boolean} - 성공 여부
 */
export function checkResponse(response, expectedStatus = 200, endpoint = 'default') {
  const result = check(response, {
    [`${endpoint}: status is ${expectedStatus}`]: (r) => r.status === expectedStatus,
    [`${endpoint}: response time < 1s`]: (r) => r.timings.duration < 1000,
    [`${endpoint}: has body`]: (r) => r.body && r.body.length > 0,
  });

  // 에러율 기록
  errorRate.add(!result);

  // 커스텀 응답 시간 기록
  customDuration.add(response.timings.duration, { endpoint });

  return result;
}

/**
 * 랜덤 Sleep (사용자 행동 시뮬레이션)
 * @param {number} min - 최소 초
 * @param {number} max - 최대 초
 */
export function randomSleep(min = 1, max = 3) {
  const duration = Math.random() * (max - min) + min;
  sleep(duration);
}

/**
 * UUID 생성
 * @returns {string} - UUID
 */
export function generateUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/**
 * 랜덤 정수 생성
 * @param {number} min - 최소값
 * @param {number} max - 최대값
 * @returns {number} - 랜덤 정수
 */
export function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

/**
 * 배열에서 랜덤 요소 선택
 * @param {Array} array - 배열
 * @returns {*} - 랜덤 요소
 */
export function randomChoice(array) {
  return array[Math.floor(Math.random() * array.length)];
}

/**
 * 랜덤 이메일 생성
 * @returns {string} - 이메일
 */
export function generateEmail() {
  const domains = ['gmail.com', 'naver.com', 'kakao.com', 'test.com'];
  const username = `user${randomInt(1000, 9999)}`;
  const domain = randomChoice(domains);
  return `${username}@${domain}`;
}

/**
 * 랜덤 전화번호 생성
 * @returns {string} - 전화번호
 */
export function generatePhone() {
  return `010-${randomInt(1000, 9999)}-${randomInt(1000, 9999)}`;
}

/**
 * 랜덤 이름 생성
 * @returns {string} - 이름
 */
export function generateName() {
  const firstNames = ['김', '이', '박', '최', '정', '강', '조', '윤', '장', '임'];
  const lastNames = ['민준', '서연', '하준', '지우', '서준', '지민', '도윤', '예은', '시우', '하윤'];
  return `${randomChoice(firstNames)}${randomChoice(lastNames)}`;
}

/**
 * 진행률 출력 (setup/teardown에서 사용)
 * @param {string} message - 메시지
 */
export function logInfo(message) {
  console.log(`[k6] ${new Date().toISOString()} - ${message}`);
}

/**
 * 에러 로깅
 * @param {string} message - 에러 메시지
 * @param {Error} error - 에러 객체
 */
export function logError(message, error) {
  console.error(`[k6 ERROR] ${new Date().toISOString()} - ${message}`, error);
}

/**
 * 공통 HTTP 옵션 생성
 * @param {Object} additionalHeaders - 추가 헤더
 * @returns {Object} - HTTP 옵션
 */
export function getHttpOptions(additionalHeaders = {}) {
  return {
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...additionalHeaders,
    },
    tags: {
      test_run_id: __ENV.TEST_RUN_ID || 'local',
    },
  };
}

