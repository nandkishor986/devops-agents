#!/usr/bin/env bash
mkdir -p infra && cat > infra/main.tf <<'TF'
terraform {
  required_providers { azurerm = { source = "hashicorp/azurerm" } }
}
variable "env" { default = "dev" }
resource "azurerm_key_vault" "kv" {
  name                          = "kv-demo"
  location                      = "centralindia"
  resource_group_name           = "rg-demo"
  tenant_id                     = "00000000-0000-0000-0000-000000000000"
  sku_name                      = "standard"
  public_network_access_enabled = true
}
TF
