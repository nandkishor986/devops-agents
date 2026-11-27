# Terraform style & structure (write and review against this)

## File layout (root module or reusable module)
| File | Holds |
|---|---|
| `terraform.tf` / `versions.tf` | `required_version`, `required_providers` (and `backend` in roots) |
| `providers.tf` | provider blocks — **roots only**; reusable modules never configure providers |
| `main.tf` | resources/modules; split by concern (`network.tf`, `aks.tf`, …) when > ~200 lines |
| `variables.tf` · `outputs.tf` · `locals.tf` · `data.tf` | inputs · outputs · computed values · lookups |
| `*.tftest.hcl` (or `tests/`) | tests — see `testing.md` |
Commit `.terraform.lock.hcl`; never commit state, `*.tfvars` with secrets, or `.terraform/`.

## Formatting & block order
- `terraform fmt -recursive` is the formatter of record (2 spaces, aligned `=`).
- Inside a block: meta-arguments first (`count`/`for_each`, `provider`, `depends_on`), then arguments, then nested blocks, `lifecycle` last.
- One blank line between top-level blocks; group related arguments.

## Naming
- `snake_case` for everything; don't repeat the type in the name (`azurerm_storage_account.logs`, not `.storage_account_logs`).
- `this` / `main` for the single instance of a type in a module.
- Cloud names from a `local` (prefix/env/region) so they're consistent and length-checked.

## Variables & outputs
- Every variable: `type` + `description`; `default` only when it's genuinely optional; `validation` blocks for formats, ranges and allowed values; `sensitive = true` for secrets (prefer not passing secrets at all — use Key Vault / Secrets Manager data sources or workload identity).
- Use `object({...})` with `optional()` attributes instead of many loose variables.
- Outputs: `description`, `sensitive` where needed; expose IDs/names consumers need, not whole resources.

## Repetition & conditionals
- Prefer `for_each` (stable keys → no index shifting on removal) over `count`.
- `count = var.enabled ? 1 : 0` only for 0/1 toggles.
- `dynamic` blocks for optional/repeated nested blocks; keep them readable.

## Versions & providers
- `required_version = "~> 1.9"` (or the team's minimum); providers `~>` minor-pinned (e.g. `azurerm ~> 4.40`, `aws ~> 6.0`).
- Azure: `features {}` + `storage_use_azuread = true`; OIDC/workload identity in CI, no client secrets.

## Security defaults (also scanned by `tf-scan.sh`)
No public network access unless asked; private endpoints + private DNS; TLS ≥ 1.2; encryption at rest with platform or customer keys; least-privilege role assignments scoped to the resource; diagnostics to Log Analytics; `prevent_destroy` on stateful prod resources; tags (owner, env, cost-center).

## Review checklist (findings → rule IDs in `contracts/RULES.md`)
fmt clean · validate passes · versions pinned + lock file · no hard-coded secrets/IDs · variables typed/described/validated · `for_each` with stable keys · no provider blocks in modules · public exposure justified · encryption/TLS/identity set · diagnostics + tags · stateful prod protected · outputs minimal · tests for modules.
