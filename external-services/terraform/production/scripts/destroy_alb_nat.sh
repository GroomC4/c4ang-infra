#!/usr/bin/env bash
set -euo pipefail

# This script destroys only the NAT route and NAT Gateway.
# NAT EIP는 재사용을 위해 유지됩니다.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "[INFO] Working dir: $(pwd)"

# Ensure backend and providers are initialized
terraform init -input=false -upgrade

echo "[INFO] Current workspace: $(terraform workspace show)"

echo "[INFO] Destroying NAT private route to NAT Gateway..."
terraform destroy -target='module.vpc_app.aws_route.private_nat_gateway[0]' -auto-approve 

echo "[INFO] Destroying NAT Gateway (EIP will remain)..."
terraform destroy -target='module.vpc_app.aws_nat_gateway.this[0]' -auto-approve

echo "[INFO] Done. NAT route and gateway removed. NAT EIP retained."





