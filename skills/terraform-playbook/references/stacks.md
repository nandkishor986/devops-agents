# Terraform Stacks (HCP Terraform)

## When to suggest them
The same set of root modules is deployed many times (environments × regions × accounts/subscriptions) and the team runs **HCP Terraform**. For local CLI or other platforms (Azure DevOps, GitHub Actions + remote state), stay with workspaces/directories — Stacks need HCP Terraform.

## Files
| File | Contains |
|---|---|
| `*.tfcomponent.hcl` | `required_providers`, `provider` blocks (can be `for_each`), `variable`, `component` (a module + its inputs/providers), `output`, `locals`, `removed` |
| `*.tfdeploy.hcl` | `identity_token` (OIDC to the cloud — no static secrets), `store` (variable sets), `deployment` blocks (one per env/region with its inputs), `deployment_group` + auto-approve rules |
| `.terraform-version` | the Terraform version for the stack |

```hcl
component "network" {
  source    = "./modules/network"
  inputs    = { name = var.name, location = var.location }
  providers = { azurerm = provider.azurerm.this }
}
```
```hcl
deployment "prod_eastus2" {
  inputs = { name = "app-prod", location = "eastus2" }
}
```

## Workflow
`terraform stacks init` / `validate` / `fmt` locally; plans and applies run in HCP Terraform per deployment. Removing a component uses a `removed` block, not deleting code. Keep auto-approve rules narrow (e.g. dev only, no destroys).

If HashiCorp's `terraform-stacks` skill is installed (`terraform@hashicorp` plugin), use it for exact block syntax and linked-stack details.
