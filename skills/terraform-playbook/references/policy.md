# Policy as code for Terraform

Pick the engine the team's platform enforces:

| Platform | Engine | Notes |
|---|---|---|
| HCP Terraform / Terraform Enterprise | **Terraform Policy** (`*.policy.hcl`, tests in `*.policytest.hcl`) or **Sentinel** | Terraform Policy is HCL-native; Sentinel → Terraform Policy conversion is a common task. If HashiCorp's `terraform-policy` skill is installed (`terraform@hashicorp`), use it for exact syntax. |
| Anything else (Azure DevOps, GitHub Actions, GitLab) | **OPA / Conftest** on the plan JSON, or **Checkov** custom policies | Runs in the pipeline before apply. |
| Azure-side guardrails | **Azure Policy** (deny/audit/modify) | Complements, doesn't replace, pre-apply checks. |

## OPA / Conftest on a plan (works anywhere)
```bash
terraform plan -out=tfplan && terraform show -json tfplan > plan.json
conftest test plan.json -p policy/
```
```rego
package main
import rego.v1

deny contains msg if {
  some rc in input.resource_changes
  rc.type == "azurerm_storage_account"
  rc.change.after.public_network_access_enabled == true
  msg := sprintf("%s: public network access must be disabled", [rc.address])
}
```

## Writing good policies
- One rule per control, message names the resource address and the fix.
- Map each policy to a rule ID in `contracts/RULES.md` so findings line up with scans.
- Test every policy with a passing and a failing fixture (plan JSON or `.policytest.hcl`).
- Start in advisory/warn mode, then enforce.
