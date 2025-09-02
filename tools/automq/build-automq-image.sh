#!/bin/bash

# AutoMQ Strimzi Build Script
# Usage: build-automq-strimzi.sh <AUTOMQ_VERSION> <AUTOMQ_URL> <KAFKA_VERSION> <DOCKER_ORG> <PROJECT_NAME>

set -e

ROOT_DIR=$(pwd)

if [ $# -ne 5 ]; then
    exit 1
fi

AUTOMQ_VERSION="$1"
AUTOMQ_URL="$2"
KAFKA_VERSION="$3"
DOCKER_ORG="$4"
PROJECT_NAME="$5"

export DOCKER_ORG="$DOCKER_ORG"
export DOCKER_TAG="${AUTOMQ_VERSION}-strimzi"
export PROJECT_NAME="$PROJECT_NAME"

KAFKA_URL="https://archive\.apache\.org/dist/kafka/${KAFKA_VERSION}/kafka_2\.13-${KAFKA_VERSION}\.tgz"

echo "Updating Strimzi Configuration..."

AUTOMQ_CHECKSUM=$(curl -L "$AUTOMQ_URL" | sha512sum | cut -d' ' -f1)
ORIGINAL_CHECKSUM=$(grep -A 4 "version: ${KAFKA_VERSION}" kafka-versions.yaml | grep "checksum:" | awk '{print $2}')
# replace kafka url to automq
sed -i "s|${KAFKA_URL}|${AUTOMQ_URL}|" kafka-versions.yaml
sed -i "s|${ORIGINAL_CHECKSUM}|${AUTOMQ_CHECKSUM}|" kafka-versions.yaml
# set 3.9.0 as default
sed -i '/- version: 3\.9\.0/,/^- version:/ { /default: false/c\  default: true
}' kafka-versions.yaml
sed -i '/- version: 4\.0\.0/,$ { s/default: true/default: false/; }' kafka-versions.yaml
# exclude other versions to speed up building
sed -i '/- version: 3\.9\.1/,/^- version:/ { s/supported: true/supported: false/; }' kafka-versions.yaml
sed -i '/- version: 4\.0\.0/,$ { s/supported: true/supported: false/; }' kafka-versions.yaml

echo "Preparing Strimzi Image Environment..."

mvn clean install -DskipTests
make -C docker-images/artifacts java_build
cd ./docker-images/artifacts/binaries/kafka/archives/
mv "automq-${AUTOMQ_VERSION}_kafka-${KAFKA_VERSION}.tgz" "kafka_2.13-${KAFKA_VERSION}.tgz"
mv "automq-${AUTOMQ_VERSION}_kafka-${KAFKA_VERSION}.tgz.sha512" "kafka_2.13-${KAFKA_VERSION}.tgz.sha512"
cd ..

IGNORE_LIST="gson-2.9.0.jar
gson-2.10.1.jar
guava-32.0.1-jre.jar
guava-32.1.3-jre.jar
jackson-annotations-2.16.2.jar
jackson-annotations-2.17.1.jar
jackson-core-2.16.2.jar
jackson-core-2.17.1.jar
jackson-databind-2.16.2.jar
jackson-databind-2.17.1.jar
jackson-dataformat-yaml-2.16.2.jar
jackson-dataformat-yaml-2.17.1.jar
opentelemetry-api-1.32.0.jar
opentelemetry-api-1.40.0.jar
opentelemetry-exporter-common-1.34.1.jar
opentelemetry-exporter-common-1.40.0.jar
opentelemetry-exporter-otlp-common-1.34.1.jar
opentelemetry-exporter-otlp-common-1.40.0.jar
opentelemetry-exporter-otlp-1.34.1.jar
opentelemetry-exporter-otlp-1.40.0.jar
opentelemetry-instrumentation-api-1.32.0.jar
opentelemetry-instrumentation-api-2.6.0.jar
opentelemetry-sdk-common-1.34.1.jar
opentelemetry-sdk-common-1.40.0.jar
opentelemetry-sdk-extension-autoconfigure-spi-1.34.1.jar
opentelemetry-sdk-extension-autoconfigure-spi-1.40.0.jar
opentelemetry-sdk-logs-1.34.1.jar
opentelemetry-sdk-logs-1.40.0.jar
opentelemetry-sdk-metrics-1.34.1.jar
opentelemetry-sdk-metrics-1.40.0.jar
opentelemetry-sdk-trace-1.34.1.jar
opentelemetry-sdk-trace-1.40.0.jar
opentelemetry-semconv-1.21.0-alpha.jar
opentelemetry-semconv-1.25.0-alpha.jar
prometheus-metrics-config-1.3.1.jar
prometheus-metrics-config-1.3.6.jar
prometheus-metrics-exposition-formats-1.3.1.jar
prometheus-metrics-exposition-textformats-1.3.6.jar
prometheus-metrics-exporter-common-1.3.1.jar
prometheus-metrics-exporter-common-1.3.6.jar
prometheus-metrics-exporter-httpserver-1.3.1.jar
prometheus-metrics-exporter-httpserver-1.3.6.jar
prometheus-metrics-model-1.3.1.jar
prometheus-metrics-model-1.3.6.jar"
printf "%s\n" "$IGNORE_LIST" >> "${KAFKA_VERSION}.ignorelist"

echo "Building and Pushing Docker Images..."

cd "$ROOT_DIR"
for ARCH in arm64 amd64; do
    DOCKER_ARCHITECTURE=$ARCH make -C docker-images/base docker_build
    DOCKER_ARCHITECTURE=$ARCH make -C docker-images/kafka-based docker_build docker_tag docker_push
    DOCKER_ARCHITECTURE=$ARCH make -C docker-images/kafka-based docker_amend_manifest
done
make -C docker-images/kafka-based docker_push_manifest