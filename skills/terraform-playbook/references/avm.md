# Azure Verified Modules (AVM)

## Use them (writing Azure infra)
Microsoft-maintained modules on the Terraform Registry:
- Resource modules: `Azure/avm-res-<provider>-<resource>/azurerm` (e.g. `avm-res-storage-storageaccount`, `avm-res-keyvault-vault`, `avm-res-network-virtualnetwork`).
- Pattern modules: `Azure/avm-ptn-<pattern>/azurerm` (landing-zone style compositions).
Pin `version` exactly or `~>` minor; read the module's README inputs on the Registry (Terraform MCP) instead of guessing.

They share one interface, which makes reviews quick:
`name`, `location`, `resource_group_name`, `tags`, `lock`, `role_assignments`, `diagnostic_settings`, `private_endpoints`, `managed_identities`, `customer_managed_key`, `enable_telemetry`.
- Set `enable_telemetry` explicitly per the organisation's policy (it defaults to on).
- Private endpoints + private DNS via the module's `private_endpoints` input rather than hand-written resources.

## Prefer AVM when
A resource module exists for the service and the team doesn't have its own standard module. Write a custom module when AVM lacks the feature, or the org mandates in-house modules (then follow the conventions below anyway).

## Conventions worth copying into your own Azure modules
- `snake_case`; resources then data sources in a stable order; meta-arguments first.
- Optional child resources: `count = var.x == null ? 0 : 1` (null comparison), or `for_each` over a map.
- Optional nested blocks: `dynamic` with `for_each = var.x == null ? [] : [var.x]`.
- Defaults: `coalesce()` / `try()` rather than nested conditionals.
- `lifecycle { ignore_changes = [...] }` only with a comment explaining why.
- No `provider` blocks inside modules; outputs `resource_id` (and `resource` when consumers need it).
- Variables: required first, then optional; each with `type`, `description`, `validation` where it adds safety.
