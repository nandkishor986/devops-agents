# Agents in GitHub Copilot

Already set up by this extension — no `mcp.json`, no files to copy.

1. Open **Copilot Chat** and switch to **Agent** mode.
2. Pick an agent from the dropdown: **terraform-expert**, **kubernetes-expert**, **docker-expert**, **finops-expert** or **devops-expert** (all-in-one).
3. Ask, e.g. *"review infra/ for security"* or *"why does my pod crashloop?"*

The agents use the **InfraCortex** MCP tools (`tf_scan`, `k8s_triage`, `docker_audit`, `finops_scan`, `az_price`, `azure_diagram`, `search_skills`, `pull_skill`, …) and the expert skills (`terraform-playbook`, `kubernetes-playbook`, `docker-playbook`, `finops-playbook`, `azure-diagrams`). Copilot asks before running terminal commands — read each one.
