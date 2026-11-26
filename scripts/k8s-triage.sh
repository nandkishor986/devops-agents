#!/usr/bin/env bash
# k8s-triage.sh — READ-ONLY cluster/namespace triage digest (token-lean).
# Usage:
#   k8s-triage.sh -n <ns>                 # namespace overview: unhealthy pods, warnings, rollouts, PVCs
#   k8s-triage.sh -n <ns> -p <pod>        # deep dive one pod: status, events, last logs (+previous)
#   k8s-triage.sh -A                      # cluster-wide unhealthy summary + node health
#   k8s-triage.sh --manifests <dir>       # static manifest checks (kubeconform/kube-linter/heuristics), no cluster needed
# Flags: --context <ctx>  --tail N (default 60)
set -uo pipefail
NS=""; POD=""; ALL=0; CTX=""; TAIL=60; MANI=""
while [[ $# -gt 0 ]]; do case "$1" in
  -n) NS="$2"; shift;; -p) POD="$2"; shift;; -A) ALL=1;; --context) CTX="$2"; shift;;
  --tail) TAIL="$2"; shift;; --manifests) MANI="$2"; shift;; esac; shift; done
have(){ command -v "$1" >/dev/null 2>&1; }
sec(){ printf '\n## %s\n' "$1"; }

if [[ -n "$MANI" ]]; then
  echo "# k8s manifest scan $MANI"
  sec "schema (kubeconform)"
  if have kubeconform; then kubeconform -summary -output text -ignore-missing-schemas "$MANI" 2>&1 | tail -n 20; else echo "SKIP kubeconform not installed"; fi
  sec "lint (kube-linter)"
  if have kube-linter; then kube-linter lint "$MANI" --format plain 2>&1 | grep -E '^\S+: \(' | head -n 30 || echo "clean"; else echo "SKIP kube-linter not installed"; fi
  sec "security (trivy config)"
  if have trivy; then trivy config --quiet --severity CRITICAL,HIGH --format json "$MANI" 2>/dev/null | jq -r '[.Results[]? | .Target as $t | .Misconfigurations[]? | "\(.Severity) \($t) \(.ID) \(.Title)"] | unique | .[]' | head -n 30; else echo "SKIP trivy"; fi
  sec "heuristics"
  grep -rnE 'privileged:\s*true|hostNetwork:\s*true|hostPID:\s*true' "$MANI" | sed 's/^/K8S-SEC-001 /' | head -n 15
  grep -rnE 'image:\s*\S+:latest\b|image:\s*[^:@ ]+\s*$' "$MANI" | sed 's/^/K8S-SEC-008 /' | head -n 15
  missing(){ # $1=pattern-required $2=kinds $3=rule-label
    grep -rlE "kind:[[:space:]]*($2)" "$MANI" 2>/dev/null | while IFS= read -r f; do grep -qE "$1" "$f" || echo "$3: $f"; done | head -n 15; }
  missing 'resources:' 'Deployment|StatefulSet|DaemonSet|Job|CronJob' 'K8S-REL-001 no resources block'
  missing 'readinessProbe:' 'Deployment|StatefulSet' 'K8S-REL-002 no readinessProbe'
  missing 'runAsNonRoot:[[:space:]]*true' 'Deployment|StatefulSet|DaemonSet' 'K8S-SEC-002 no runAsNonRoot'
  echo; echo "# end"; exit 0
fi

have kubectl || { echo "ERR kubectl not installed"; exit 2; }
K=(kubectl); [[ -n "$CTX" ]] && K+=(--context "$CTX")
SCOPE=(-n "${NS:-default}"); [[ $ALL -eq 1 ]] && SCOPE=(-A)
echo "# k8s-triage ctx=$("${K[@]}" config current-context 2>/dev/null) scope=${NS:-ALL}"
"${K[@]}" version -o json 2>/dev/null | jq -r '"server \(.serverVersion.gitVersion // "unreachable")"' 2>/dev/null

if [[ -n "$POD" ]]; then
  sec "pod status"
  "${K[@]}" get pod "$POD" -n "$NS" -o json | jq -r '
    "phase=\(.status.phase) node=\(.spec.nodeName // "-") qos=\(.status.qosClass)",
    (.status.conditions[]? | select(.status!="True") | "cond \(.type)=False \(.reason // "") \(.message // "")"),
    ((.status.initContainerStatuses // []) + (.status.containerStatuses // []))[] |
      "ctr \(.name) ready=\(.ready) restarts=\(.restartCount) state=\(.state|keys[0]) \(.state[]?.reason // "") last=\(.lastState.terminated.reason // "-") exit=\(.lastState.terminated.exitCode // "-")"'
  sec "spec essentials"
  "${K[@]}" get pod "$POD" -n "$NS" -o json | jq -r '.spec.containers[] | "ctr \(.name) image=\(.image) req=\(.resources.requests // {} | tostring) lim=\(.resources.limits // {} | tostring) readiness=\(.readinessProbe != null) liveness=\(.livenessProbe != null)"'
  sec "events (newest last)"
  "${K[@]}" get events -n "$NS" --field-selector "involvedObject.name=$POD" --sort-by=.lastTimestamp -o json \
   | jq -r '.items[-15:][] | "\(.type) \(.reason) x\(.count // 1): \(.message)"'
  for c in $("${K[@]}" get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[*].name}'); do
    sec "logs $c (tail $TAIL, errors first)"
    L=$("${K[@]}" logs "$POD" -n "$NS" -c "$c" --tail="$TAIL" 2>&1)
    echo "$L" | grep -iE 'error|fatal|panic|exception|refused|denied|timeout|oom' | tail -n 15
    echo "--- last 10"; echo "$L" | tail -n 10
    P=$("${K[@]}" logs "$POD" -n "$NS" -c "$c" --previous --tail=30 2>/dev/null)
    [[ -n "$P" ]] && { echo "--- previous (crashed) last 15"; echo "$P" | tail -n 15; }
  done
  echo; echo "# end"; exit 0
fi

sec "unhealthy pods"
"${K[@]}" get pods "${SCOPE[@]}" -o json | jq -r '
  .items[] | . as $p |
  ([.status.containerStatuses[]? | .restartCount] | add // 0) as $r |
  ([.status.containerStatuses[]? | (.state.waiting.reason // .state.terminated.reason // empty)] | join(",")) as $why |
  select(.status.phase!="Running" and .status.phase!="Succeeded" or $r>3 or ($why|length>0) or ([.status.containerStatuses[]?|.ready]|all|not)) |
  "\(.metadata.namespace)/\(.metadata.name) phase=\(.status.phase) restarts=\($r) reason=\($why) node=\(.spec.nodeName // "unscheduled")"' | head -n 30
sec "rollouts not ready"
"${K[@]}" get deploy,sts,ds "${SCOPE[@]}" -o json | jq -r '.items[] |
  (.status.readyReplicas // .status.numberReady // 0) as $r | (.spec.replicas // .status.desiredNumberScheduled // 0) as $d |
  select($r < $d) | "\(.kind) \(.metadata.namespace)/\(.metadata.name) ready=\($r)/\($d)"' | head -n 20
sec "warning events (last 20, deduped)"
"${K[@]}" get events "${SCOPE[@]}" --field-selector type=Warning --sort-by=.lastTimestamp -o json \
  | jq -r '.items | map("\(.involvedObject.kind)/\(.involvedObject.name) \(.reason): \(.message|.[0:160])") | unique | .[-20:][]'
sec "pvc not bound"
"${K[@]}" get pvc "${SCOPE[@]}" -o json | jq -r '.items[] | select(.status.phase!="Bound") | "\(.metadata.namespace)/\(.metadata.name) \(.status.phase) sc=\(.spec.storageClassName // "-")"'
sec "services without endpoints"
"${K[@]}" get endpoints "${SCOPE[@]}" -o json | jq -r '.items[] | select((.subsets // []) | length == 0) | "\(.metadata.namespace)/\(.metadata.name)"' | grep -v '/kubernetes$' | head -n 15
if [[ $ALL -eq 1 ]]; then
  sec "nodes"
  "${K[@]}" get nodes -o json | jq -r '.items[] | "\(.metadata.name) " + ([.status.conditions[] | select((.type=="Ready" and .status!="True") or (.type!="Ready" and .status=="True")) | .type] | if length==0 then "OK" else join(",") end) + " \(.metadata.labels["kubernetes.azure.com/agentpool"] // "")"'
  have kubectl && "${K[@]}" top nodes --no-headers 2>/dev/null | head -n 20
fi
echo; echo "# end"
