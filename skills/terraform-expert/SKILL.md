---
name: terraform-expert
description: Terraform expertise for Azure (azurerm/azapi) and AWS (aws provider 6.x) — reviewing, writing, refactoring and debugging HCL, modules, state, and CI pipelines with OIDC. Use for any .tf/.tfvars work, plan errors, drift, IaC code review, or creating cloud resources like a secure EC2 instance or storage account.
---

> **Learned lessons:** read `references/learned.md` first (short) — rules promoted from past mistakes; they override older guidance below.

# Terraform expert (Azure + AWS)

## Token rules (follow strictly)
1. **Scan before reading.** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/tf-scan.sh <dir> --no-init` first (drop `--no-init` only when validate needs providers). Read only files the digest points at; read by line range, never whole large files.
2. **Docs via MCP, not memory.** For any azurerm/azapi/aws attribute you are not certain of for the pinned provider version, query the `terraform` MCP (provider docs / latest version / module search) or the AWS MCP Server's documentation search when installed. Never invent attributes.
3. Load a reference only when the task needs it:
   - Code review → `references/review-checklist.md`
   - Azure patterns (backend, OIDC, naming, private endpoints, AKS, KV) → `references/azure-patterns.md`
   - AWS patterns (S3 backend, SSO/OIDC, secure EC2 baseline, SG, IAM, IMDSv2) → `references/aws-patterns.md`
   - Refactor/state surgery (moved, import, state mv, count→for_each) → `references/state-refactor.md`
4. Findings use rule IDs from `${CLAUDE_PLUGIN_ROOT}/contracts/RULES.md` (TF-*). Report once per rule per file; group repeats.

## Workflow by task
| Task | Steps |
|---|---|
| review | scan → read flagged ranges → checklist → findings (no edits unless asked) |
| implement | read `versions.tf`/provider pins → MCP-verify resource schema → write minimal module-shaped code → `terraform fmt` → `validate` → `plan -out=tfplan` if backend available → summarise plan (`terraform show -json tfplan \| jq` counts: add/change/destroy + any replace) |
| debug | reproduce with exact command → read error range → check provider version / API version / RBAC (AuthorizationFailed = role, not code) → fix → re-validate |

## Non-negotiables
- Pin `required_version` and providers (`~>` minor). **Check the repo's azurerm major first**: 4.x needs `subscription_id` (or `ARM_SUBSCRIPTION_ID`); **5.0 (GA Jul 2026)** registers NO resource providers by default (register what you use or manage RPs outside TF), disables location/RP-name validation unless the `enhanced_validation` feature is enabled, offers opt-in preflight validation during plan, removes legacy App Service/Function App resources and deprecated properties, and moves storage queue/static-website settings to dedicated resources. Upgrading 4→5: read https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/5.0-upgrade-guide via the terraform MCP before touching code; never bump a major silently.
- `for_each` over maps for keyed collections; `moved {}` for every rename; `prevent_destroy` on stateful resources (KV, SQL, storage with data, AKS in prod).
- Every variable: `type`, `description`, and `validation {}` where the domain is constrained. Secrets: `sensitive = true`, sourced from Key Vault / pipeline secret — never defaults.
- Auth in CI: OIDC / workload identity federation (`use_oidc = true` on Azure, AssumeRoleWithWebIdentity on AWS), never client secrets or access keys in code.
- **AWS**: confirm the account first (`aws sts get-caller-identity`) and state it; pin `hashicorp/aws ~> 6.0`; every EC2 follows the secure baseline in `references/aws-patterns.md` (IMDSv2, private subnet, no SSH, SSM, encrypted gp3, scoped instance profile).
- Remote state: azurerm backend with `use_azuread_auth = true`, one state per env/stack, blob versioning + soft delete on the state account.
- Never run `apply`/`destroy`/`state rm` yourself — put them in `needs_approval`. The guard hook will block/ask anyway.

## Plan reading shortcut (cheap)
```bash
terraform show -json tfplan | jq -r '.resource_changes[] | select(.change.actions!=["no-op"]) | "\(.change.actions|join("+")) \(.address)"' | sort | uniq -c | sort -rn | head -40
```
Any `delete+create` on stateful resources = HIGH finding (TF-REL-002/TF-REL-004) — explain the forcing attribute.
