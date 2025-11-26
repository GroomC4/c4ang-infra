#!/usr/bin/env bash
set -euo pipefail

# This script (re)creates only the NAT Gateway and related route.
# It assumes VPC와 서브넷이 이미 존재하며, NAT EIP는 Terraform 상태로 관리된다고 가정합니다.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "[INFO] Working dir: $(pwd)"

# Ensure backend and providers are initialized
terraform init -input=false -upgrade

echo "[INFO] Current workspace: $(terraform workspace show)"

echo "[INFO] Creating NAT Gateway (will reuse allocated EIP if managed by state)..."
terraform apply -target='module.vpc_app.aws_nat_gateway.this[0]' -auto-approve

echo "[INFO] Creating NAT private route to NAT Gateway..."
terraform apply -target='module.vpc_app.aws_route.private_nat_gateway[0]' -auto-approve

echo "[INFO] Done. NAT Gateway and route ready."



