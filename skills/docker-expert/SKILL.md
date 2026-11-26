---
name: docker-expert
description: Docker expertise across Dockerfiles, BuildKit, multi-stage builds, image size/caching, Compose, registries (ACR), runtime hardening and container security (CVEs, secrets, rootless, capabilities, supply chain/SBOM/signing). Use for writing, reviewing, debugging or securing containers.
---

> **Learned lessons:** read `references/learned.md` first (short) — rules promoted from past mistakes; they override older guidance below.

# Docker expert (security-first)

## Token rules
1. **Audit script first**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/docker-audit.sh -f <Dockerfile> [-i <image>] [-c <container>]`. Read the Dockerfile itself (short) but never paste `docker inspect`/`history`/scanner JSON raw.
2. Load references only when needed:
   - Hardening, CVEs, secrets, supply chain → `references/security-hardening.md`
   - Writing/optimising Dockerfiles, Compose, BuildKit, per-language templates → `references/dockerfile-patterns.md`
   - Anything failing at build/run/health → `references/healthcheck-fixes.md` (DIAG → fix table, forbidden fixes)
3. Findings use DKR-* IDs from `${CLAUDE_PLUGIN_ROOT}/contracts/RULES.md`.
4. Docker MCP Toolkit (if connected as `MCP_DOCKER`) is optional — use it for Docker Hub lookups (tags, digests), not for things the CLI does.

## Workflow
| Task | Steps |
|---|---|
| review | audit -f (+ -i if image exists) → map to rules → prioritised findings: secrets > root > CVEs > base pin > size/caching |
| write/optimise | detect language + build tool → pick template → multi-stage, pinned base, non-root numeric UID, exec-form ENTRYPOINT, cache mounts → `.dockerignore` → `docker build --progress=plain` → re-audit → report size before/after |
| debug build | read the failing step only (`--progress=plain` output tail) → cache/context/arch/network cause → fix |
| **fix (build/run/health failing)** | `bash ${CLAUDE_PLUGIN_ROOT}/scripts/docker-verify.sh -f <Dockerfile> -p <port> [--path /healthz]` → first DIAG → playbook fix → re-verify; max 3 iterations; finish with `--hardened` |
| debug runtime (existing container) | `docker-audit.sh -c` → exit code → logs tail → then reproduce with docker-verify |
| security | audit -i with trivy → fixable HIGH/CRITICAL → base bump vs package upgrade → SBOM (`docker buildx build --sbom=true --provenance=mode=max`) → sign (cosign) recommendation |

## Verify gate
Any task that edits a Dockerfile/compose ends with `docker-verify.sh` RESULT PASS (and `--hardened` for prod images), or status BLOCKED with the DIAG line. Lint before build: `docker build --check` (built into verify) + hadolint when present.

## Non-negotiables in anything you write
- `# syntax=docker/dockerfile:1` header; multi-stage; final stage distroless/chainguard/alpine/slim as appropriate.
- Base images pinned to a version tag (+ digest for prod). `USER 10001:10001` (numeric). Exec-form `ENTRYPOINT`.
- Secrets only via `RUN --mount=type=secret,id=...` — never ARG/ENV/COPY.
- Dependency manifests copied and installed before source; `--mount=type=cache` for package caches.
- Runtime flags for anything you suggest: `--read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges --user 10001 --memory --pids-limit`.
- Never suggest `--privileged`, mounting `/var/run/docker.sock`, or `chmod 777`.
