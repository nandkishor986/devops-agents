#!/usr/bin/env bash
# az-price.sh — Azure Retail Prices lookup (public API, NO login/key). Compact rows + monthly estimate for hourly meters.
# Usage:
#   az-price.sh preset <name> [--region eastus2] [--qty N]       presets: private-endpoint | private-dns-zone | storage <SKU e.g. "Hot LRS"> | vm <size e.g. D4s_v5> | aks-uptime
#   az-price.sh fx [INR]                                         Microsoft retail USD→<cur> rate (derived from the same meter in both price lists)
#   any command: --currency INR (default: $DEVOPS_CURRENCY or USD) — prices come natively in that currency from the API
#   az-price.sh query --region eastus2 [--service "Storage"] [--product "Block Blob"] [--sku "Hot LRS"] [--meter "Data Stored"] [--max 15]
#                     (--product/--meter are contains() matches; --service/--sku exact)
# Prices are retail list (USD, pay-as-you-go "Consumption"); EA/MCA discounts not included. Monthly = hourly × 730.
set -uo pipefail
API="https://prices.azure.com/api/retail/prices"
command -v curl >/dev/null && command -v jq >/dev/null || { echo "ERR needs curl + jq"; exit 2; }
MODE="${1:-}"; shift || true
REGION="eastus2"; SVC=""; PROD=""; SKU=""; METER=""; MAX=15; QTY=1; PRESET=""; ARG=""; CUR="${DEVOPS_CURRENCY:-USD}"
if [[ "$MODE" == "fx" ]]; then [[ $# -gt 0 && "$1" != --* ]] && { CUR="$1"; shift; }; fi
if [[ "$MODE" == "preset" ]]; then PRESET="${1:-}"; shift || true; [[ $# -gt 0 && "$1" != --* ]] && { ARG="$1"; shift; }; fi
while [[ $# -gt 0 ]]; do case "$1" in
  --region) REGION="$2"; shift;; --service) SVC="$2"; shift;; --product) PROD="$2"; shift;; --sku) SKU="$2"; shift;;
  --meter) METER="$2"; shift;; --max) MAX="$2"; shift;; --qty) QTY="$2"; shift;; --currency) CUR="$2"; shift;;
  *) echo "unknown arg $1"; exit 2;; esac; shift; done
CUR=$(echo "$CUR" | tr '[:lower:]' '[:upper:]'); [[ "$CUR" =~ ^[A-Z]{3}$ ]] || { echo "ERR bad currency $CUR"; exit 2; }
SYM="$CUR "; case "$CUR" in INR) SYM="₹";; USD) SYM="\$";; EUR) SYM="€";; GBP) SYM="£";; JPY) SYM="¥";; esac

if [[ "$MODE" == "fx" ]]; then   # same global meter priced in USD and target currency → Microsoft's retail rate
  REF="productName eq 'Virtual Network Private Link' and skuName eq 'Standard' and meterName eq 'Standard Private Endpoint' and armRegionName eq 'Global'"
  U=$(curl -s -m 20 -G "$API" --data-urlencode "currencyCode='USD'" --data-urlencode "\$filter=$REF" | jq -r '[.Items[]?|select(.type=="Consumption")][0].retailPrice // empty')
  T=$(curl -s -m 20 -G "$API" --data-urlencode "currencyCode='$CUR'" --data-urlencode "\$filter=$REF" | jq -r '[.Items[]?|select(.type=="Consumption")][0].retailPrice // empty')
  [[ -n "$U" && -n "$T" ]] || { echo "ERR prices API unreachable"; exit 2; }
  awk -v u="$U" -v t="$T" -v c="$CUR" 'BEGIN{printf "fx USD->%s %.4f (Azure retail price-list rate; use to convert USD-only tools like Infracost)\n", c, t/u}'
  exit 0
fi

F=""
add(){ F="${F:+$F and }$1"; }
case "$PRESET" in
  private-endpoint) add "productName eq 'Virtual Network Private Link'"; add "skuName eq 'Standard'"; add "(armRegionName eq 'Global')";;
  private-dns-zone) add "serviceName eq 'Azure DNS'"; add "productName eq 'Azure DNS'"; add "skuName eq 'Private'"; add "(armRegionName eq 'Global' or armRegionName eq '')";;
  storage) add "serviceName eq 'Storage'"; add "armRegionName eq '$REGION'"; add "skuName eq '${ARG:-Hot LRS}'"; add "contains(productName, 'Block Blob')";;
  vm) add "serviceName eq 'Virtual Machines'"; add "armRegionName eq '$REGION'"; add "armSkuName eq 'Standard_${ARG#Standard_}'"; add "priceType eq 'Consumption'";;
  aks-uptime) add "serviceName eq 'Azure Kubernetes Service'"; add "armRegionName eq '$REGION'";;
  "") [[ "$MODE" == "query" ]] || { sed -n '2,7p' "$0"; exit 2; }
      add "armRegionName eq '$REGION'"
      [[ -n "$SVC" ]] && add "serviceName eq '$SVC'"; [[ -n "$SKU" ]] && add "skuName eq '$SKU'"
      [[ -n "$PROD" ]] && add "contains(productName, '$PROD')"; [[ -n "$METER" ]] && add "contains(meterName, '$METER')";;
  *) echo "unknown preset $PRESET"; exit 2;;
esac
echo "# az-price ${PRESET:-query} region=$REGION qty=$QTY currency=$CUR (retail list, PAYG)"
URL="$API"; ROWS=""; PAGES=0
RESP=$(curl -s -m 20 -G "$URL" --data-urlencode "currencyCode='$CUR'" --data-urlencode "\$filter=$F") || { echo "ERR prices API unreachable"; exit 2; }
while :; do
  ROWS+=$(echo "$RESP" | jq -r '.Items[]? | select(.type=="Consumption") | [.armRegionName, .productName, .skuName, .meterName, .unitOfMeasure, .retailPrice, .tierMinimumUnits] | @tsv')$'\n'
  NEXT=$(echo "$RESP" | jq -r '.NextPageLink // empty'); PAGES=$((PAGES+1))
  [[ -z "$NEXT" || $PAGES -ge 3 ]] && break
  RESP=$(curl -s -m 20 "$NEXT") || break
done
ROWS=$(echo "$ROWS" | grep -v '^$' | grep -viE 'spot|low priority|windows' | sort -u)
[[ "$PRESET" == "vm" ]] && ROWS=$(echo "$ROWS" | grep -viE 'windows' )
[[ -z "$ROWS" ]] && { echo "no matching meters — loosen filters (query --product/--meter are substring matches)"; exit 1; }
echo "region | product | sku | meter | unit | price | tier_min | monthly_est"
echo "$ROWS" | head -n "$MAX" | awk -F'\t' -v q="$QTY" -v s="$SYM" '{
  m=""; if ($5 ~ /Hour/) m=sprintf("%s%.2f/mo x%s", s, $6*730*q, q); else if ($5 ~ /Month/) m=sprintf("%s%.2f/mo x%s", s, $6*q, q);
  printf "%s | %s | %s | %s | %s | %s | %s | %s\n", ($1==""?"global":$1), $2, $3, $4, $5, $6, $7, m }'
N=$(echo "$ROWS" | wc -l | tr -d ' '); [[ $N -gt $MAX ]] && echo "... $((N-MAX)) more (narrow with --meter/--product)"
exit 0
