#!/usr/bin/env bash
# docker-audit.sh — Dockerfile / image / container security+efficiency digest (token-lean).
# Usage:
#   docker-audit.sh -f Dockerfile              # static: hadolint + heuristics + .dockerignore
#   docker-audit.sh -i image:tag               # image: user, size, layers, CVEs (trivy/scout)
#   docker-audit.sh -c <container>             # runtime: privileges, caps, mounts, rootfs
#   combine flags freely: -f Dockerfile -i myapp:dev
set -uo pipefail
DF=""; IMG=""; CTR=""
while [[ $# -gt 0 ]]; do case "$1" in -f) DF="$2"; shift;; -i) IMG="$2"; shift;; -c) CTR="$2"; shift;; esac; shift; done
have(){ command -v "$1" >/dev/null 2>&1; }
sec(){ printf '\n## %s\n' "$1"; }
echo "# docker-audit"

if [[ -n "$DF" ]]; then
  [[ -f "$DF" ]] || { echo "ERR no file $DF"; exit 2; }
  CTXDIR=$(dirname "$DF")
  sec "hadolint $DF"
  if have hadolint; then hadolint --no-fail -f tty "$DF" 2>&1 | head -n 25
  elif have docker && docker info >/dev/null 2>&1; then docker run --rm -i hadolint/hadolint hadolint --no-fail - < "$DF" 2>&1 | head -n 25
  else echo "SKIP hadolint"; fi
  sec "heuristics"
  stages=$(grep -ciE '^\s*FROM\s' "$DF"); echo "stages=$stages"
  grep -nE '^\s*FROM\s+[^ :@]+(\s|$)|^\s*FROM\s+\S+:latest' "$DF" | sed 's/^/DKR-SEC-003 /'
  grep -nE '^\s*FROM\s' "$DF" | grep -v '@sha256:' | sed 's/^/INFO no digest pin: /'
  last_user=$(grep -nE '^\s*USER\s' "$DF" | tail -n1)
  last_from=$(grep -nE '^\s*FROM\s' "$DF" | tail -n1 | cut -d: -f1)
  if [[ -z "$last_user" ]] || [[ ${last_user%%:*} -lt ${last_from:-0} ]]; then echo "DKR-SEC-002 final stage has no USER (runs as root)"
  elif echo "$last_user" | grep -qiE 'USER\s+(root|0)(\s|:|$)'; then echo "DKR-SEC-002 $last_user"; fi
  grep -niE '^\s*(ARG|ENV)\s+\S*(PASS|SECRET|TOKEN|KEY|CREDENTIAL)\S*' "$DF" | sed 's/=.*/=<redacted>/' | sed 's/^/DKR-SEC-001 /'
  grep -niE 'COPY\s+.*(\.env|id_rsa|\.pem|\.pfx|credentials|kubeconfig)' "$DF" | sed 's/^/DKR-SEC-001 /'
  grep -niE '(curl|wget)[^|]*\|\s*(ba)?sh' "$DF" | sed 's/^/DKR-SEC-006 /'
  grep -niE '^\s*ADD\s+https?://' "$DF" | sed 's/^/DKR-SEC-006 /'
  grep -niE '^\s*(CMD|ENTRYPOINT)\s+[^\[]' "$DF" | sed 's/^/DKR-REL-001 shell form: /'
  grep -niE 'apt-get install' "$DF" | grep -v 'no-install-recommends' | sed 's/^/DKR-PERF-003 no --no-install-recommends: /'
  grep -niE 'apt-get install' "$DF" | grep -v 'rm -rf /var/lib/apt/lists' | sed 's/^/DKR-PERF-003 apt lists not cleaned: /'
  grep -niE '^\s*RUN\s+apt-get update\s*$' "$DF" | sed 's/^/DKR-COR-001 /'
  first_copy_all=$(grep -nE '^\s*COPY\s+\.\s' "$DF" | head -n1 | cut -d: -f1)
  dep_install=$(grep -nE 'npm (ci|install)|pip install|go mod download|mvn .*(package|dependency)|dotnet restore|bundle install' "$DF" | head -n1 | cut -d: -f1)
  [[ -n "$first_copy_all" && -n "$dep_install" && $first_copy_all -lt $dep_install ]] && echo "DKR-PERF-001 COPY . (line $first_copy_all) before deps install (line $dep_install)"
  grep -qiE '^\s*HEALTHCHECK' "$DF" || echo "DKR-REL-002 no HEALTHCHECK (ok if K8s probes used)"
  grep -qiE 'org.opencontainers.image' "$DF" || echo "DKR-MNT-001 no OCI labels"
  [[ -f "$CTXDIR/.dockerignore" ]] || echo "DKR-SEC-008 no .dockerignore in $CTXDIR"
  [[ -f "$CTXDIR/.dockerignore" ]] && for p in .git .env node_modules '*.pem'; do grep -qF "$p" "$CTXDIR/.dockerignore" || echo "DKR-SEC-008 .dockerignore missing $p"; done
fi

if [[ -n "$IMG" ]]; then
  have docker || { echo "ERR docker not installed"; exit 2; }
  sec "image $IMG"
  docker image inspect "$IMG" >/dev/null 2>&1 || docker pull -q "$IMG" >/dev/null 2>&1
  docker image inspect "$IMG" --format 'user={{if .Config.User}}{{.Config.User}}{{else}}ROOT{{end}} size={{.Size}} arch={{.Architecture}} entrypoint={{json .Config.Entrypoint}} cmd={{json .Config.Cmd}} ports={{json .Config.ExposedPorts}}' 2>&1 \
    | awk '{for(i=1;i<=NF;i++){ if($i ~ /^size=/){split($i,a,"="); printf "size=%.0fMB ", a[2]/1048576} else printf "%s ", $i }; print ""}'
  echo -n "env keys: "; docker image inspect "$IMG" --format '{{range .Config.Env}}{{println .}}{{end}}' | cut -d= -f1 | tr '\n' ' '; echo
  docker image inspect "$IMG" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -iE '^(\S*(PASS|SECRET|TOKEN|API_KEY)\S*)=.+' | cut -d= -f1 | sed 's/^/DKR-SEC-001 secret-like ENV baked in: /'
  sec "largest layers"
  docker history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' "$IMG" 2>/dev/null | grep -vE '^0B' | sort -hr | head -n 5 | cut -c1-160
  sec "vulnerabilities (HIGH/CRITICAL, fixable)"
  if have trivy; then
    trivy image --quiet --severity HIGH,CRITICAL --ignore-unfixed --format json "$IMG" 2>/dev/null | jq -r '
      [.Results[]?.Vulnerabilities[]?] as $v |
      "counts: CRITICAL=\([$v[]|select(.Severity=="CRITICAL")]|length) HIGH=\([$v[]|select(.Severity=="HIGH")]|length)",
      ($v | unique_by(.VulnerabilityID) | sort_by(.Severity) | .[:15][] | "\(.Severity) \(.VulnerabilityID) \(.PkgName) \(.InstalledVersion)->\(.FixedVersion)")'
    trivy image --quiet --scanners secret --format json "$IMG" 2>/dev/null | jq -r '.Results[]?.Secrets[]? | "DKR-SEC-001 secret in layer: \(.RuleID) \(.Target)"' | head -n 10
  elif docker scout version >/dev/null 2>&1; then docker scout cves --only-severity critical,high --only-fixed "$IMG" 2>/dev/null | tail -n 25
  else echo "SKIP trivy/docker scout not installed"; fi
fi

if [[ -n "$CTR" ]]; then
  sec "runtime $CTR"
  docker inspect "$CTR" --format 'user={{if .Config.User}}{{.Config.User}}{{else}}ROOT{{end}} privileged={{.HostConfig.Privileged}} readonly_rootfs={{.HostConfig.ReadonlyRootfs}} capadd={{json .HostConfig.CapAdd}} capdrop={{json .HostConfig.CapDrop}} secopt={{json .HostConfig.SecurityOpt}} pid={{.HostConfig.PidMode}} net={{.HostConfig.NetworkMode}} mem={{.HostConfig.Memory}} cpus={{.HostConfig.NanoCpus}} restart={{.HostConfig.RestartPolicy.Name}}'
  docker inspect "$CTR" --format '{{range .Mounts}}{{.Source}}->{{.Destination}} rw={{.RW}}{{println}}{{end}}' | grep -E 'docker.sock|^/(etc|proc|sys|root)?->' | sed 's/^/DKR-SEC-005 sensitive mount: /'
  docker inspect "$CTR" --format '{{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
  docker logs --tail 15 "$CTR" 2>&1 | cut -c1-200
fi
echo; echo "# end docker-audit"
