#!/usr/bin/env bash
# tf-scan.sh — run deterministic Terraform checks, print a COMPACT digest (token-lean).
# Usage: tf-scan.sh [dir=.] [--no-init] [--max N]
# Tools used if present: terraform, tflint, trivy (or checkov), infracost. Missing tools are skipped, not fatal.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="${1:-.}"; shift || true
INIT=1; MAX=25
while [[ $# -gt 0 ]]; do case "$1" in --no-init) INIT=0;; --max) MAX="$2"; shift;; esac; shift; done
cd "$DIR" || { echo "ERR dir not found: $DIR"; exit 2; }
have(){ command -v "$1" >/dev/null 2>&1; }
cap(){ head -n "$MAX"; }
sec(){ printf '\n## %s\n' "$1"; }

echo "# tf-scan $(pwd)"
echo "files: $(find . -name '*.tf' -not -path '*/.terraform/*' | wc -l | tr -d ' ') .tf, $(find . -name '*.tfvars' -not -path '*/.terraform/*' | wc -l | tr -d ' ') .tfvars"

if have terraform; then
  sec "version"; terraform version -json 2>/dev/null | (have jq && jq -r '"terraform \(.terraform_version)"' || head -1)
  sec "fmt (files needing fmt)"
  out=$(terraform fmt -check -recursive -list=true 2>&1); [[ -z "$out" ]] && echo "clean" || echo "$out" | cap
  if [[ $INIT -eq 1 ]]; then
    terraform init -backend=false -input=false -no-color >/tmp/tfscan-init.log 2>&1 || { sec "init FAILED"; tail -n 15 /tmp/tfscan-init.log; }
  fi
  sec "validate"
  if have jq; then
    terraform validate -json -no-color 2>/dev/null | jq -r 'if .valid then "valid" else (.diagnostics[] | "\(.severity|ascii_upcase) \(.range.filename // "-"):\(.range.start.line // 0) \(.summary)") end' | cap
  else terraform validate -no-color 2>&1 | cap; fi
else echo "SKIP terraform not installed"; fi

sec "tflint"
if have tflint; then
  tflint --init >/dev/null 2>&1
  tflint --recursive --format compact 2>/dev/null | grep -v '^$' | cap || echo "clean"
else echo "SKIP tflint not installed"; fi

sec "security (trivy config / checkov)"
if have trivy; then
  trivy config --quiet --severity CRITICAL,HIGH,MEDIUM --format json . 2>/dev/null \
  | jq -r '[.Results[]? | .Target as $t | .Misconfigurations[]? | "\(.Severity) \($t):\(.CauseMetadata.StartLine // 0) \(.ID) \(.Title)"] | unique | .[]' | cap
elif have checkov; then
  checkov -d . --compact --quiet -o json 2>/dev/null \
  | jq -r '(if type=="array" then .[] else . end) | .results.failed_checks[]? | "\(.severity // "NA") \(.file_path):\(.file_line_range[0]) \(.check_id) \(.check_name)"' | cap
else echo "SKIP trivy/checkov not installed"; fi

sec "AST checks (python-hcl2) / heuristics"
PY=$(for c in python3 python; do command -v "$c" >/dev/null && "$c" -c "" 2>/dev/null && { command -v "$c"; break; }; done)
if [[ -n "$PY" ]] && "$PY" "$HERE/tf_inspect.py" . --max "$MAX"; then :; else
# Fast grep-level checks that tools often miss; each line → candidate rule ID
grep -rnE --include='*.tf' --include='*.tfvars' '(password|secret|client_secret|access_key|connection_string)\s*=\s*"[^"$]{6,}"' . 2>/dev/null | grep -v '.terraform/' | sed 's/=.*/= "<redacted>"/' | sed 's/^/TF-SEC-001 /' | cap
grep -rnE --include='*.tf' 'public_network_access_enabled\s*=\s*true' . 2>/dev/null | grep -v '.terraform/' | sed 's/^/TF-SEC-003 /' | cap
grep -rnE --include='*.tf' 'source_address_prefix\s*=\s*"(\*|0\.0\.0\.0/0|Internet)"' . 2>/dev/null | grep -v '.terraform/' | sed 's/^/TF-SEC-004 /' | cap
grep -rnE --include='*.tf' 'min_tls_version\s*=\s*"(TLS1_0|TLS1_1|1\.0|1\.1)"' . 2>/dev/null | grep -v '.terraform/' | sed 's/^/TF-SEC-005 /' | cap
grep -rnE --include='*.tf' 'source\s*=\s*"git::[^"]*"' . 2>/dev/null | grep -v 'ref=' | grep -v '.terraform/' | sed 's/^/TF-REL-001 (module no ref) /' | cap
grep -rnE --include='*.tf' 'role_definition_name\s*=\s*"(Owner|Contributor)"' . 2>/dev/null | grep -v '.terraform/' | sed 's/^/TF-SEC-006 /' | cap
if ! grep -rqE --include='*.tf' 'required_providers' . 2>/dev/null; then echo "TF-REL-001 no required_providers block found"; fi
grep -rlE --include='*.tf' '^[[:space:]]*variable[[:space:]]+"' . 2>/dev/null | grep -v '.terraform/' | while read -r f; do
  awk -v f="$f" '/^[[:space:]]*variable[[:space:]]+"/{n=$2; t=0; d=0; open=1} open&&/^[[:space:]]*type[[:space:]]*=/{t=1} open&&/^[[:space:]]*description[[:space:]]*=/{d=1} open&&/^}/{ if(!t) print "TF-COR-004 " f ": var " n " no type"; if(!d) print "TF-MNT-002 " f ": var " n " no description"; open=0}' "$f"
done | cap

fi

sec "cost (infracost)"
if have infracost && [[ -n "${INFRACOST_API_KEY:-}" ]]; then
  infracost breakdown --path . --format json --log-level error 2>/dev/null \
  | jq -r '"monthly_total_usd=\(.totalMonthlyCost // "n/a")", (.projects[]?.breakdown.resources[]? | select((.monthlyCost // "0"|tonumber) > 20) | "  \(.name) $\(.monthlyCost)/mo")' | head -n 15
else echo "SKIP infracost not installed or INFRACOST_API_KEY unset"; fi
echo; echo "# end tf-scan"
