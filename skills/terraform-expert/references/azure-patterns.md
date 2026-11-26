# Azure Terraform patterns (load only when implementing)
Verify exact attribute names for the pinned azurerm version via the terraform MCP before writing.

## Providers & backend
```hcl
terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }   # or "~> 5.0" for new stacks — see SKILL.md 5.0 notes
    azapi   = { source = "azure/azapi",       version = "~> 2.0" }
  }
  backend "azurerm" {
    # values via -backend-config=env/<env>.backend.hcl
    use_azuread_auth = true
    use_oidc         = true
  }
}
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id   # required in 4.x; keep explicit in 5.x too
  use_oidc        = true                   # CI; locally az login works
  storage_use_azuread = true
}
```
State account: versioning + soft delete + `Storage Blob Data Contributor` for the pipeline identity only; `shared_access_key_enabled = false`.

## Layout (per stack, env via tfvars + backend-config)
```
infra/
  modules/<concern>/{main,variables,outputs,versions}.tf
  stacks/<stack>/{main,providers,variables,outputs}.tf
  stacks/<stack>/env/{dev,prod}.tfvars  env/{dev,prod}.backend.hcl
```

## Typed inputs (prefer objects with optional over loose maps)
```hcl
variable "aks" {
  type = object({
    kubernetes_version = string
    system_pool = object({ vm_size = string, min = number, max = number, zones = optional(list(string), ["1","2","3"]) })
    user_pools  = optional(map(object({ vm_size = string, min = number, max = number, spot = optional(bool, false), taints = optional(list(string), []) })), {})
  })
  validation {
    condition     = can(regex("^1\\.[0-9]+(\\.[0-9]+)?$", var.aks.kubernetes_version))
    error_message = "kubernetes_version must look like 1.30 or 1.30.4."
  }
}
variable "env" {
  type = string
  validation { condition = contains(["dev","qa","uat","prod"], var.env); error_message = "env must be dev|qa|uat|prod." }
}
```

## Naming + tags
```hcl
locals {
  name = "${var.prefix}-${var.env}-${var.location_short}"
  tags = merge(var.tags, { env = var.env, managed-by = "terraform", owner = var.owner, cost-center = var.cost_center })
}
```

## Private endpoint pattern (KV/Storage/ACR/SQL)
resource → `public_network_access_enabled = false` → `azurerm_private_endpoint` (subresource: vault | blob | registry | sqlServer) → `private_dns_zone_group` pointing at the hub's `privatelink.*` zone (zones usually live in the hub/connectivity subscription → pass zone IDs as inputs, don't create per spoke).

### Example: storage account + blob private endpoint (shape — verify attributes for the pinned azurerm major via MCP)
```hcl
resource "azurerm_storage_account" "this" {
  name                            = local.sa_name            # 3-24 lowercase alnum, globally unique
  resource_group_name             = var.resource_group_name
  location                        = var.location             # e.g. "eastus2"
  account_tier                    = "Standard"
  account_replication_type        = var.env == "prod" ? "ZRS" : "LRS"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  tags                            = local.tags
  lifecycle { prevent_destroy = true }   # prod only
}
resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${local.sa_name}-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  private_service_connection {
    name                           = "psc-${local.sa_name}-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]          # one PE per needed subresource: blob | file | queue | table | dfs | web
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.blob_private_dns_zone_id]   # privatelink.blob.core.windows.net (usually in hub)
  }
  tags = local.tags
}
```
Cost drivers to hand to FinOps: replication (LRS/ZRS/GRS), GB stored + tier, transactions, **each PE ≈ 730 h/month + data processed**, private DNS zone per zone (often already in hub = $0 extra).

## AKS baseline
Entra ID integration + Azure RBAC, `local_account_disabled = true`, `oidc_issuer_enabled = true`, `workload_identity_enabled = true`, system pool `only_critical_addons_enabled = true`, autoscaler on user pools, `azure_policy_enabled = true`, Container Insights/Managed Prometheus, CNI overlay or Cilium, `automatic_upgrade_channel = "patch"` + maintenance window, node OS upgrade channel `NodeImage`. Kubelet identity gets `AcrPull` on ACR (no admin user on ACR).

## Key Vault
RBAC authorization mode (not access policies), purge protection on, soft delete 90d (prod), private endpoint, diagnostics. Secrets consumed via data source or by apps through workload identity — not passed through TF outputs.

## Workload identity (app → Azure without secrets)
user-assigned identity + `azurerm_federated_identity_credential` (issuer = AKS OIDC issuer URL, subject = `system:serviceaccount:<ns>:<sa>`) + scoped role assignment.

## Azure DevOps pipeline (workload identity federation)
```yaml
- task: TerraformTask@5        # or AzureCLI@2 running terraform with ARM_USE_OIDC
  inputs:
    provider: azurerm
    command: plan
    environmentServiceNameAzureRM: sc-wif-<env>
    commandOptions: -var-file=env/$(env).tfvars -out=tfplan -input=false
```
Publish `tfplan` as artifact; apply stage consumes the same artifact behind an Environment approval. Set `ARM_USE_OIDC=true`, `ARM_USE_AZUREAD=true` when calling terraform directly.

## AzAPI for gaps
Use `azapi_resource` / `azapi_update_resource` only when azurerm lacks a property; pin the API version and add a TODO to migrate when azurerm catches up.
