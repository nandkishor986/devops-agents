# State & refactor playbook (load only for refactors/state issues)

Always: back up first `terraform state pull > state.backup.$(date +%s).json` (mark this in needs_approval if the human must run it). Prefer declarative blocks (`moved`, `import`, `removed`) over CLI state surgery — they are reviewable in PRs and plan-visible.

| Goal | Declarative (preferred) | CLI fallback |
|---|---|---|
| Rename resource/module | `moved { from = azurerm_x.a  to = azurerm_x.b }` | `terraform state mv` |
| count → for_each | one `moved` per index: `from = x.y[0] to = x.y["web"]` | `state mv 'x.y[0]' 'x.y["web"]'` |
| Move into module | `moved { from = azurerm_x.a to = module.m.azurerm_x.a }` | — |
| Adopt existing Azure resource | `import { to = azurerm_x.a  id = "/subscriptions/.../resourceGroups/rg/providers/..." }` then `terraform plan -generate-config-out=gen.tf` | `terraform import` |
| Stop managing without deleting | `removed { from = azurerm_x.a  lifecycle { destroy = false } }` (TF ≥1.7) | `terraform state rm` |
| Force recreate one resource | `terraform plan -replace=azurerm_x.a` | `taint` (deprecated) |

Verify: plan must show `has moved to` / `will be imported` and **0 to destroy** for refactors. Any destroy in a refactor plan = stop and report.

## Common Azure errors → cause
- `AuthorizationFailed` / 403 → identity lacks role at scope (often needs `User Access Administrator` / RBAC Admin for role assignments). Not a code fix.
- `RequestDisallowedByPolicy` → Azure Policy deny; read the policy name in the error, fix the attribute (tags, location, SKU, public access).
- `already exists - to be managed via Terraform this resource needs to be imported` → use `import {}` block.
- `ResourceGroupNotFound` right after creation → eventual consistency; ensure implicit dependency (reference `.name` from the RG resource, not a string).
- State lock `LeaseAlreadyPresent` → check for a running pipeline first; only then `force-unlock <id>` (needs approval).
- Perpetual diff → provider normalises value (case, ordering, defaults). Match the normalised form or `ignore_changes` that attribute with a comment.
- `Error acquiring the state lock` in ADO with parallel stages → add `lockBehavior: sequential` / environment exclusive lock.
