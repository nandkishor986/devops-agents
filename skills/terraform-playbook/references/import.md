# Bring existing resources under Terraform

## Decide the route
1. **Provider supports list resources** (Terraform ≥ 1.14 search): discover with `terraform query`, then generate config + import blocks in bulk.
   Check: `terraform providers schema -json | jq '.provider_schemas[].list_resource_schemas | keys'` (empty → not supported).
2. **Otherwise**: `import` blocks (Terraform ≥ 1.5) + `terraform plan -generate-config-out=generated.tf`.
3. **Azure, many resources**: `aztfexport resource-group <rg>` is an alternative generator; still review like below.

## Search (query) route
```hcl
# discover.tfquery.hcl
list "aws_instance" "web" {
  provider = aws
  config {
    filter { name = "tag:App"  values = ["web"] }
  }
}
```
`terraform query` lists matches; `terraform query -generate-config-out=imported.tf` writes resource + import blocks. Review, then `plan`/`apply` (apply only after the user approves).

## Import-block route
```hcl
import {
  to = azurerm_resource_group.app
  id = "/subscriptions/<sub>/resourceGroups/rg-app-prod"
}
```
Several of the same type: `import { for_each = local.rgs  to = azurerm_resource_group.this[each.key]  id = each.value }` (≥ 1.7).
`terraform plan -generate-config-out=generated.tf` → move the generated blocks into the right files.

## Clean up generated config (always)
Remove computed/read-only and default-valued attributes; replace literal IDs with references; add variables/locals; apply naming and tags from `style-guide.md`. The goal: **plan shows only "import", 0 to add/change/destroy**. Anything else means config ≠ reality — fix config, don't apply changes silently.

## After import
Keep `import` blocks until every environment applied them, then delete them. Never edit state by hand; `terraform state rm`/`mv` only with the user's approval (guard asks).
