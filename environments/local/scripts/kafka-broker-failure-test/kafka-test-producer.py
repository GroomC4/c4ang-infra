#!/usr/bin/env python3
"""
Kafka Test Producer
순차적인 ID를 가진 메시지를 전송하고 에러 발생 시 자동 재시도합니다.
"""
import os
import sys
import json
import time
from datetime import datetime
from kafka import KafkaProducer, KafkaAdminClient
from kafka.errors import KafkaError

# 설정
BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')
TOPIC = os.getenv('KAFKA_TOPIC', 'broker-failure-test')
MESSAGE_INTERVAL = float(os.getenv('MESSAGE_INTERVAL_MS', '1000')) / 1000.0  # 초 단위로 변환
MAX_RETRIES = int(os.getenv('MAX_RETRIES', '5'))

# 상태 변수
message_id = 0
success_count = 0
failure_count = 0
last_report_time = time.time()

def log(message):
    """로그 출력"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
    print(f"[{timestamp}] [PRODUCER] {message}", flush=True)

def send_message(producer, msg_id):
    """메시지 전송"""
    global success_count, failure_count
    
    message = {
        "id": msg_id,
        "timestamp": str(int(time.time() * 1000)),
        "message": f"Test message #{msg_id}",
        "producer": "kafka-test-producer"
    }
    
    try:
        future = producer.send(TOPIC, key=f"key-{msg_id}", value=json.dumps(message))
        record_metadata = future.get(timeout=10)  # 10초 타임아웃
        
        success_count += 1
        log(f"✅ Sent message #{msg_id} -> partition={record_metadata.partition}, offset={record_metadata.offset}")
        return True
    except KafkaError as e:
        failure_count += 1
        log(f"❌ FAILED to send message #{msg_id}: {e}")
        return False
    except Exception as e:
        failure_count += 1
        log(f"❌ Exception sending message #{msg_id}: {e}")
        return False

def print_status_report():
    """상태 리포트 출력"""
    global last_report_time, message_id
    
    now = time.time()
    elapsed = now - last_report_time
    
    log("=" * 60)
    log("📊 STATUS REPORT")
    log(f"  Message ID: {message_id}")
    log(f"  Success: {success_count}")
    log(f"  Failure: {failure_count}")
    if message_id > 0:
        success_rate = (success_count * 100.0 / message_id)
        log(f"  Success Rate: {success_rate:.2f}%")
    log(f"  Elapsed: {elapsed:.1f}s")
    log("=" * 60)
    last_report_time = now

def main():
    global message_id
    
    log("🚀 Starting Kafka Test Producer")
    log(f"  Bootstrap Servers: {BOOTSTRAP_SERVERS}")
    log(f"  Topic: {TOPIC}")
    log(f"  Message Interval: {MESSAGE_INTERVAL * 1000:.0f}ms")
    log(f"  Max Retries: {MAX_RETRIES}")
    log("")
    
    # Producer 설정
    # 포트 포워딩을 통해 브로커 0으로 연결
    # 브로커가 내부 서비스 이름을 반환하지만, 포트 포워딩이 각 브로커 Pod에 설정되어 있으므로
    # 브로커 ID를 매핑하여 localhost로 연결하도록 설정
    bootstrap_servers_list = BOOTSTRAP_SERVERS.split(',')
    producer = KafkaProducer(
        bootstrap_servers=bootstrap_servers_list,  # 리스트로 변환
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),  # dict -> JSON string -> bytes
        key_serializer=lambda k: k.encode('utf-8') if k else None,
        acks='all',  # 모든 리플리카 확인
        retries=MAX_RETRIES,
        max_in_flight_requests_per_connection=1,  # 순서 보장
        enable_idempotence=True,  # 중복 방지 (Kafka 0.11+ 필요, 자동 감지)
        request_timeout_ms=10000,  # 10초로 단축
        delivery_timeout_ms=60000,  # 60초로 단축
        metadata_max_age_ms=5000,  # 메타데이터 캐시 5초
        api_version_auto_timeout_ms=10000,  # API 버전 자동 감지 타임아웃
        client_id='kafka-test-producer',  # 클라이언트 ID 명시
        # 브로커가 내부 서비스 이름을 반환하면 연결 실패할 수 있음
        # 포트 포워딩이 각 브로커 Pod에 설정되어 있으므로 연결 가능해야 함
        # api_version은 자동 감지 (Kafka 4.0.0은 충분히 높은 버전)
    )
    
    # 초기 연결 테스트 및 메타데이터 로드
    log("🔍 Testing Kafka connection...")
    try:
        # KafkaAdminClient를 사용하여 메타데이터 확인
        admin_client = KafkaAdminClient(
            bootstrap_servers=BOOTSTRAP_SERVERS.split(','),
            client_id='kafka-test-producer-admin',
            request_timeout_ms=10000,
        )
        # list_topics()는 timeout 파라미터를 받지 않음
        topics = admin_client.list_topics()
        admin_client.close()
        log(f"✅ Kafka connection successful! Found {len(topics)} topics.")
    except Exception as e:
        log(f"⚠️  Warning: Connection test failed: {e}")
        log("   This might be normal if Kafka is still starting up.")
        log("   Will continue and retry on first message send...")
    log("")
    
    try:
        while True:
            message_id += 1
            success = send_message(producer, message_id)
            
            if not success:
                log("⚠️  Retrying in 2 seconds...")
                time.sleep(2)
            else:
                time.sleep(MESSAGE_INTERVAL)
            
            # 30초마다 상태 리포트
            now = time.time()
            if now - last_report_time >= 30:
                print_status_report()
                
    except KeyboardInterrupt:
        log("🛑 Shutting down producer...")
        print_status_report()
    finally:
        producer.close()
        log("✅ Producer closed")

if __name__ == '__main__':
    main()

