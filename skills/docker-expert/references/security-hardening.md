# Container security hardening (load only for security tasks)

## Threat → control map
| Threat | Control | Rule |
|---|---|---|
| Secret leaks in layers/history | BuildKit `--mount=type=secret`, `.dockerignore`, scan with `trivy image --scanners secret`; rotate anything ever baked in (deleting in a later layer does NOT remove it) | DKR-SEC-001/008 |
| Root in container → host escape blast radius | non-root numeric UID, rootless Docker / userns-remap on hosts, K8s `runAsNonRoot` | DKR-SEC-002 |
| Known CVEs | minimal base (distroless/chainguard/alpine), rebuild weekly, `trivy image --ignore-unfixed --severity HIGH,CRITICAL --exit-code 1` gate in CI | DKR-SEC-004/007 |
| Base image drift / tampering | pin by digest, Renovate/Dependabot for digests, verify signatures (`cosign verify`), Docker Official/Verified images only | DKR-SEC-003 |
| Remote script supply chain | download + verify checksum/GPG; never `curl \| sh` | DKR-SEC-006 |
| Privileged runtime | no `--privileged`, no docker.sock, `--cap-drop ALL` + add back only needed (e.g. `NET_BIND_SERVICE`), seccomp default, AppArmor/SELinux on | DKR-SEC-005/009 |
| Writable FS abuse | `--read-only` + tmpfs for /tmp; K8s `readOnlyRootFilesystem` | DKR-SEC-009 |
| Resource DoS | `--memory`, `--cpus`, `--pids-limit`, ulimits | — |
| Provenance unknown | `docker buildx build --sbom=true --provenance=mode=max`, `cosign sign` with keyless OIDC in CI, ACR content trust / Notation | — |

## CVE triage (keeps reports short)
1. Count fixable HIGH/CRITICAL only (`--ignore-unfixed`).
2. If most come from the OS layer → bump base tag/digest (one change fixes many).
3. If from app deps → upgrade the package; cite `PkgName installed→fixed`.
4. Unfixable criticals → document with `.trivyignore` entry + expiry date + justification; never silently ignore.

## Secrets: correct patterns
```dockerfile
# build-time private feed token
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc npm ci --omit=dev
```
`docker build --secret id=npmrc,src=$HOME/.npmrc .`  — ADO: `--secret id=npmrc,env=NPM_TOKEN` style with pipeline secret var.
Runtime secrets: env from orchestrator (K8s Secret via CSI/ESO, Compose `secrets:`), never baked.

## Hardened run (standalone)
```bash
docker run -d --name api \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --cap-drop ALL --security-opt no-new-privileges:true \
  --user 10001:10001 --memory 512m --cpus 1 --pids-limit 200 \
  -p 8080:8080 --restart unless-stopped myacr.azurecr.io/api:1.4.2
```

## Compose hardening snippet
```yaml
services:
  api:
    image: myacr.azurecr.io/api:1.4.2
    read_only: true
    tmpfs: [/tmp]
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    user: "10001:10001"
    deploy: { resources: { limits: { memory: 512M, cpus: "1" } } }
    healthcheck: { test: ["CMD", "/app/healthcheck"], interval: 30s, timeout: 3s, retries: 3 }
    secrets: [db_password]
secrets:
  db_password: { file: ./secrets/db_password.txt }
```

## Host / daemon
Docker CIS benchmark (`docker/docker-bench-security`), `live-restore`, `userns-remap` or rootless mode, `icc=false`, log rotation (`log-opts max-size/max-file`), TLS on remote API (never expose 2375).

## ACR
Admin user disabled, AcrPull via managed identity, private endpoint, Defender for Containers scanning, retention policy for untagged manifests, quarantine/content trust for prod repos.
