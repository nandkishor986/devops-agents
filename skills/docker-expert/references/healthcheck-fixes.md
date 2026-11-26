# Fix playbook for docker-verify DIAG codes (load only in fix loops)

## Loop contract
1. `docker-verify.sh -f <Dockerfile> -p <port> [--path /healthz] [--hardened]` → read only DIAG/HINT/RESULT lines.
2. Pick the FIRST DIAG (most upstream). Apply the smallest Dockerfile/compose change from the table. One fix per iteration.
3. Re-run verify. Max **3 iterations**; same DIAG twice → stop, status BLOCKED with evidence.
4. Finish with `--hardened` once it passes plain — prod must survive read-only + cap-drop.

## Forbidden "fixes" (never trade security for green)
Removing/disabling HEALTHCHECK · switching to root / `USER 0` · `--privileged`, extra caps · installing curl/wget/bash into distroless/chiseled images just for the check · dropping `--read-only` · `chmod 777` · `retries=100` or 10-minute intervals to mask failure · `|| true` / `exit 0` health commands. If the real fix needs app code (no health route, wrong bind host hard-coded) → BLOCKED + exact code change proposed.

## DIAG → fix
| DIAG | Typical cause | Fix |
|---|---|---|
| HC_CMD_MISSING | `curl` not in alpine/slim/distroless | Use what the image has (table below). Exec form. |
| HC_CONN_REFUSED / HC_PORT_MISMATCH | check port ≠ listen port; app slow | Same port from one `ENV PORT=8080` used by app + check; else add `--start-period` |
| HC_NEVER_PASSED | slow boot (JVM, migrations) | `--start-period=30s --start-interval=2s` (start-interval: Docker ≥25) |
| HC_TIMEOUT | heavy /health (DB calls) | cheap liveness route; `--timeout=3s`; deps belong in readiness, not liveness |
| HC_HTTP_ERROR | wrong path / auth on health route | correct path; health route must be unauthenticated and 200 |
| HC_EXIT_2 | command returns 2 | append `\|\| exit 1` (shell form only where a shell exists) |
| BIND_LOCALHOST | app listens on 127.0.0.1 | bind 0.0.0.0 (`HOST=0.0.0.0`, `--host 0.0.0.0`, `server.address`, `ASPNETCORE_URLS=http://+:8080`) |
| RUN_FAIL / EXIT_127 | ENTRYPOINT binary/path missing in final stage | fix `COPY --from=build` path or exec-form path; distroless node: `/nodejs/bin/node` |
| EXIT_126 | not executable | `COPY --chmod=0755` |
| EXITED_CLEAN | daemonises / no foreground | foreground flag (`nginx -g 'daemon off;'`, `httpd -f`) |
| EXIT_OOM | heap > limit | `-XX:MaxRAMPercentage=75`, `--max-old-space-size`, or raise limit |
| RO_FS | writes to image FS | write to `/tmp` (tmpfs) or a declared `VOLUME`; set cache/pid/log dirs via env |
| PERMISSION | non-root can't write/bind | `COPY --chown=10001:10001`, `RUN mkdir -p /data && chown`, port ≥ 1024 |
| BUILD_COPY_MISSING | path outside context / in .dockerignore | fix path relative to context; un-ignore the file |
| BUILD_CMD_NOT_FOUND | tool absent in that stage | install in that stage or use builder image |
| BUILD_NETWORK | registry/proxy/auth (incl. `# syntax=` frontend pull) | `docker login`, mirror, proxy build-args; not a Dockerfile bug |
| BUILD_ARCH / ARCH_MISMATCH | amd64 vs arm64 | `--platform`, `TARGETARCH`-aware downloads |

## Health commands by base image (exec form, no extra packages)
| Image family | HEALTHCHECK CMD |
|---|---|
| alpine / busybox | `["wget", "-q", "--spider", "http://127.0.0.1:8080/healthz"]` |
| debian-slim with curl already present | `["curl", "-fsS", "http://127.0.0.1:8080/healthz"]` |
| python (incl. distroless python) | `["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2).status==200 else 1)"]` |
| node 18+ (distroless: `/nodejs/bin/node`) | `["node", "-e", "fetch('http://127.0.0.1:8080/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]` |
| Go / static (scratch, distroless/static) | app subcommand `["/app", "healthcheck"]`, or copy a tiny static checker binary from a builder stage |
| .NET chiseled | app-provided health probe binary/flag; no shell available |
| JVM | alpine-based: busybox wget; else app-provided `--health` flag; never add curl to distroless java |

Always: `--interval=30s --timeout=3s --start-period=<boot time> --retries=3`, target `127.0.0.1`, exec form. Kubernetes ignores Docker HEALTHCHECK — mirror it as readiness/liveness probes in the manifest.
