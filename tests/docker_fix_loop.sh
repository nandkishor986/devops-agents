#!/usr/bin/env bash
# Integration test for the Docker agent's loop: verify (expect specific DIAG) → apply the fix the playbook prescribes → verify (expect PASS).
# Needs a running Docker daemon. Base image: BASE env (default busybox:1.37; offline: build local/busybox:test from a static busybox).
# Usage: BASE=busybox:1.37 bash tests/docker_fix_loop.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; V="$ROOT/scripts/docker-verify.sh"; BASE="${BASE:-busybox:1.37}"
docker info >/dev/null 2>&1 || { echo "SKIP no docker daemon"; exit 0; }
W=$(mktemp -d); cp -R "$ROOT/tests/fixtures/docker/." "$W/"; PASS=0; FAILN=0
run(){ bash "$V" -f "$W/$1/Dockerfile" -t "loop-$1:dev" -p 8080 --timeout 25 --build-arg "BASE=$BASE" "${@:2}" 2>&1; }
check(){ # case expected_diag fix_cmd [verify flags]
  local c="$1" want="$2" fix="$3"; shift 3
  local out1 out2; out1=$(run "$c" "$@")
  if ! grep -q "DIAG $want" <<<"$out1"; then echo "✗ $c: expected DIAG $want, got: $(grep -E 'DIAG|RESULT' <<<"$out1" | tr '\n' ' ')"; FAILN=$((FAILN+1)); return; fi
  (cd "$W/$c" && eval "$fix")
  out2=$(run "$c" "$@")
  if grep -q "RESULT PASS" <<<"$out2"; then echo "✓ $c: $want → fixed → PASS"; PASS=$((PASS+1))
  else echo "✗ $c: still failing after fix: $(grep -E 'DIAG|RESULT' <<<"$out2" | tr '\n' ' ')"; FAILN=$((FAILN+1)); fi
}
out=$(run healthy); grep -q "RESULT PASS" <<<"$out" && { echo "✓ healthy: PASS"; PASS=$((PASS+1)); } || { echo "✗ healthy: $out"; FAILN=$((FAILN+1)); }
check hc-cmd-missing   HC_CMD_MISSING      "sed -i 's/\"curl\", \"-fsS\"/\"wget\", \"-q\", \"--spider\"/' Dockerfile"
check hc-port-mismatch HC_PORT_MISMATCH    "sed -i 's#127.0.0.1:8081#127.0.0.1:8080#' Dockerfile"
check bind-localhost   BIND_LOCALHOST      "sed -i 's#\"127.0.0.1:8080\", \"-h\"#\"0.0.0.0:8080\", \"-h\"#' Dockerfile"
check exit-127         RUN_FAIL            "sed -i 's/\"httpdx\"/\"httpd\"/; s#\"0.0.0.0:8080\"\\]#\"0.0.0.0:8080\", \"-h\", \"/www\"]#' Dockerfile"
check copy-missing     BUILD_COPY_MISSING  "printf 'port: 8080\n' > config.yaml"
check ro-fs            RO_FS               "sed -i 's#/data/state#/tmp/state#' Dockerfile" --hardened
docker ps -aq --filter 'name=verify-' | xargs -r docker rm -f >/dev/null 2>&1; rm -rf "$W"
echo "passed=$PASS failed=$FAILN"; [[ $FAILN -eq 0 ]]
