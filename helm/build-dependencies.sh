#!/bin/bash
set -e

echo "🔨 Building Helm chart dependencies..."

# Add required Helm repositories
echo "📦 Adding required Helm repositories..."
helm repo add apache-airflow https://airflow.apache.org 2>/dev/null || true
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update

# Base charts
echo "📦 Building Airflow base dependencies..."
cd management-base/airflow
helm dependency build

echo "📦 Building PostgreSQL dependencies..."
cd ../../statefulset-base/postgresql
helm dependency build

echo "📦 Building Redis dependencies..."
cd ../redis
helm dependency build

# Test infrastructure
echo "📦 Building test-infrastructure dependencies..."
cd ../../test-infrastructure
helm dependency build

# istio service mesh and gateway
echo "📦 Building istio dependencies..."
cd ../management-base/istio
helm dependency build

# Customer service (optional)
echo "📦 Building customer-service dependencies..."
cd ../../services/customer-service
helm dependency build

echo "✅ All Helm chart dependencies built successfully!"
