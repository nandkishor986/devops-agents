# Terraform tests (`terraform test`, Terraform ≥ 1.6; mocks ≥ 1.7)

## When
Every reusable module you write gets tests; roots get plan-mode tests for their validation rules and naming.

## Files
`*.tftest.hcl` next to the module or in `tests/`. Run: `terraform init && terraform test` (`-filter=tests/x.tftest.hcl`, `-verbose`; `-junit-xml=out.xml` for CI on recent versions).

## Shape
```hcl
variables {                       # defaults for every run block
  name     = "demo"
  location = "eastus2"
}

run "plan_names_and_tags" {
  command = plan                  # unit test: no resources created
  assert {
    condition     = azurerm_storage_account.this.public_network_access_enabled == false
    error_message = "storage must not be public"
  }
}

run "rejects_bad_env" {
  command = plan
  variables { env = "qa1" }
  expect_failures = [var.env]     # proves the validation block works
}
```
- `command = plan` → fast unit tests (no cloud cost). Default `apply` → integration tests that create and then destroy real resources in reverse order — run them only in a sandbox subscription/account.
- Each `run` sees earlier runs' state; reference outputs with `run.<name>.<output>`.
- `module { source = "./tests/setup" }` inside a run for fixtures (e.g. a resource group).

## No credentials in CI: mocks
```hcl
mock_provider "azurerm" {
  mock_resource "azurerm_storage_account" {
    defaults = { id = "/subscriptions/0000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/demo" }
  }
}
```
`override_resource` / `override_data` / `override_module` replace one object in one run. Mocked plan-mode suites run anywhere (PR checks) without cloud access.

## What to assert
Security defaults (public access off, TLS, encryption), naming/tag rules, `for_each` keys and counts, conditional resources on/off, validation failures, outputs.

## CI
PR: `terraform fmt -check`, `validate`, `test` (plan + mocks). Main / nightly: integration runs against a sandbox with OIDC credentials; publish JUnit results.
