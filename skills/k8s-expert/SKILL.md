---
name: k8s-expert
description: Kubernetes (AKS-first) troubleshooting, manifest/Helm/Kustomize review and authoring, and cluster setup guidance. Use for CrashLoopBackOff, Pending, OOMKilled, ImagePull errors, networking/DNS/ingress issues, probe failures, RBAC, or writing/reviewing YAML.
---

> **Learned lessons:** read `references/learned.md` first (short) — rules promoted from past mistakes; they override older guidance below.

# Kubernetes expert (AKS-first)

## Token rules
1. **Digest first, never raw dumps.** Use `bash ${CLAUDE_PLUGIN_ROOT}/scripts/k8s-triage.sh -n <ns>` (overview), `-n <ns> -p <pod>` (deep dive), `-A` (cluster), `--manifests <dir>` (static review). Do NOT run `kubectl get -o yaml`, `describe` on many objects, or untailed logs.
2. Prefer the `kubernetes` MCP (read-only) for targeted lookups (one resource, one log stream). The script is cheaper for broad sweeps.
3. Load references only when needed:
   - Troubleshooting → `references/failure-playbook.md`
   - Writing/reviewing manifests or Helm → `references/manifest-standards.md`
4. Findings use K8S-* IDs from `${CLAUDE_PLUGIN_ROOT}/contracts/RULES.md`.

## Troubleshooting loop (hypothesis-driven, stop at root cause)
1. **Scope**: which namespace/workload, since when, what changed (`kubectl rollout history`, recent deploy, node upgrade)?
2. **Triage digest** → pick the single most upstream symptom (Pending before CrashLoop, node before pod, DNS before app).
3. **One hypothesis at a time**, cheapest check that can falsify it. Record evidence lines, not full outputs.
4. **Fix** as a file change (manifest/values/kustomize patch) + `kubectl apply --dry-run=server -f` + `kubectl diff -f`. Live mutation goes to `needs_approval`.
5. **Verify plan**: what to watch after apply (`kubectl rollout status`, the event/metric that should disappear).

## Writing manifests
- Output Kustomize base+overlays or Helm values — no per-env copy-paste.
- Every workload ships with: requests/limits, readiness (+startup for slow boots), securityContext (runAsNonRoot, readOnlyRootFilesystem, drop ALL, seccomp RuntimeDefault, no privilege escalation), PDB, topologySpread, ServiceAccount with `automountServiceAccountToken: false` unless needed, NetworkPolicy, recommended labels, image by digest/semver tag.
- Validate: `kubeconform -strict -summary` (target cluster version) + `kube-linter lint` + `kubectl apply --dry-run=server` when a cluster is reachable.

## Safety
Read-only by default (MCP runs `--read-only`). Never `delete`, `drain`, `scale 0`, `rollout restart` or `apply` without listing it in `needs_approval`. Never print Secret data — `kubectl get secret -o jsonpath='{.data}' | jq 'keys'` for key names only.
