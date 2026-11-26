# Rule registry (treat like a Java enum: IDs are stable, never reused)

Format: `<DOMAIN>-<CATEGORY>-<NNN>`. DOMAIN ∈ TF | K8S | DKR. CATEGORY ∈ SEC (security), REL (reliability), COST, MNT (maintainability), COR (correctness), PERF, OPS (operability).
Default severity is shown; agents may raise or lower it by one level with justification in `issue`.
New rule → append with the next free number. Memory files reference these IDs (e.g. "repo X: suppress TF-MNT-004"), so never renumber.

## Terraform
| ID | Sev | Rule |
|---|---|---|
| TF-SEC-001 | CRITICAL | Secret/credential literal in .tf/.tfvars or default of a variable |
| TF-SEC-002 | HIGH | Sensitive variable/output not marked `sensitive = true` |
| TF-SEC-003 | HIGH | Public network access enabled (storage, KV, SQL, ACR, AKS API) without justification |
| TF-SEC-004 | HIGH | NSG/SG rule allows 0.0.0.0/0 or `*` on admin ports (22, 3389, 5985/6, DB ports) |
| TF-SEC-005 | HIGH | Encryption at rest/in transit disabled, TLS < 1.2, HTTP allowed |
| TF-SEC-006 | MEDIUM | Over-privileged role assignment (Owner/Contributor at subscription/RG scope; `*` IAM actions) |
| TF-SEC-007 | MEDIUM | Remote state backend without locking/encryption, or state in VCS |
| TF-SEC-008 | MEDIUM | Static credentials in provider block instead of OIDC/MSI/workload identity |
| TF-REL-001 | HIGH | Provider or module version unpinned (no `required_providers` constraint / module `ref`) |
| TF-REL-002 | HIGH | Stateful resource without `prevent_destroy` or deletion protection |
| TF-REL-003 | MEDIUM | `count` used for a keyed collection (index-shift destroys) — use `for_each` |
| TF-REL-004 | MEDIUM | Resource rename/move without `moved {}` block → destroy/create |
| TF-REL-005 | MEDIUM | Single-zone / no redundancy for prod tier |
| TF-REL-006 | LOW | `ignore_changes` hiding real drift (e.g. `all`) |
| TF-COR-001 | HIGH | `terraform validate` fails / type mismatch |
| TF-COR-002 | MEDIUM | Missing `validation {}` on constrained input (env names, CIDRs, SKUs) |
| TF-COR-003 | MEDIUM | Implicit dependency missing; `depends_on` misuse at module level |
| TF-COR-004 | LOW | Variable lacks `type` (defaults to `any`) |
| TF-MNT-001 | LOW | `terraform fmt` drift |
| TF-MNT-002 | LOW | Variable/output missing `description` |
| TF-MNT-003 | LOW | Hard-coded values that belong in variables/locals (region, names, tags) |
| TF-MNT-004 | LOW | Missing standard tags (env, owner, cost-center, managed-by) |
| TF-MNT-005 | MEDIUM | Module does too much (> ~15 resources across unrelated concerns) |
| TF-COST-001 | MEDIUM | Oversized SKU for non-prod; no autoscale/auto-shutdown |
| TF-COST-002 | LOW | Log retention unbounded / premium tier logs in non-prod |
| TF-OPS-001 | MEDIUM | No diagnostic settings / monitoring for critical resource |
| TF-OPS-002 | LOW | Plan not reviewable in CI (no `-out`, no plan artifact, no policy check) |
| TF-SEC-009 | HIGH | AWS EC2 allows IMDSv1 (`metadata_options.http_tokens` not `"required"`) |
| TF-SEC-010 | HIGH | AWS EC2 gets a public IP / sits in a public subnet without justification (use SSM Session Manager or a bastion-less private subnet) |
| TF-SEC-011 | MEDIUM | AWS EC2 without an IAM instance profile scoped to its job (or with `*` actions / AdministratorAccess) |
| TF-MNT-006 | LOW | Hard-coded AMI ID — resolve via `aws_ssm_parameter` (e.g. `/aws/service/ami-amazon-linux-latest/...`) or a data source |
| TF-OPS-003 | LOW | AWS EC2 without detailed monitoring / CloudWatch agent / termination protection for prod |

## Kubernetes
| ID | Sev | Rule |
|---|---|---|
| K8S-SEC-001 | CRITICAL | `privileged: true`, hostPID/hostNetwork/hostIPC, or hostPath to sensitive paths |
| K8S-SEC-002 | HIGH | Runs as root / missing `runAsNonRoot: true` |
| K8S-SEC-003 | HIGH | `allowPrivilegeEscalation` not false; capabilities not dropped (`ALL`) |
| K8S-SEC-004 | HIGH | Secret values in ConfigMap/env literal/manifest in Git |
| K8S-SEC-005 | MEDIUM | `readOnlyRootFilesystem` not true |
| K8S-SEC-006 | MEDIUM | ServiceAccount token automounted when not needed; RBAC wildcard verbs/resources |
| K8S-SEC-007 | MEDIUM | No NetworkPolicy (default-allow namespace) |
| K8S-SEC-008 | MEDIUM | Image uses `:latest` or no digest for prod |
| K8S-SEC-009 | LOW | seccompProfile not `RuntimeDefault` |
| K8S-REL-001 | HIGH | No resource requests/limits (memory limit especially) |
| K8S-REL-002 | HIGH | No readiness probe on a Service-backed workload |
| K8S-REL-003 | MEDIUM | Liveness probe identical to readiness / too aggressive (restart storms) |
| K8S-REL-004 | MEDIUM | replicas < 2 or no PodDisruptionBudget for HA workload |
| K8S-REL-005 | MEDIUM | No topologySpreadConstraints/anti-affinity across zones |
| K8S-REL-006 | LOW | No `terminationGracePeriodSeconds`/preStop for connection draining |
| K8S-COR-001 | HIGH | Selector/label mismatch (Service ↔ Pod, Deployment selector) |
| K8S-COR-002 | HIGH | Deprecated/removed apiVersion for target cluster version |
| K8S-COR-003 | MEDIUM | Port name/number mismatch between Service, container, probe |
| K8S-MNT-001 | LOW | Missing recommended labels `app.kubernetes.io/*` |
| K8S-MNT-002 | LOW | Copy-paste across envs — use Kustomize overlays/Helm values |
| K8S-COST-001 | MEDIUM | Requests far above observed usage; no HPA where load varies |
| K8S-OPS-001 | MEDIUM | No structured logs/metrics endpoint/annotations for scraping |

## Docker
| ID | Sev | Rule |
|---|---|---|
| DKR-SEC-001 | CRITICAL | Secret in image (ARG/ENV/COPY of creds, .env, keys) — use BuildKit `--secret` |
| DKR-SEC-002 | HIGH | Final stage runs as root (no `USER` non-root numeric UID) |
| DKR-SEC-003 | HIGH | Base image unpinned (`:latest` / no tag / no digest in prod) |
| DKR-SEC-004 | HIGH | Critical/High CVEs with available fix in final image |
| DKR-SEC-005 | HIGH | Runtime: `--privileged`, docker.sock mounted, `--cap-add SYS_ADMIN`, `--pid=host` |
| DKR-SEC-006 | MEDIUM | `curl | sh` / remote ADD without checksum verification |
| DKR-SEC-007 | MEDIUM | Full OS / build tools in runtime image (use distroless/slim/chainguard) |
| DKR-SEC-008 | MEDIUM | No `.dockerignore` (leaks .git, .env, node_modules) |
| DKR-SEC-009 | LOW | Runtime without `--read-only`, `--cap-drop ALL`, `no-new-privileges` |
| DKR-REL-001 | MEDIUM | Shell-form ENTRYPOINT/CMD → no signal forwarding (PID 1) |
| DKR-REL-002 | LOW | No HEALTHCHECK (compose/standalone) |
| DKR-PERF-001 | MEDIUM | Cache-busting layer order (COPY . before dependency install) |
| DKR-PERF-002 | MEDIUM | Single-stage build for compiled language |
| DKR-PERF-003 | LOW | Package manager cache left in layer; separate RUN for update/install |
| DKR-COR-001 | MEDIUM | `apt-get update` in separate layer from install (stale cache) |
| DKR-MNT-001 | LOW | Missing OCI labels (`org.opencontainers.image.source`, version) |
| DKR-MNT-002 | LOW | hadolint warning not covered above |

## FinOps (Azure-first)
| ID | Sev | Rule |
|---|---|---|
| FIN-COST-001 | HIGH | Orphaned resource: unattached managed disk, unassociated public IP, NIC without VM |
| FIN-COST-002 | HIGH | Idle compute: VM/VMSS/AKS node pool with sustained low CPU (<5% p95 over 14d) |
| FIN-COST-003 | MEDIUM | Oversized SKU vs observed utilisation (VM, App Service Plan, SQL DTU/vCore) |
| FIN-COST-004 | MEDIUM | Empty/unused App Service Plan, load balancer without backends, idle App Gateway |
| FIN-COST-005 | MEDIUM | Old snapshots/backups beyond retention policy |
| FIN-COST-006 | MEDIUM | Non-prod running 24×7 without auto-shutdown / scale-to-zero schedule |
| FIN-COST-007 | MEDIUM | Steady-state workload on pay-as-you-go — reservation/savings plan candidate |
| FIN-COST-008 | MEDIUM | Storage in wrong tier / no lifecycle policy (hot data never read) |
| FIN-COST-009 | LOW | Log Analytics ingestion/retention excess (debug logs, no basic/aux tables) |
| FIN-COST-010 | MEDIUM | AKS: requests ≫ usage, no cluster autoscaler, no spot pool for tolerant workloads |
| FIN-COST-011 | HIGH | Terraform change increases monthly cost > threshold without approval (Infracost) |
| FIN-OPS-001 | MEDIUM | Missing cost-allocation tags (env, owner, cost-center, app) |
| FIN-OPS-002 | MEDIUM | No budget/alert on subscription or resource group |
| FIN-OPS-003 | LOW | Azure Advisor cost recommendations not actioned |
