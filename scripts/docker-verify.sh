#!/usr/bin/env bash
# docker-verify.sh — build → run → wait for health → DIAGNOSE (token-lean). The Docker agent's fix loop runs this after every patch.
# Usage:
#   docker-verify.sh -f Dockerfile [-C context] [-t tag] [-p <containerPort>] [--path /healthz] [--timeout 60]
#                    [-e KEY=VAL ...] [--build-arg K=V ...] [--hardened] [--keep] [--no-build]
#   --hardened  run with --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges (what prod should survive)
# Output: compact lines.  RESULT PASS|FAIL  ·  DIAG <CODE> <evidence>  ·  HINT <fix>.   Exit: 0 pass, 1 fail, 2 usage/env.
# DIAG codes map to skills/docker-playbook/references/healthcheck-fixes.md
set -uo pipefail
DF="Dockerfile"; CTX=""; TAG=""; PORT=""; HPATH="/"; TIMEOUT=60; HARD=0; KEEP=0; BUILD=1; ENVS=(); BARGS=()
while [[ $# -gt 0 ]]; do case "$1" in
  -f) DF="$2"; shift;; -C) CTX="$2"; shift;; -t) TAG="$2"; shift;; -p) PORT="$2"; shift;; --path) HPATH="$2"; shift;;
  --timeout) TIMEOUT="$2"; shift;; -e) ENVS+=(-e "$2"); shift;; --build-arg) BARGS+=(--build-arg "$2"); shift;; --hardened) HARD=1;; --keep) KEEP=1;; --no-build) BUILD=0;;
  *) echo "unknown arg $1"; exit 2;; esac; shift; done
command -v docker >/dev/null || { echo "ERR docker not installed"; exit 2; }
docker info >/dev/null 2>&1 || { echo "ERR docker daemon not reachable"; exit 2; }
[[ -f "$DF" ]] || { echo "ERR no Dockerfile at $DF"; exit 2; }
CTX="${CTX:-$(dirname "$DF")}"; TAG="${TAG:-verify-$(basename "$(cd "$CTX" && pwd)" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-'):dev}"
NAME="verify-$$"; FAIL=0
diag(){ echo "DIAG $*"; FAIL=1; }
hint(){ echo "HINT $*"; }
cleanup(){ [[ $KEEP -eq 0 ]] && docker rm -f "$NAME" >/dev/null 2>&1; }
trap cleanup EXIT
echo "# docker-verify $DF ctx=$CTX tag=$TAG hardened=$HARD"

# 1) lint via BuildKit build checks (no build)
if [[ $BUILD -eq 1 ]]; then
  CHK=$(docker build --check "${BARGS[@]}" -f "$DF" "$CTX" 2>&1 | grep -E '^ *(WARNING|ERROR|- )|lint violation' | grep -v '^ *- ' | sed 's/^ *//' | sort -u | head -n 12)
  [[ -n "$CHK" ]] && { echo "## build checks"; echo "$CHK"; }

  # 2) build
  BLOG=$(mktemp)
  if ! DOCKER_BUILDKIT=1 docker build --progress=plain "${BARGS[@]}" -f "$DF" -t "$TAG" "$CTX" >"$BLOG" 2>&1; then
    STEP=$(grep -oE '^#[0-9]+ \[[^]]+\] [A-Z]+ .*' "$BLOG" | tail -n 1 | cut -c1-160)
    ERR=$(grep -iE 'error|failed|not found|denied|no such|unable' "$BLOG" | grep -v '^#.*DONE' | tail -n 6 | cut -c1-200)
    if   echo "$ERR" | grep -qiE 'failed to compute cache key|"/[^"]*": not found|no such file or directory.*COPY|lstat .* no such file'; then
      diag BUILD_COPY_MISSING "$STEP"; hint "file missing from build context: check path relative to -C context and .dockerignore exclusions"
    elif echo "$ERR" | grep -qiE 'executable file not found|: not found|command not found'; then
      diag BUILD_CMD_NOT_FOUND "$STEP"; hint "tool absent in that stage's base image: install it in that stage or use a builder image that has it"
    elif echo "$ERR" | grep -qiE 'could not resolve|temporary failure|timeout|tls handshake|connection refused|failed to resolve source|failed to do request|forbidden|unauthorized|pull access denied|i/o timeout'; then
      diag BUILD_NETWORK "$STEP"; hint "network/registry or proxy unreachable or auth (base image, # syntax frontend, package mirror): docker login, mirror, or proxy build-args"
    elif echo "$ERR" | grep -qiE 'permission denied'; then
      diag BUILD_PERMISSION "$STEP"; hint "step runs as non-root before files are owned by it: move USER after installs or COPY --chown"
    elif echo "$ERR" | grep -qiE 'exec format error'; then
      diag BUILD_ARCH "$STEP"; hint "binary/base arch mismatch: use --platform and TARGETARCH-aware downloads"
    else diag BUILD_FAIL "$STEP"; fi
    echo "--- build error tail"; echo "$ERR"
    rm -f "$BLOG"; echo "RESULT FAIL"; exit 1
  fi
  rm -f "$BLOG"
fi

# 3) image facts
HC=$(docker image inspect "$TAG" --format '{{if .Config.Healthcheck}}{{json .Config.Healthcheck.Test}} interval={{.Config.Healthcheck.Interval}} timeout={{.Config.Healthcheck.Timeout}} start={{.Config.Healthcheck.StartPeriod}} retries={{.Config.Healthcheck.Retries}}{{end}}' 2>/dev/null)
USER_=$(docker image inspect "$TAG" --format '{{.Config.User}}')
echo "image user=${USER_:-ROOT} healthcheck=${HC:-none} entry=$(docker image inspect "$TAG" --format '{{json .Config.Entrypoint}} {{json .Config.Cmd}}')"
[[ -z "$USER_" || "$USER_" == "root" || "$USER_" == "0" ]] && echo "WARN DKR-SEC-002 runs as root (fixing health must not rely on root)"

# 4) run
RUNF=(-d --name "$NAME")
[[ $HARD -eq 1 ]] && RUNF+=(--read-only --tmpfs "/tmp:rw,size=64m" --cap-drop ALL --security-opt no-new-privileges)
[[ -n "$PORT" ]] && RUNF+=(-p "127.0.0.1::$PORT")
if ! OUT=$(docker run "${RUNF[@]}" "${ENVS[@]}" "$TAG" 2>&1); then
  diag RUN_FAIL "$(echo "$OUT" | grep -iE 'error|exec|not found' | head -n 1 | cut -c1-220)"
  echo "$OUT" | grep -qiE 'executable file not found|no such file' && hint "ENTRYPOINT/CMD binary missing in final stage (multi-stage COPY path? exec-form path?)"
  echo "RESULT FAIL"; exit 1
fi

# 5) wait
listen(){ # LISTEN sockets inside the container (needs cat in image; falls back to host /proc on Linux)
  local raw; raw=$(docker exec "$NAME" cat /proc/net/tcp /proc/net/tcp6 2>/dev/null)
  if [[ -z "$raw" ]]; then local pid; pid=$(docker inspect -f '{{.State.Pid}}' "$NAME" 2>/dev/null); [[ -r /proc/$pid/net/tcp ]] && raw=$(cat /proc/"$pid"/net/tcp /proc/"$pid"/net/tcp6 2>/dev/null); fi
  [[ -z "$raw" ]] && { echo "unknown"; return; }
  echo "$raw" | awk 'function hx(s,  n,i){n=0;s=toupper(s);for(i=1;i<=length(s);i++)n=n*16+index("0123456789ABCDEF",substr(s,i,1))-1;return n} $4=="0A"{split($2,a,":"); ip=a[1]; p=hx(a[2]); if(ip ~ /^0+$/) h="0.0.0.0"; else if(ip=="0100007F"||ip=="00000000000000000000000001000000") h="127.0.0.1"; else h=ip; print h ":" p}' | sort -u | tr '\n' ' '
}
probe(){ [[ -z "$PORT" ]] && return 2; local hp; hp=$(docker port "$NAME" "$PORT/tcp" 2>/dev/null | head -n1 | awk -F: '{print $NF}'); [[ -z "$hp" ]] && return 2
  curl -s -o /dev/null -m 3 -w '%{http_code}' "http://127.0.0.1:$hp$HPATH" 2>/dev/null; }
T0=$(date +%s); STATE=""; HEALTH=""; STABLE=0
while :; do
  STATE=$(docker inspect -f '{{.State.Status}}' "$NAME" 2>/dev/null)
  HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$NAME" 2>/dev/null)
  [[ "$STATE" == "exited" || "$STATE" == "dead" ]] && break
  [[ "$HEALTH" == "healthy" || "$HEALTH" == "unhealthy" ]] && break
  if [[ -z "$HEALTH" && "$STATE" == "running" ]]; then STABLE=$((STABLE+2)); [[ $STABLE -ge 10 ]] && break; fi
  (( $(date +%s) - T0 >= TIMEOUT )) && break
  sleep 2
done
ELAPSED=$(( $(date +%s) - T0 ))
echo "state=$STATE health=${HEALTH:-n/a} after=${ELAPSED}s listen=$(listen)"

logs_tail(){ docker logs --tail 40 "$NAME" 2>&1 | grep -iE 'error|fatal|panic|exception|denied|refused|not found|read-only|address|listen|bind' | tail -n 8 | cut -c1-200; echo "--- last 5"; docker logs --tail 5 "$NAME" 2>&1 | cut -c1-200; }

# 6) diagnose
if [[ "$STATE" == "exited" || "$STATE" == "dead" ]]; then
  CODE=$(docker inspect -f '{{.State.ExitCode}}' "$NAME"); OOM=$(docker inspect -f '{{.State.OOMKilled}}' "$NAME")
  L=$(docker logs --tail 40 "$NAME" 2>&1)
  if [[ "$OOM" == "true" ]]; then diag EXIT_OOM "exit=$CODE"; hint "raise memory limit or cap runtime heap (-XX:MaxRAMPercentage, --max-old-space-size)"
  elif echo "$L" | grep -qiE 'read-only file system'; then diag RO_FS "exit=$CODE $(echo "$L" | grep -iE 'read-only' | tail -n1 | cut -c1-160)"; hint "app writes outside /tmp: point caches/pid/logs to /tmp or a volume; keep --read-only"
  elif echo "$L" | grep -qiE 'permission denied|EACCES|operation not permitted'; then diag PERMISSION "exit=$CODE $(echo "$L" | grep -iE 'permission denied|EACCES|operation not permitted' | tail -n1 | cut -c1-160)"; hint "non-root user can't write/bind: COPY --chown=<uid>, writable dir, or port ≥1024; do NOT switch to root"
  elif echo "$L" | grep -qiE 'exec format error'; then diag ARCH_MISMATCH "exit=$CODE"; hint "rebuild for target platform (--platform linux/amd64|arm64)"
  elif [[ "$CODE" == "127" ]]; then diag EXIT_127_CMD_NOT_FOUND "$(echo "$L" | tail -n1 | cut -c1-160)"; hint "ENTRYPOINT/CMD binary or interpreter missing in final stage; check exec-form path"
  elif [[ "$CODE" == "126" ]]; then diag EXIT_126_NOT_EXECUTABLE ""; hint "chmod +x in build stage (COPY --chmod=0755) or wrong interpreter shebang"
  elif [[ "$CODE" == "0" ]]; then diag EXITED_CLEAN "process exited 0"; hint "no foreground process: run server in foreground (no daemon flag, no '&')"
  elif [[ "$CODE" == "137" ]]; then diag EXIT_137_KILLED ""; hint "SIGKILL without OOM flag: host limit or orchestrator kill"
  else diag EXIT_APP "exit=$CODE"; hint "application error — read log lines below; config/env/secret missing is most common"; fi
  logs_tail
elif [[ "$HEALTH" == "unhealthy" || ( -n "$HC" && "$HEALTH" == "starting" ) ]]; then
  HL=$(docker inspect -f '{{range .State.Health.Log}}{{.ExitCode}}|{{.Output}}{{"\n"}}{{end}}' "$NAME" | grep -v '^$' | tail -n 3 | tr -d '\r' | cut -c1-200)
  echo "--- health log (exit|output)"; echo "$HL"
  LST=$(listen)
  if [[ "$HEALTH" == "starting" ]]; then diag HC_NEVER_PASSED "still starting after ${ELAPSED}s"; hint "slow boot: add --start-period (and --start-interval) to HEALTHCHECK; or the check never succeeds (see log)"; fi
  if   echo "$HL" | grep -qiE 'executable file not found|not found|no such file'; then diag HC_CMD_MISSING "$(echo "$HL" | tail -n1)"; hint "health tool absent in final image (curl/wget/sh in distroless/slim): use exec form with a binary the image HAS (python/node runtime one-liner, app's own --healthcheck flag, or a tiny static checker); never add a shell/curl just for this"
  elif echo "$HL" | grep -qiE 'refused|ECONNREFUSED|can.t connect|failed to connect'; then
    diag HC_CONN_REFUSED "listen=$LST"
    HCPORT=$(echo "$HC" | grep -oE 'localhost:[0-9]+|127\.0\.0\.1:[0-9]+|0\.0\.0\.0:[0-9]+' | head -n1 | awk -F: '{print $2}')
    if [[ -n "$HCPORT" && "$LST" != "unknown" && -n "$LST" && "$LST" != *":$HCPORT "* ]]; then diag HC_PORT_MISMATCH "check targets :$HCPORT but app listens on $LST"; hint "align HEALTHCHECK port with the app's listen port (prefer an ENV PORT used by both)"
    else hint "app not listening yet or crashed in background: add start-period, check logs"; fi
  elif echo "$HL" | grep -qiE 'timed out|timeout|deadline'; then diag HC_TIMEOUT ""; hint "check too slow: raise --timeout, make /healthz cheap (no DB round-trip), or the app is overloaded"
  elif echo "$HL" | grep -qiE ' 4[0-9][0-9]| 5[0-9][0-9]|server returned|bad status|404|500|503'; then diag HC_HTTP_ERROR "$(echo "$HL" | tail -n1)"; hint "wrong health path or endpoint failing: confirm route (e.g. /healthz) and that it returns 200 without auth"
  elif echo "$HL" | grep -qE '^2\|'; then diag HC_EXIT_2 ""; hint "health command exits 2 (reserved): end with '|| exit 1'"
  else diag HC_FAIL "unclassified"; fi
  logs_tail
elif [[ -z "$HEALTH" ]]; then
  echo "DIAG_INFO NO_HEALTHCHECK image defines no HEALTHCHECK (OK if K8s probes are used; DKR-REL-002)"
fi

# 7) port probe (outside view) — catches 127.0.0.1-only binds even when in-container health passes
if [[ -n "$PORT" && "$STATE" == "running" ]]; then
  CODE=$(probe); RC=$?
  if [[ $RC -eq 2 ]]; then diag PORT_NOT_PUBLISHED ":$PORT"
  elif [[ -z "$CODE" || "$CODE" == "000" ]]; then
    LST=$(listen)
    if [[ "$LST" == *"127.0.0.1:$PORT"* ]]; then diag BIND_LOCALHOST "listen=$LST"; hint "app binds 127.0.0.1 — bind 0.0.0.0 (HOST=0.0.0.0 / --host 0.0.0.0) so traffic from outside the container reaches it"
    else diag PORT_UNREACHABLE "listen=$LST"; hint "app not listening on :$PORT — check EXPOSE vs actual port env"; fi
  elif [[ "$CODE" =~ ^[45] ]]; then diag HTTP_$CODE "GET $HPATH via published :$PORT"
  else echo "probe GET $HPATH -> $CODE"; fi
fi

if [[ $FAIL -eq 0 && ( "$HEALTH" == "healthy" || ( -z "$HEALTH" && "$STATE" == "running" ) ) ]]; then echo "RESULT PASS"; exit 0; fi
echo "RESULT FAIL"; exit 1
