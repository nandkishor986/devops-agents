#!/usr/bin/env bash
# aws-price.sh — AWS Price List lookup via the aws CLI (needs any credentials with pricing:GetProducts; read-only).
# Usage:
#   aws-price.sh ec2 <instance-type> [--region ap-south-1] [--os Linux|Windows|RHEL|SUSE] [--qty N] [--currency INR]
#   aws-price.sh ebs <gp3|gp2|io2|st1|sc1> [--region ap-south-1] [--gb 30] [--currency INR]
# AWS publishes USD only. --currency (default $DEVOPS_CURRENCY or USD) converts with $DEVOPS_FX_<CUR> if set,
# else Microsoft's retail USD→<CUR> rate from az-price.sh fx (labelled as converted). Monthly = hourly × 730 × qty.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v aws >/dev/null && command -v jq >/dev/null || { echo "ERR needs aws CLI + jq"; exit 2; }
KIND="${1:-}"; NAME="${2:-}"; shift 2 2>/dev/null || { sed -n '2,7p' "$0"; exit 2; }
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-south-1}}"; OS="Linux"; QTY=1; GB=30; CUR="${DEVOPS_CURRENCY:-USD}"
while [[ $# -gt 0 ]]; do case "$1" in
  --region) REGION="$2"; shift;; --os) OS="$2"; shift;; --qty) QTY="$2"; shift;; --gb) GB="$2"; shift;;
  --currency) CUR="$2"; shift;; *) echo "unknown arg $1"; exit 2;; esac; shift; done
CUR=$(echo "$CUR" | tr '[:lower:]' '[:upper:]')
[[ "$NAME" =~ ^[a-z0-9.]{2,40}$ && "$REGION" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]$ ]] || { echo "ERR bad type/region"; exit 2; }

f(){ printf '{"Type":"TERM_MATCH","Field":"%s","Value":"%s"}' "$1" "$2"; }
case "$KIND" in
  ec2) FILTERS="[$(f regionCode "$REGION"),$(f instanceType "$NAME"),$(f operatingSystem "$OS"),$(f tenancy Shared),$(f preInstalledSw NA),$(f capacitystatus Used),$(f licenseModel 'No License required')]";;
  ebs) FILTERS="[$(f regionCode "$REGION"),$(f productFamily Storage),$(f volumeApiName "$NAME")]";;
  *) sed -n '2,7p' "$0"; exit 2;;
esac
# Price List API endpoints live in us-east-1 / ap-south-1 / eu-central-1; any region's prices are queryable from them.
RAW=$(aws pricing get-products --region us-east-1 --service-code AmazonEC2 --format-version aws_v1 --max-results 20 --filters "$FILTERS" --output json 2>&1) \
  || { echo "ERR aws pricing failed: $(echo "$RAW" | tail -n1 | cut -c1-200) (run aws sso login / aws configure)"; exit 2; }
USD=$(echo "$RAW" | jq -r '[.PriceList[] | fromjson | .terms.OnDemand // {} | to_entries[].value.priceDimensions | to_entries[].value
        | select((.pricePerUnit.USD|tonumber) > 0) | .pricePerUnit.USD | tonumber] | min // empty')
[[ -n "$USD" ]] || { echo "no on-demand price found for $KIND $NAME in $REGION (check type/region/os)"; exit 1; }

RATE=1; NOTE="USD (AWS list price)"
if [[ "$CUR" != "USD" ]]; then
  VAR="DEVOPS_FX_${CUR}"; RATE="${!VAR:-}"
  if [[ -z "$RATE" ]]; then RATE=$(bash "$HERE/az-price.sh" fx "$CUR" 2>/dev/null | awk '/^fx /{print $3}'); fi
  if [[ -z "$RATE" ]]; then RATE=1; CUR="USD"; NOTE="USD (no FX rate available — set DEVOPS_FX_INR=…)"
  else NOTE="$CUR converted from USD at $RATE"; fi
fi
SYM="$CUR "; case "$CUR" in INR) SYM="₹";; USD) SYM="\$";; EUR) SYM="€";; GBP) SYM="£";; esac
echo "# aws-price $KIND $NAME region=$REGION ${KIND/ebs/size=${GB}GB} qty=$QTY · $NOTE · on-demand, no Savings Plans/RIs"
if [[ "$KIND" == "ec2" ]]; then
  awk -v u="$USD" -v r="$RATE" -v q="$QTY" -v s="$SYM" -v os="$OS" 'BEGIN{printf "ec2 %s per-hour=%s%.4f  monthly_est=%s%.2f x%s (730h)\n", os, s, u*r, s, u*r*730*q, q}'
else
  awk -v u="$USD" -v r="$RATE" -v g="$GB" -v q="$QTY" -v s="$SYM" 'BEGIN{printf "ebs per-GB-month=%s%.4f  monthly_est=%s%.2f for %sGB x%s\n", s, u*r, s, u*r*g*q, g, q}'
fi
