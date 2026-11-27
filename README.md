# infracortex — plug-and-play DevOps agents for Claude Code

[![ci](https://github.com/nandkishor986/infracortex/actions/workflows/ci.yml/badge.svg)](https://github.com/nandkishor986/infracortex/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Contributions welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](CONTRIBUTING.md)

Token-lean **Terraform (Azure-first)**, **Kubernetes/AKS**, **Docker** and **FinOps** subagents, plus **Azure architecture diagrams with official icons**. Each agent has persistent memory, uses official MCP servers, returns a **typed report contract**, and ships with a guard hook that blocks or asks before destructive infra commands.

**Five agents:** `terraform-engineer` · `k8s-troubleshooter` · `docker-engineer` · `finops-analyst` · `cortex` (all four in one) — usable alone, as a parallel team (`/infracortex:team`), in **Claude Code** (CLI, VS Code, Desktop) and in **GitHub Copilot**. They **learn from their own mistakes**, and an **on-screen HUD** shows which agent is working and what it's doing.

Built by Nandu · upinclouds. Open source (MIT) — improvements welcome.

---

## Install (2 commands)

In **Claude Code** (CLI, VS Code extension, or the Code tab in Claude Desktop):

```text
/plugin marketplace add nandkishor986/infracortex
/plugin install infracortex@upinclouds
```
Restart Claude Code. Run `/mcp` to confirm `terraform`, `azure`, `kubernetes` are connected.

**Install scope** (pick one per machine or repo):

| Goal | Command |
|---|---|
| Every repo on this machine | `claude plugin install infracortex@upinclouds` (user scope) |
| One repo, only you | `claude plugin install infracortex@upinclouds --scope local` |
| One repo, whole team | `--scope project`, then commit `.claude/settings.json`; each teammate runs the install once |
| Installed globally, off in one repo | `claude plugin disable infracortex@upinclouds --scope local` |

Local overrides project, and project overrides user. The terminal, VS Code and the Desktop Code tab share these settings.

**Local / no marketplace:** `claude --plugin-dir ./infracortex` (try without installing) or `./install.sh` (copies into `~/.claude`; `--no-mcp`, `--no-hook`, `--uninstall`).

**Claude Desktop chat / claude.ai (skills only, no agents/hooks):** `bash scripts/build-desktop.sh` → upload `dist/*.zip` under Settings → Capabilities → Skills; merge `dist/claude_desktop_config.snippet.json` into `claude_desktop_config.json`; add `https://mcp.draw.io/mcp` as a custom connector.

> **Which surface?** Claude Code (CLI or VS Code extension) is the lightest *and* the only one with subagents, memory and hooks. Use Desktop chat only for quick questions.

### Prerequisites
| Need | Windows | macOS / Linux |
|---|---|---|
| Git Bash (Claude Code on Windows uses it) | `winget install Git.Git` | built-in |
| Python 3 (guard hook, validator, diagrams) | `winget install Python.Python.3.12` | built-in / pkg manager |
| jq | `winget install jqlang.jq` | `brew/apt install jq` |
| Node (Azure + K8s MCP via npx) | `winget install OpenJS.NodeJS.LTS` | `brew install node` |
| Docker (Terraform MCP) | Docker Desktop | Docker |
| `az login` + `az account set -s <sub>` (Azure MCP, FinOps; needs Reader + Cost Management Reader) · kubeconfig (K8s) | | |

**Optional scanners** (scripts skip any that are missing): `terraform tflint trivy checkov infracost kubectl kubeconform kube-linter hadolint`.
**From PyPI:** `pip install python-hcl2` (AST-level Terraform checks instead of grep; recommended), `pip install checkov` (extra IaC policies), `pip install diagrams` + Graphviz for PNG/SVG diagrams.

---


## AWS: "create a secure EC2" end to end

```
You: create a t3.micro EC2 in ap-south-1 for dev, private subnet subnet-0abc in vpc-0def, considering security
```
1. **provision** skill confirms the account (`aws sts get-caller-identity`) and fills gaps (region, env, subnet).
2. **terraform-engineer** writes `infra/<name>/` from the secure baseline in `skills/terraform-expert/references/aws-patterns.md`: aws provider `~> 6.0`, private subnet, no public IP, no SSH (SSM Session Manager), IMDSv2 required, encrypted gp3 root, scoped instance profile, AMI from the SSM parameter, monitoring.
3. Verify gate: `terraform fmt/validate` + `tf-scan.sh` (AST checks TF-SEC-004/005/009/010/011, TF-MNT-006, TF-OPS-003) must be clean, then `terraform plan`.
4. **finops-analyst** prices it: `aws-price.sh ec2 t3.micro --region ap-south-1 --currency INR` + `aws-price.sh ebs gp3 --gb 30` (AWS lists USD; converted and labelled).
5. You get one summary (plan + monthly INR). **Nothing is created until you approve**: the guard hook asks before `terraform apply` and every mutating `aws` command, and denies destructive ones (`terminate-instances`, `s3 rm --recursive`, `iam create-access-key`, …). `--dry-run` passes.

Setup:
```bash
aws configure sso && aws sso login --profile dev && export AWS_PROFILE=dev   # no static keys
/plugin install aws-core@claude-plugins-official                             # optional: official AWS MCP Server (docs + live API)
```
IAM needed: read-only + `pricing:GetProducts` for review/costing; the deploy role (yours, or OIDC in CI) for apply.

## Use

| You type | What happens |
|---|---|
| `/infracortex:tf-review ./infra` | terraform-engineer scans, then reviews and returns a findings table |
| `/infracortex:k8s-debug payments api crashloop` | k8s-troubleshooter triages, finds the root cause, and writes a manifest fix |
| `/infracortex:docker-audit ./Dockerfile myacr.azurecr.io/api:1.2 fix` | docker-engineer audits the file and hardens it |
| "my container goes unhealthy, fix it" | docker-engineer runs the **diagnose → fix → re-verify loop** (below) until the container is healthy under hardened flags |
| `/infracortex:finops-scan --tf ./infra` | finops-analyst runs an Infracost diff vs main |
| "Create a storage account in eastus2 with private endpoints" (or `/infracortex:provision …`) | **provision** workflow: terraform-engineer writes and verifies the code, finops-analyst prices it (Infracost, or Azure Retail Prices with no key), then one summary with the monthly estimate and the approvals needed |
| "What does a D4s_v5 cost in eastus2?" | finops-analyst → `az-price.sh preset vm D4s_v5 --region eastus2` (no login) |
| "Create a private AKS module with workload identity and a KV private endpoint" | terraform-engineer is auto-delegated and verifies attributes through the Terraform MCP |
| "Draw our hub-spoke network from ./infra" | azure-diagrams: `from-tf` → typed spec → editable `.drawio` + PNG, official Azure icons |
| "Add Redis to that diagram and export it to Visio" | azure-diagrams edits the `.drawio` with CLI-Anything's draw.io CLI (`--json`), then exports to `.vsdx` |

You can also call an agent explicitly: `@agent-infracortex:terraform-engineer review modules/aks`.

---

## Why it's light on tokens

1. **Scripts digest, the model reasons.** `scripts/*-scan.sh` run fmt/validate/tflint/trivy/kubectl/hadolint/az graph and print **one line per issue, already tagged with a rule ID**. No raw YAML/JSON enters context.
2. **Progressive disclosure.** Each `SKILL.md` is under 60 lines. Checklists, playbooks and patterns live in `references/` and load only for the task that needs them.
3. **Subagents isolate context.** Scans and file reads stay in the subagent; your main chat gets back a compact JSON report. `omitClaudeMd: true` skips re-loading project CLAUDE.md files.
4. **Slash skills are invisible until used** (`disable-model-invocation: true`), so they cost nothing per turn.
5. **Docs on demand.** The Terraform MCP fetches provider docs for exactly the resource in hand, instead of the model guessing (and then fixing) attributes.
6. **Diagrams as a 30-line JSON spec.** The script owns layout and icon mapping and writes `.drawio`/PNG locally, with no MCP and no tool schemas.

## Extensions: Claude Desktop and VS Code

`bash extensions/build.sh` builds both into `dist/` (needs Node ≥ 18). Each bundles the same scripts and rule registry as the plugin.

| | Claude Desktop extension (`.mcpb`) | VS Code extension (`.vsix`) |
|---|---|---|
| Install | Double-click the `.mcpb`, or Desktop → Settings → Extensions → Install | `code --install-extension dist/infracortex-<ver>.vsix` or Extensions → … → Install from VSIX |
| What you get | 9 MCP tools in Desktop **chat**, running on your machine: `tf_scan`, `k8s_triage`, `docker_audit`, `docker_verify`, `finops_scan`, `az_price`, `azure_diagram`, `validate_report`, `check_command` | Sidebar + right-click + command palette; findings land in the **Problems** panel with rule IDs and severities |
| Settings | workspace folder (tools are locked inside it), currency (INR), bash path, python command | `devopsAgents.currency` (INR), `defaultRegion`, `bashPath`, `pythonPath`, `terraformInit` |
| Uses tokens | yes (it's chat) | no (scripts only) |
| Agents / hooks / memory | no (Claude Code plugin only) | no (use the plugin in the Claude Code panel for those) |

Security in the Desktop extension:
- Every path is resolved inside the chosen workspace; `../` escapes are refused.
- Scripts run with argument arrays, never a shell string.
- Inputs are schema-validated (namespaces, image names, ports, `KEY=VAL`), and an injection such as `ns; rm -rf /` is rejected before anything runs.
- Scans are marked read-only. `docker_verify` builds and runs a temporary container, then removes it.

**Best combo:** the plugin in the Claude Code panel (agents, memory, guard), plus the `.vsix` for one-click scans with Problems-panel results.

### GitHub Copilot (VS Code agent mode)

1. MCP tools: unzip `dist/infracortex-<ver>.mcpb` to `~/.infracortex/mcp-server`, then add to VS Code's user `mcp.json` (Command Palette → *MCP: Open User Configuration*):
   ```json
   { "servers": { "infracortex": { "type": "stdio", "command": "node",
       "args": ["${userHome}/.infracortex/mcp-server/server/index.js"],
       "env": { "DEVOPS_WORKSPACE": "${workspaceFolder}", "DEVOPS_CURRENCY": "INR" } } } }
   ```
2. Agents: `python scripts/make-copilot-agents.py` writes `terraform-engineer`, `k8s-troubleshooter`, `docker-engineer`, `finops-analyst` as `.agent.md` into your VS Code user prompts folder (or `--out .github/agents` for one repo). Pick them from the agent dropdown in Copilot Chat.
3. Limits vs Claude Code: no persistent memory, no SubagentStop contract gate, and **no guard hook** — Copilot asks before running terminal commands, so read each one before approving.

### On-screen agent HUD (see the agents work)
A small always-on-top panel (bottom-right, never steals focus) shows every devops agent that is working **right now**, one card each:
avatar with a spinning progress ring in the agent's colour · name · status pill (**Running / Stalled / Passed / Warning / Failed / Blocked / Idle**) · *where* it runs (`VS Code · <project> · 1m 12s`) · the task it was given (or its final summary) · its last two steps with a live marker (red = that step failed) · steps and errors recorded for learning · an activity bar. Collapse ⌄ or close × in the header; drag to move.

What feeds it — and what it can't see:
| Client | Shown | How |
|---|---|---|
| Claude Code (VS Code panel, CLI, Desktop Code tab) | every step of every devops agent | plugin hooks (SubagentStart, PreToolUse, PostToolUseFailure, SubagentStop) |
| GitHub Copilot / Claude Desktop chat | each `infracortex` MCP tool call (`tf_scan`, `docker_audit`, …) as an "Idle/Running" card labelled with the client | the MCP server reports its own tool calls |
| Copilot's own file reads/edits | not shown | Copilot has no hook API |

A card with no activity for 5 min shows **Stalled**; it disappears after 30 min (dead session). Windows: custom-drawn WinForms (`scripts/hud.ps1`, no install); macOS/Linux: tkinter (`scripts/hud.py`). Off: `DEVOPS_HUD=off`.

### The combined `cortex`
One agent with all four skill sets (Terraform, Kubernetes, Docker, FinOps) in a single context — loads only the skills a task touches, checks the seams between them (image tag ↔ manifest, ACR ↔ AKS identity, HEALTHCHECK ↔ probes, SKU ↔ cost), and reports findings from any domain (`"agent":"devops"`). Use it for small/medium cross-domain work: `/infracortex:cortex <task>` or "use the devops agent to …". For big reviews use `/infracortex:team` (parallel specialists). In Copilot it appears as **cortex** in the agent picker.

### Self-learning (agents don't repeat mistakes)
1. **Capture (automatic, no tokens):** hooks record every failed command, guard block and contract-rejected report of a devops agent in `~/.infracortex/learning/<agent>.json`, normalised so "same error, different line/path" counts as the same mistake.
2. **Teach (next run):** on the agent's next start, only *new* or *repeated* mistakes are injected (≤ 6 lines; nothing when there's nothing new). The agent writes a `- LESSON: <situation> → <do instead>` line into its persistent memory (`~/.claude/agent-memory/infracortex-<agent>/MEMORY.md`, `## Lessons`). A mistake that comes back after a lesson is flagged **REPEATED ×N** and the agent must make the lesson more specific.
3. **Promote to skills:** `/infracortex:learn` shows mistakes vs lessons per agent; `/infracortex:learn all --promote` moves proven lessons into `skills/<domain>-expert/references/learned.md`, which every run reads first — commit it and every machine gets them.
Off: `DEVOPS_LEARN=off`. Nothing secret is stored (errors are normalised; lessons must be generic).

### Team mode (agents together or alone)
Each agent works alone (`/infracortex:tf-review`, or "use docker-engineer to …"). Together: `/infracortex:team [dir] [goal]` detects Terraform / Kubernetes / Docker in the folder, runs the matching agents **in parallel**, routes each agent's `handoff:<agent>: …` items to the right agent in a second wave, and returns one merged, deduped findings table with cross-cutting issues.

### Watching an agent work
- **Claude Code panel (VS Code) or Claude Desktop Code tab:** every file read, command and edit appears live; expand a subagent's row to see its steps.
- **Copilot agent mode:** each MCP tool call (`tf_scan`, …) shows its input and output in chat.
- **VS Code extension:** *Output → InfraCortex* streams the script output; results land in *Problems*.

## Self-healing Docker loop

`scripts/docker-verify.sh` builds the image (running BuildKit `docker build --check` first), runs it, waits for the health check, and prints only `DIAG` codes with evidence and a `HINT`:

`HC_CMD_MISSING · HC_PORT_MISMATCH · HC_CONN_REFUSED · HC_TIMEOUT · HC_HTTP_ERROR · HC_NEVER_PASSED · BIND_LOCALHOST · RUN_FAIL · EXIT_127/126/OOM · EXITED_CLEAN · RO_FS · PERMISSION · BUILD_COPY_MISSING · BUILD_CMD_NOT_FOUND · BUILD_NETWORK · BUILD_ARCH`

The docker-engineer applies one fix per iteration from `references/healthcheck-fixes.md`, re-verifies (up to 3 times), then re-runs with `--hardened` (read-only filesystem, all capabilities dropped, no-new-privileges). It is **forbidden** to "fix" by removing the HEALTHCHECK, running as root, adding privileges, installing curl into distroless images, or masking failures. If the real fix needs app code, it reports BLOCKED with the exact change.

`tests/docker_fix_loop.sh` proves it against real containers: 7 broken Dockerfiles go diagnosed → fixed → PASS (also runs in CI).

## Typed contract (the "type-safe" part)

Every agent's final message is an **AgentReport v1** (`contracts/report.schema.json`), and **rule IDs work like enums** (`contracts/RULES.md`: `TF-SEC-003`, `K8S-REL-001`, `DKR-SEC-002`, `FIN-COST-001`…).
- Stable IDs → memory can say `repo-x: suppress TF-MNT-004` in a few tokens, and CI can gate on `sev`.
- `scripts/validate_report.py` checks enums, the ID↔agent domain, length caps and invariants (`PASS` with a HIGH finding is rejected). Use it in CI: `validate_report.py --extract transcript.md`.
- The diagram spec is typed too: unknown node types, dangling edges, and nodes placed twice fail with exact paths.
- **Enforced at runtime:** the `SubagentStop` hook (`scripts/contract_gate.py`) validates every agent's final report. A malformed report, plain prose, or `DONE` with changed files but no `verify.passed: true` is **sent back to the agent** to correct (once; no infinite loops).

**Java-style mapping**, for the "type-safe like Java" idea:

| Java | Here |
|---|---|
| `enum Severity {CRITICAL, HIGH…}` | `Severity`, `Status`, `Agent`, `Task` enums in `validate_report.py` + schema `enum`s |
| `record Finding(String id, Severity sev, …)` | frozen dataclasses / schema objects with `additionalProperties: false` |
| enum constants for rules | `RULES.md` IDs (`TF-SEC-003`), regex-checked, never renumbered |
| constructor invariants / `IllegalStateException` | cross-field invariants: PASS ⇒ no HIGH; DONE + files changed ⇒ `verify.passed` |
| deserializer that throws | `contract_gate.py` rejects the agent's output and makes it retry |
| compile + unit tests in CI | `tests/` (27 unit tests) + CI on every push |

An LLM's text can't be compiled. What we *can* do is the equivalent of strict deserialization at the boundary: reject anything that doesn't fit the type and make the producer redo it.

## Optional: TypeSafe Jev as a typed decision layer

[Jev](https://composio.dev/content/typesafe-jev-guide-and-best-practical-usecases) (TypeSafe AI) is a "System One" model. It doesn't write text: it answers predefined questions with typed choices and calibrated probabilities, so its output can't break a schema.

Here it's an **optional second opinion inside the guard hook**, used only for commands the deterministic rules don't recognise (the gray zone; known read-only commands skip it):

| Question | Type | Effect |
|---|---|---|
| `risk` | Choice: safe / risky / destructive | destructive ≥ 0.85 → **deny** · risky/destructive ≥ 0.60 → **ask** |
| `remote_exec` | Noul (yes-probability) | ≥ 0.70 → ask (catches `curl … \| sh`) |
| `prod` | Noul | ≥ 0.70 → ask |
| `exfil` | Noul | ≥ 0.80 → deny |

Jev can only make things **stricter**. It never approves anything, and any error, timeout or missing key falls back to the normal flow. Secrets (passwords, tokens, `KEY=` env values, URL credentials, SAS signatures) are redacted before the command is sent.
```bash
pip install typesafe-sdk
export TYPESAFE_API_KEY=...        # separate TypeSafe account, billed per input token; NOT included in Claude Pro
export DEVOPS_JEV=off              # disable per shell
```
Without a key, nothing changes and nothing leaves your machine.

## Currency (INR by default)
FinOps estimates use the plugin setting **Cost currency** (default **INR**). It's asked when the plugin is enabled and can be changed in `/config`; with `install.sh`, set `DEVOPS_CURRENCY=INR`.
- `az-price.sh … --currency INR` returns Microsoft's native INR list prices (no conversion).
- `az-price.sh fx INR` derives the USD→INR rate from the same meter in both price lists. It's used to convert Infracost output (USD) and any actual cost billed in another currency, and the report says so whenever it converts.
- Actual cost from Cost Management is reported in your subscription's billing currency as-is.

## Running on Claude Pro

All four agents are pinned to `model: sonnet` with `effort: medium`. Claude Code's default on Pro is now Opus, which uses limits several times faster, so delegated work runs on the cheaper model no matter what the main session uses.
- Main session: `/model sonnet` for day-to-day work, or `/model opusplan` (Opus plans, Sonnet executes).
- Disable MCP servers you aren't using in `/mcp` (each server's tool schemas cost tokens every turn).
- Evals spend real usage. Run `--tag smoke --runs 1 --ablation none`, and only when you change prompts.

## Evals (measure the agents, don't trust vibes)
```bash
claude plugin eval . --scaffold --tag smoke --runs 1 --ablation none          # TF + K8s reviews, no-delegation check
claude plugin eval . --scaffold --case docker-fix-unhealthy --runs 1 \
  --allow-tools Edit Write "Bash(bash *)" "Bash(docker *)"                      # needs Docker; on Windows run under WSL2
```
Cases check that agents find seeded issues by rule ID, delegate only when it pays off (trivia must not spawn an agent), and fix a broken Dockerfile without going root or dropping the health check.

## Memory

`memory: user` gives each agent `~/.claude/agent-memory/<agent>/MEMORY.md`, shared across all your repos. Agents store only durable facts (repo conventions, cluster quirks, approved suppressions, gotchas → fixes), keep the file under 60 lines, and never store secrets, IDs or IPs. For per-repo memory committed to Git, change to `memory: project`.

## MCP servers (official)

| Server | Source | Mode |
|---|---|---|
| `terraform` | HashiCorp `hashicorp/terraform-mcp-server` (pinned 1.1.0) | registry/provider docs; set `TFE_TOKEN` for HCP TF |
| `azure` | Microsoft `@azure/mcp` | uses your `az login` identity, so RBAC limits apply |
| `kubernetes` | `kubernetes-mcp-server` (containers org, pinned 0.1.3) | **read-only** via `config/kubernetes-mcp.toml` (0.1.0 removed the `--read-only` flag), Secrets denied; fixes go through files and the guard. It hangs on start if your IP isn't in the cluster's API allow-list. |
| `drawio` (opt-in) | jgraph official hosted `https://mcp.draw.io/mcp` | off by default; content goes to draw.io; enable with `claude mcp add --transport http drawio https://mcp.draw.io/mcp` |
| Docker (optional) | Docker MCP Toolkit: `docker mcp client connect claude-code` | Docker Hub lookups |

Disable any server you don't use in `/mcp` to save tool-schema tokens.

## Diagrams + CLI-Anything (draw.io)

`scripts/azdiagram.py` turns one typed spec into **`.drawio`** (nested subscription/VNet/subnet containers, draw.io's built-in official Azure icons, no dependencies) or **PNG/SVG** (`pip install diagrams` + Graphviz). All 52 node types are tested against both icon sets.

For editing and exporting existing `.drawio` files, the skill uses [HKUDS CLI-Anything](https://github.com/HKUDS/CLI-Anything)'s draw.io CLI when it's installed. It works through JSON output, with no MCP schemas, and exports to PNG, PDF, SVG and **Visio .vsdx** (export needs draw.io Desktop).
```text
/plugin marketplace add HKUDS/CLI-Anything            # optional: CLI generator for other GUI apps
pip install "git+https://github.com/HKUDS/CLI-Anything.git#subdirectory=drawio/agent-harness"
```
Before installing third-party code, read it. The draw.io harness is about 4k lines of Python with three dependencies (click, prompt-toolkit, defusedxml), and it only shells out to the draw.io binary.

## Guard hook

`scripts/guard.py` runs before every Bash call:
`scripts/contract_gate.py` runs when one of these agents stops and enforces the typed report.

- **Denies:** `terraform destroy`, `apply -auto-approve`, `state push`, namespace/bulk `kubectl delete`, `az group delete` and deletion of core resources, volume prune.
- **Asks:** apply/import/state rm, kubectl mutations, helm install/upgrade, `az … create|delete|update|scale`, docker push/rm/privileged runs.
- `--dry-run` and `--what-if` always pass. Read-only commands always pass. Bypass for one shell: `export DEVOPS_GUARD=off`.

## Layout
```
.claude-plugin/{plugin,marketplace}.json   .mcp.json   hooks/hooks.json
agents/      terraform-engineer · k8s-troubleshooter · docker-engineer · finops-analyst
skills/      terraform-expert · k8s-expert · docker-expert · finops-expert · azure-diagrams   (knowledge + references/)
             provision (multi-agent workflow) · tf-review · k8s-debug · docker-audit · finops-scan (entry points)
scripts/     tf-scan · tf_inspect.py · k8s-triage · docker-audit · docker-verify · finops-scan · az-price · azdiagram.py
             guard.py · jev_judge.py · contract_gate.py · validate_report.py · build-desktop
contracts/   report.schema.json · RULES.md          examples/  hub-spoke-aks.{json,png,drawio}
tests/       test_contracts.py (unit) · docker_fix_loop.sh + fixtures/ (real containers) · az_price_test.sh     evals/  plugin eval suite
extensions/  claude-desktop/ (.mcpb MCP server) · vscode/ (.vsix) · build.sh → dist/
```

## Extend
- New rule: append to `contracts/RULES.md` with the next number. Never renumber.
- New diagram icon: add to `TYPES` in `scripts/azdiagram.py` (`python3 scripts/azdiagram.py types` lists them; tests verify every class exists).
- New agent: copy an agent file, keep the Start / Tools / Memory / Output sections, and add a `DOMAIN` to the schema and validator.
- Bump versions: edit `.claude-plugin/plugin.json` `version`; users get it via `/plugin update`.

## Privacy
Scripts and agents run locally against your credentials. If you enable Jev, redacted gray-zone shell commands are sent to TypeSafe's API. Diagrams are generated locally by default. Only the opt-in hosted draw.io MCP sends diagram XML to draw.io ([privacy policy](https://www.drawio.com/privacy)). MCP servers run with your identity, so scope your `az`/kube contexts accordingly.

## Contributing
Issues and pull requests are welcome — new rules, better fixes, more clouds/tools, and especially **lessons your agents learned** (`/infracortex:learn all --promote` → PR with `skills/*/references/learned.md`). Read [CONTRIBUTING.md](CONTRIBUTING.md) first; report security problems privately ([SECURITY.md](SECURITY.md)). Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License
[MIT](LICENSE)
