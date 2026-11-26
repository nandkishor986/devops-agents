#!/usr/bin/env bash
# Offline test for az-price.sh: a fake curl serves canned Retail Prices API JSON (USD or INR by currencyCode).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export PATH="$ROOT/tests/fakebin:$PATH"; F=0
t(){ if grep -qF -- "$2" <<<"$1"; then echo "✓ $3"; else echo "✗ $3 — got: $1"; F=1; fi; }
t "$(bash "$ROOT/scripts/az-price.sh" preset private-endpoint --currency INR)" "₹695.18/mo x1" "INR native price, monthly from hourly"
t "$(bash "$ROOT/scripts/az-price.sh" preset private-endpoint --qty 2)" "\$14.60/mo x2" "USD default, quantity"
t "$(DEVOPS_CURRENCY=inr bash "$ROOT/scripts/az-price.sh" preset private-endpoint)" "currency=INR" "currency from env"
t "$(bash "$ROOT/scripts/az-price.sh" fx INR)" "fx USD->INR 95.2300" "fx rate derived from price lists"
t "$(bash "$ROOT/scripts/az-price.sh" preset private-endpoint --currency rupee)" "ERR bad currency" "rejects invalid currency"
t "$(bash "$ROOT/scripts/aws-price.sh" ec2 t3.micro --region ap-south-1)" "monthly_est=\$8.18 x1" "aws ec2 USD monthly"
t "$(bash "$ROOT/scripts/aws-price.sh" ec2 t3.micro --region ap-south-1 --currency INR)" "₹778." "aws ec2 converted to INR via fx"
t "$(DEVOPS_FX_INR=90 bash "$ROOT/scripts/aws-price.sh" ebs gp3 --gb 30 --currency INR)" "₹246.24 for 30GB" "aws ebs with explicit FX override"
t "$(bash "$ROOT/scripts/aws-price.sh" ec2 'T3;rm' --region ap-south-1)" "ERR bad type/region" "rejects bad input"
exit $F
