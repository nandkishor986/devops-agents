# Refactor a monolith into modules (no rebuilds)

## 1. Analyse
List resources and group them by lifecycle and ownership (network, data, compute, identity, observability). A module = things created, changed and deleted together. Note cross-group references — they become module inputs/outputs.

## 2. Design the interface
- Inputs: typed `object({...})` with `optional()`; `description` + `validation`; no provider config inside the module.
- Outputs: the IDs/names consumers need.
- `versions.tf` in the module with `required_providers` (no `provider` blocks).
- Azure: check whether an Azure Verified Module already does this (`avm.md`) before writing your own.

## 3. Move code, then state — with `moved` blocks
```hcl
moved {
  from = azurerm_virtual_network.hub
  to   = module.network.azurerm_virtual_network.this
}
```
One `moved` per resource (and per `for_each` key when shapes change: `from = x["a"]`, `to = module.m.x["a"]`). Prefer `moved` over `terraform state mv`: it's reviewed in the PR and applied by every environment's pipeline.

## 4. Prove it's a no-op
`terraform plan` must show **0 to add, 0 to change, 0 to destroy** (only moves). Any replace = wrong address or changed argument — fix before going further.

## 5. Document & test
README (purpose, inputs, outputs, example; `terraform-docs` if the team uses it) and `.tftest.hcl` plan-mode tests (`testing.md`).

## 6. Clean up
Keep `moved` blocks until all workspaces/environments have applied; in shared modules keep them for at least one major version for consumers.
