#!/usr/bin/env bash
# finops-scan.sh — READ-ONLY Azure cost-waste digest (token-lean). Needs: az CLI (logged in) + resource-graph extension, jq.
# Usage:
#   finops-scan.sh [--sub <subscriptionId>] [--days 30]      # waste + advisor + top spend
#   finops-scan.sh --tf <dir>                                 # Infracost diff for a Terraform dir (vs main via git)
#   finops-scan.sh --aks -n <ns>                              # requests vs usage for a namespace (kubectl top)
set -uo pipefail
PY=$(for c in python3 python; do command -v "$c" >/dev/null && "$c" -c "" 2>/dev/null && { command -v "$c"; break; }; done)
SUB=""; DAYS=30; TF=""; AKS=0; NS=""
while [[ $# -gt 0 ]]; do case "$1" in --sub) SUB="$2"; shift;; --days) DAYS="$2"; shift;; --tf) TF="$2"; shift;; --aks) AKS=1;; -n) NS="$2"; shift;; esac; shift; done
have(){ command -v "$1" >/dev/null 2>&1; }
sec(){ printf '\n## %s\n' "$1"; }
echo "# finops-scan"

if [[ -n "$TF" ]]; then
  have infracost || { echo "SKIP infracost not installed (https://www.infracost.io/docs/)"; exit 0; }
  sec "infracost breakdown $TF"
  infracost breakdown --path "$TF" --format json --out-file /tmp/ic-now.json --log-level error >/dev/null 2>&1 \
    && jq -r '"monthly_total_usd=\(.totalMonthlyCost)", (.projects[].breakdown.resources | sort_by(-(.monthlyCost // "0"|tonumber)) | .[:10][] | "  \(.name) $\(.monthlyCost // "0")/mo")' /tmp/ic-now.json
  if git -C "$TF" rev-parse >/dev/null 2>&1; then
    BASE=$(git -C "$TF" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
    tmp=$(mktemp -d); git -C "$TF" worktree add -q "$tmp" "$BASE" 2>/dev/null && {
      rel=$(realpath --relative-to="$(git -C "$TF" rev-parse --show-toplevel)" "$TF")
      infracost breakdown --path "$tmp/$rel" --format json --out-file /tmp/ic-base.json --log-level error >/dev/null 2>&1
      sec "diff vs $BASE"
      infracost diff --path "$TF" --compare-to /tmp/ic-base.json --log-level error 2>/dev/null | tail -n 20
      git -C "$TF" worktree remove --force "$tmp" >/dev/null 2>&1; }
  fi
  echo; echo "# end"; exit 0
fi

if [[ $AKS -eq 1 ]]; then
  have kubectl || { echo "ERR kubectl"; exit 2; }
  sec "requests vs usage ns=${NS:-all} (FIN-COST-010 candidates: usage < 30% of request)"
  SC=(-n "${NS:-default}"); [[ -z "$NS" ]] && SC=(-A)
  kubectl get pods "${SC[@]}" -o json | jq -r '.items[] | .metadata.namespace as $n | .metadata.name as $p |
    "\($n)/\($p) " + ([.spec.containers[] | "\(.resources.requests.cpu // "0")|\(.resources.requests.memory // "0")"] | join(";"))' > /tmp/fin-req.txt
  kubectl top pods "${SC[@]}" --no-headers 2>/dev/null | awk -v all="$([[ -z "$NS" ]] && echo 1)" '{ if(all) print $1"/"$2, $3, $4; else print "'"${NS}"'/"$1, $2, $3 }' > /tmp/fin-use.txt
  join <(sort /tmp/fin-req.txt) <(sort /tmp/fin-use.txt) 2>/dev/null | "$PY" -c '
import sys,re
def cpu(s):
    s=s.strip(); return 0 if not s or s=="0" else (float(s[:-1])/1000 if s.endswith("m") else float(s))
def mem(s):
    s=s.strip(); u={"Ki":2**10,"Mi":2**20,"Gi":2**30,"K":1e3,"M":1e6,"G":1e9}
    m=re.match(r"([0-9.]+)([A-Za-z]*)",s or "0"); return float(m.group(1))*u.get(m.group(2),1) if m else 0
for line in sys.stdin:
    pod,req,ucpu,umem=line.split()
    rc=sum(cpu(x.split("|")[0]) for x in req.split(";")); rm=sum(mem(x.split("|")[1]) for x in req.split(";"))
    uc,um=cpu(ucpu),mem(umem)
    flag=[]
    if rc and uc/rc<0.3: flag.append(f"cpu {uc:.2f}/{rc:.2f}")
    if rm and um/rm<0.3: flag.append(f"mem {um/2**20:.0f}Mi/{rm/2**20:.0f}Mi")
    if not rc and not rm: flag.append("NO REQUESTS")
    if flag: print(pod, " ".join(flag))
' | head -n 30
  echo; echo "# end"; exit 0
fi

have az || { echo "ERR az CLI not installed"; exit 2; }
az extension show -n resource-graph >/dev/null 2>&1 || az extension add -n resource-graph --only-show-errors >/dev/null 2>&1
[[ -n "$SUB" ]] && SUBARG=(--subscriptions "$SUB") || SUBARG=()
echo "account: $(az account show --query '{n:name,id:id}' -o tsv 2>/dev/null | tr '\t' ' ')"
q(){ az graph query -q "$1" "${SUBARG[@]}" --first 50 -o json 2>/dev/null | jq -r '.data[] | [.[]] | map(tostring) | join(" | ")'; }

sec "FIN-COST-001 unattached disks (name | rg | sku | GB | created)"
q "Resources | where type =~ 'microsoft.compute/disks' and properties.diskState =~ 'Unattached' | project name, resourceGroup, sku.name, properties.diskSizeGB, properties.timeCreated"
sec "FIN-COST-001 unassociated public IPs"
q "Resources | where type =~ 'microsoft.network/publicipaddresses' and isnull(properties.ipConfiguration) and isnull(properties.natGateway) | project name, resourceGroup, sku.name"
sec "FIN-COST-001 orphan NICs"
q "Resources | where type =~ 'microsoft.network/networkinterfaces' and isnull(properties.virtualMachine) and isnull(properties.privateEndpoint) | project name, resourceGroup"
sec "FIN-COST-004 empty App Service Plans"
q "Resources | where type =~ 'microsoft.web/serverfarms' and toint(properties.numberOfSites) == 0 | project name, resourceGroup, sku.name, sku.tier"
sec "FIN-COST-004 load balancers without backends"
q "Resources | where type =~ 'microsoft.network/loadbalancers' and array_length(properties.backendAddressPools) == 0 | project name, resourceGroup, sku.name"
sec "FIN-COST-005 snapshots older than 90d"
q "Resources | where type =~ 'microsoft.compute/snapshots' and todatetime(properties.timeCreated) < ago(90d) | project name, resourceGroup, properties.diskSizeGB, properties.timeCreated"
sec "FIN-COST-006 deallocation candidates: running VMs in non-prod RGs/tags"
q "Resources | where type =~ 'microsoft.compute/virtualmachines' and (tolower(resourceGroup) matches regex '(dev|test|qa|uat|sandbox)' or tolower(tostring(tags.env)) in ('dev','test','qa','uat')) | extend ps=tostring(properties.extended.instanceView.powerState.code) | where ps =~ 'PowerState/running' | project name, resourceGroup, properties.hardwareProfile.vmSize"
sec "FIN-OPS-001 resources missing cost tags (count by type, top 10)"
q "Resources | where isnull(tags.env) or isnull(tags.owner) or isnull(tags['cost-center']) | summarize n=count() by type | top 10 by n"
sec "FIN-OPS-003 Azure Advisor cost recommendations"
az advisor recommendation list --category Cost -o json 2>/dev/null | jq -r '.[:15][] | "\(.impact) \(.impactedField|split("/")|last)/\(.impactedValue): \(.shortDescription.problem) | saving=\(.extendedProperties.annualSavingsAmount // .extendedProperties.savingsAmount // "n/a") \(.extendedProperties.savingsCurrency // "")"'
sec "FIN-OPS-002 budgets"
n=$(az consumption budget list -o json 2>/dev/null | jq 'length'); echo "budgets on subscription: ${n:-unknown}"
sec "top 10 resource groups by actual cost, last ${DAYS}d (rg | amount | BILLING currency)"
SUBID=${SUB:-$(az account show --query id -o tsv)}
FROM=$(date -u -d "-${DAYS} days" +%Y-%m-%dT00:00:00Z 2>/dev/null || date -u -v-"${DAYS}"d +%Y-%m-%dT00:00:00Z); TO=$(date -u +%Y-%m-%dT23:59:59Z)
az rest --method post --url "https://management.azure.com/subscriptions/${SUBID}/providers/Microsoft.CostManagement/query?api-version=2023-11-01" \
  --body "{\"type\":\"ActualCost\",\"timeframe\":\"Custom\",\"timePeriod\":{\"from\":\"$FROM\",\"to\":\"$TO\"},\"dataset\":{\"granularity\":\"None\",\"aggregation\":{\"c\":{\"name\":\"Cost\",\"function\":\"Sum\"}},\"grouping\":[{\"type\":\"Dimension\",\"name\":\"ResourceGroupName\"}]}}" -o json 2>/dev/null \
  | jq -r '.properties.rows | sort_by(-.[0]) | .[:10][] | "\(.[1]) \(.[0]|.*100|round/100) \(.[2])"' || echo "cost query failed (needs Cost Management Reader)"
echo; echo "# end finops-scan"
