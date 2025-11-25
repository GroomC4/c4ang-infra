FROM quay.io/strimzi/kafka:0.48.0-kafka-4.1.0

USER root:root

# Confluent Hub에서 S3 Sink Connector 다운로드 및 설치
RUN mkdir -p /opt/kafka/plugins/confluentinc-kafka-connect-s3 && \
    curl -f -sSL https://hub-downloads.confluent.io/api/plugins/confluentinc/kafka-connect-s3/versions/10.6.11/confluentinc-kafka-connect-s3-10.6.11.zip \
    -o /tmp/kafka-connect-s3.zip && \
    unzip /tmp/kafka-connect-s3.zip -d /opt/kafka/plugins/confluentinc-kafka-connect-s3 && \
    rm -f /tmp/kafka-connect-s3.zip && \
    chown -R 1001:1001 /opt/kafka/plugins

USER 1001
