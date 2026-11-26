# Terraform review checklist (load only for reviews)

Work top-down; stop expanding a section once it's clean. Map every issue to a rule ID in contracts/RULES.md.

## 1. Structure & versions
- `versions.tf` pins terraform + providers; lock file committed (`.terraform.lock.hcl`) — TF-REL-001
- Root module = composition only; resources live in child modules with a single concern — TF-MNT-005
- Modules sourced with immutable ref (`?ref=v1.4.2` tag or SHA), registry modules with `version` — TF-REL-001
- No provider blocks inside child modules (pass via `providers = {}`) — TF-COR-003

## 2. Inputs/outputs (the "type system")
- Every variable has `type` (prefer `object({...})` with `optional()` over `map(any)`) — TF-COR-004
- `validation {}` for env names, CIDRs (`can(cidrhost(var.x,0))`), SKUs, regions — TF-COR-002
- `nullable = false` where null is meaningless
- Outputs: only what consumers need; secrets `sensitive = true` — TF-SEC-002

## 3. Security (Azure)
- No literals for secrets; KV data sources or pipeline variables — TF-SEC-001
- `public_network_access_enabled = false` + private endpoint + private DNS zone for KV, Storage, SQL, ACR, Cosmos — TF-SEC-003
- Storage: `min_tls_version = "TLS1_2"`, `https_traffic_only_enabled`, `allow_nested_items_to_be_public = false`, shared key access disabled where possible — TF-SEC-005
- NSG: no `*`/`Internet` source on 22/3389/DB ports; use Bastion / JIT — TF-SEC-004
- RBAC: least privilege at narrowest scope; prefer built-in data-plane roles (Key Vault Secrets User, Storage Blob Data Reader) over Contributor — TF-SEC-006
- AKS: `local_account_disabled = true`, Entra ID RBAC, workload identity + OIDC issuer enabled, private cluster or `api_server_access_profile.authorized_ip_ranges`, Azure Policy add-on — TF-SEC-003/006
- Diagnostic settings → Log Analytics for KV, AKS, App GW, SQL — TF-OPS-001

## 4. Reliability
- Stateful resources: `lifecycle { prevent_destroy = true }` (prod) — TF-REL-002
- Keyed collections via `for_each`; renames via `moved {}` — TF-REL-003/004
- Zones: `zones = ["1","2","3"]` / zone-redundant SKUs for prod — TF-REL-005
- `ignore_changes` only on attributes mutated outside TF (e.g. `tags["LastDeployed"]`, AKS `default_node_pool[0].node_count` with autoscaler) — TF-REL-006

## 5. Correctness
- `terraform validate` clean — TF-COR-001
- No `depends_on` on whole modules unless unavoidable (forces unknowns → perpetual diffs) — TF-COR-003
- `count = var.enabled ? 1 : 0` fine for toggles; reference with `one(resource.x[*].id)`
- Data sources that depend on resources created in the same apply → known-after-apply churn

## 6. Maintainability & cost
- `locals` for naming convention (`"${var.prefix}-${var.env}-${var.location_short}-<type>"`) and merged tags — TF-MNT-003/004
- Non-prod SKUs parameterised; autoscale/auto-shutdown for dev — TF-COST-001
- LA workspace retention set; no premium logs in dev — TF-COST-002

## 7. Pipeline (Azure DevOps / GitHub Actions)
- Stages: fmt → validate → tflint → trivy/checkov → plan (`-out`, publish artifact + Infracost comment) → manual approval (environment check) → apply **that** plan — TF-OPS-002
- Service connection uses workload identity federation; no secrets in variable groups for ARM auth — TF-SEC-008
- State lock respected (no `-lock=false`); concurrency limited per env
