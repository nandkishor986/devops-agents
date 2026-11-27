# InfraCortex — DevOps AI agents for GitHub Copilot & Claude Code

**One click** gives you expert DevOps agents for **Terraform (Azure/AWS)**, **Kubernetes/AKS**, **Docker** and **FinOps** — in **GitHub Copilot** and **Claude Code** — backed by real scanners on your machine, a destructive-command guard, and a self-learning skill memory.

## What you get after installing

| | GitHub Copilot | Claude Code |
|---|---|---|
| Agents | **terraform-engineer · k8s-troubleshooter · docker-engineer · finops-analyst · cortex** in the agent picker — ready immediately | same agents + **overseer**, after one click on **Enable in Claude Code** |
| Skills | `terraform-expert`, `k8s-expert`, `docker-expert`, `finops-expert`, `azure-diagrams` | the same, as `/infracortex:terraform-expert …` |
| Tools | built-in **InfraCortex MCP server** (no `mcp.json`, no Node install): `tf_scan`, `k8s_triage`, `docker_audit`, `docker_verify`, `finops_scan`, `az_price`, `azure_diagram`, `check_command`, `search_skills`, `pull_skill`, `agent_activity` | the plugin's scripts + official Terraform / Azure / Kubernetes MCP servers |
| Safety & learning | Copilot asks before running commands | **guard hook** (blocks destroy / auto-approve / RG deletes), typed reports, **self-learning**, **CortexWeave** skill memory with human review, live on-screen **HUD** |

## Get started (3 clicks)
1. **Install** this extension. The *Get started with InfraCortex* walkthrough opens.
2. **Install missing tools** — checks Git (+ Git Bash on Windows), Python, jq and the scanners (terraform, tflint, trivy, hadolint, kubectl, Azure CLI, Docker) and installs what's missing with winget / Homebrew / apt in a visible terminal. Restart VS Code afterwards.
3. **Enable in Claude Code** (optional) — adds the InfraCortex plugin to Claude Code.

Then:
- **Copilot:** open Copilot Chat → **Agent** mode → pick **terraform-engineer** → *"review infra/ for security"*.
- **Claude Code:** `/infracortex:terraform-expert review the KV module in infra/` · `/infracortex:team . review` · `/infracortex:cortex <task>`.

The status bar shows **InfraCortex ready** or what's missing; click it to re-check.

## Also included: one-click scans (no AI, no tokens)
Right-click a folder → *Terraform: Scan Folder*, *Kubernetes: Review Manifests*, *Terraform: Cost*, *Diagram: Spec from Terraform*; right-click a Dockerfile → *Docker: Audit*, *Build → Run → Diagnose*. Findings land in the **Problems** panel with rule IDs and severities.

## Settings
`devopsAgents.currency` (INR) · `devopsAgents.defaultRegion` · `devopsAgents.bashPath` / `pythonPath` (auto-detected) · `devopsAgents.terraformInit` · `devopsAgents.installOptionalTools`.

## Privacy & security
Everything runs locally with your own credentials; the extension sends nothing anywhere. Tools are only installed after you confirm, in a terminal you can see. Source, issues and security policy: **https://github.com/nandkishor986/infracortex** (MIT).
