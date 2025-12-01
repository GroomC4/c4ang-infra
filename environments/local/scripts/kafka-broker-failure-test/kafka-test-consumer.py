#!/usr/bin/env python3
"""
Kafka Test Consumer
메시지를 읽으면서 ID 연속성을 체크하고 상태를 출력합니다.
"""
import os
import sys
import json
import time
import traceback
from datetime import datetime
from kafka import KafkaConsumer
from kafka.errors import KafkaError

# 설정
BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')
TOPIC = os.getenv('KAFKA_TOPIC', 'broker-failure-test')
GROUP_ID = os.getenv('CONSUMER_GROUP_ID', 'broker-failure-test-group')
REPORT_INTERVAL = int(os.getenv('REPORT_INTERVAL_SEC', '5'))

# 상태 변수
expected_id = 1
received_count = 0
duplicate_count = 0
gap_count = 0
last_received_ids = set()
last_report_time = time.time()
last_message_time = time.time()

def log(message):
    """로그 출력"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
    print(f"[{timestamp}] [CONSUMER] {message}", flush=True)

def check_message_id(msg_id, record):
    """메시지 ID 연속성 체크"""
    global expected_id, received_count, duplicate_count, gap_count, last_received_ids, last_message_time
    
    received_count += 1
    last_message_time = time.time()
    
    # 중복 체크
    if msg_id in last_received_ids:
        duplicate_count += 1
        log(f"⚠️  DUPLICATE message detected! ID: {msg_id}, partition={record.partition}, offset={record.offset}")
    else:
        last_received_ids.add(msg_id)
        # 최근 1000개만 유지
        if len(last_received_ids) > 1000:
            last_received_ids.remove(min(last_received_ids))
    
    # 연속성 체크
    if msg_id > expected_id:
        gap = msg_id - expected_id
        gap_count += gap
        log(f"⚠️  GAP detected! Expected: {expected_id}, Received: {msg_id} (Gap: {gap} messages)")
        expected_id = msg_id + 1
    elif msg_id == expected_id:
        # 정상 순서
        expected_id += 1
    else:
        # 이전 메시지 (중복이거나 재처리)
        if msg_id not in last_received_ids:
            log(f"⚠️  Out-of-order message! Expected: {expected_id}, Received: {msg_id}")

def print_status_report():
    """상태 리포트 출력"""
    global last_report_time, last_message_time
    
    now = time.time()
    elapsed = now - last_report_time
    time_since_last_message = now - last_message_time
    
    log("=" * 60)
    log("📊 STATUS REPORT")
    log(f"  Expected Next ID: {expected_id}")
    log(f"  Received: {received_count}")
    log(f"  Duplicates: {duplicate_count}")
    log(f"  Gaps: {gap_count} messages")
    if received_count > 0:
        duplicate_rate = (duplicate_count * 100.0 / received_count)
        log(f"  Duplicate Rate: {duplicate_rate:.2f}%")
    log(f"  Time Since Last Message: {time_since_last_message:.1f}s")
    log(f"  Elapsed: {elapsed:.1f}s")
    log("=" * 60)
    last_report_time = now

def main():
    global last_message_time
    
    log("🚀 Starting Kafka Test Consumer")
    log(f"  Bootstrap Servers: {BOOTSTRAP_SERVERS}")
    log(f"  Topic: {TOPIC}")
    log(f"  Consumer Group: {GROUP_ID}")
    log(f"  Report Interval: {REPORT_INTERVAL}s")
    log("")
    
    # Consumer 설정
    consumer = KafkaConsumer(
        TOPIC,
        bootstrap_servers=BOOTSTRAP_SERVERS.split(','),  # 리스트로 변환
        group_id=GROUP_ID,
        auto_offset_reset='earliest',  # 처음부터 읽기
        enable_auto_commit=False,  # 수동 커밋
        value_deserializer=lambda m: m.decode('utf-8'),
        consumer_timeout_ms=5000,  # 5초 타임아웃 (더 길게)
        api_version_auto_timeout_ms=10000,  # API 버전 자동 감지 타임아웃
        client_id='kafka-test-consumer',  # 클라이언트 ID 명시
    )
    
    log("✅ Subscribed to topic: " + TOPIC)
    
    try:
        last_report_time = time.time()
        
        while True:
            try:
                # poll 타임아웃을 더 길게 설정하여 메시지 수신 기회 증가
                message_pack = consumer.poll(timeout_ms=5000)
                
                if not message_pack:
                    time_since_last_message = time.time() - last_message_time
                    if time_since_last_message > 10:
                        log(f"⏳ No messages received for {time_since_last_message:.1f}s...")
                        # Consumer 상태 확인
                        try:
                            partitions = consumer.assignment()
                            if partitions:
                                log(f"  Assigned partitions: {partitions}")
                            else:
                                log("  ⚠️  No partitions assigned!")
                        except Exception as e:
                            log(f"  Error checking partitions: {e}")
                else:
                    last_message_time = time.time()  # 메시지 수신 시간 업데이트
                    for topic_partition, messages in message_pack.items():
                        log(f"📦 Received {len(messages)} messages from {topic_partition}")
                        for record in messages:
                            try:
                                # value_deserializer가 이미 문자열로 디코딩했으므로 json.loads() 사용
                                raw_value = record.value
                                
                                # 타입 확인 및 변환
                                if isinstance(raw_value, bytes):
                                    raw_value = raw_value.decode('utf-8')
                                elif isinstance(raw_value, dict):
                                    message_data = raw_value
                                    msg_id = message_data.get('id')
                                    if msg_id is None:
                                        log(f"⚠️  Message has no 'id' field: {message_data}")
                                        continue
                                    log(f"📨 Received message #{msg_id} -> partition={record.partition}, offset={record.offset}")
                                    check_message_id(msg_id, record)
                                    continue
                                
                                # 문자열인 경우 JSON 파싱
                                if isinstance(raw_value, str):
                                    # 이중 인코딩 체크: 문자열이 JSON 문자열로 감싸져 있는지 확인
                                    if raw_value.startswith('"') and raw_value.endswith('"'):
                                        # 이중 인코딩된 경우: "\"{...}\"" -> "{...}"
                                        try:
                                            raw_value = json.loads(raw_value)
                                        except json.JSONDecodeError:
                                            pass
                                    
                                    # JSON 파싱
                                    message_data = json.loads(raw_value)
                                    
                                    # message_data가 여전히 문자열인지 확인
                                    if isinstance(message_data, str):
                                        log(f"⚠️  Warning: message_data is still a string after json.loads()")
                                        log(f"  Raw value: {raw_value}")
                                        # 한 번 더 파싱 시도
                                        message_data = json.loads(message_data)
                                    
                                    msg_id = message_data.get('id')
                                    
                                    if msg_id is None:
                                        log(f"⚠️  Message has no 'id' field: {message_data}")
                                        continue
                                    
                                    log(f"📨 Received message #{msg_id} -> partition={record.partition}, offset={record.offset}")
                                    check_message_id(msg_id, record)
                                else:
                                    log(f"⚠️  Unexpected value type: {type(raw_value)}")
                                    log(f"  Value: {raw_value}")
                                    
                            except json.JSONDecodeError as e:
                                log(f"❌ JSON decode error: {e}")
                                log(f"  Raw value: {record.value}")
                                log(f"  Type: {type(record.value)}")
                            except Exception as e:
                                log(f"❌ Error parsing message: {e}")
                                log(f"  Raw value: {record.value}")
                                log(f"  Type: {type(record.value)}")
                                log(f"  Traceback: {traceback.format_exc()}")
                    
                    # 수동 커밋
                    try:
                        consumer.commit()
                        log("✅ Offsets committed")
                    except Exception as e:
                        log(f"⚠️  Failed to commit offsets: {e}")
                
                # 주기적 리포트
                now = time.time()
                if now - last_report_time >= REPORT_INTERVAL:
                    print_status_report()
                    last_report_time = now
                    
            except KafkaError as e:
                log(f"❌ Kafka error: {e}")
                time.sleep(2)
            except Exception as e:
                log(f"❌ Error: {e}")
                time.sleep(2)
                
    except KeyboardInterrupt:
        log("🛑 Shutting down consumer...")
        print_status_report()
    finally:
        consumer.close()
        log("✅ Consumer closed")

if __name__ == '__main__':
    main()

