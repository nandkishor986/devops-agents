# InfraCortex — self-learning DevOps agents for Claude Code and GitHub Copilot

[![ci](https://github.com/nandkishor986/infracortex/actions/workflows/ci.yml/badge.svg)](https://github.com/nandkishor986/infracortex/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Contributions welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](CONTRIBUTING.md)

Token-lean AI agents for **Terraform (Azure-first, AWS)**, **Kubernetes/AKS**, **Docker** and **FinOps** that review, fix and build infrastructure code, return **typed reports**, refuse destructive commands without your approval, **learn from their own mistakes**, and keep a shared skill memory (**CortexWeave**) curated by a monitor agent (**overseer**). A live on-screen HUD shows which agent is working and what it's doing.

Built by Nandu · upinclouds · MIT licensed · contributions welcome.

**Contents:** [Agents](#the-agents) · [Prerequisites](#prerequisites) · [Quick start](#quick-start) · [Use in Claude Code](#use-in-claude-code) · [Use in GitHub Copilot](#use-in-github-copilot-vs-code) · [CortexWeave + overseer](#cortexweave-and-the-overseer-shared-skill-memory) · [Configuration](#configuration) · [Troubleshooting](#troubleshooting) · [Update / uninstall](#update-and-uninstall) · [Reference](#reference)

---

## The agents

| Agent | Does | Ask it / command |
|---|---|---|
| `terraform-engineer` | Review, write, refactor, debug Terraform (azurerm/azapi, aws 6.x), state, IaC pipelines with OIDC | `/infracortex:tf-review ./infra` · "create a private AKS module with workload identity" |
| `k8s-troubleshooter` | Root-cause failing pods (CrashLoop, Pending, OOMKilled, ImagePull), networking, RBAC; write manifest fixes | `/infracortex:k8s-debug payments api crashloop` |
| `docker-engineer` | Dockerfile/Compose review, hardening, image size, CVEs; diagnose → fix → verify loop | `/infracortex:docker-audit ./Dockerfile` · "my container goes unhealthy, fix it" |
| `finops-analyst` | Waste, rightsizing, Infracost diffs, price lookups (Azure/AWS) — read-only | `/infracortex:finops-scan --tf ./infra` · "what does a D4s_v5 cost in eastus2?" |
| `cortex` | All four skill sets in one context, for small/medium cross-domain tasks | `/infracortex:cortex containerise the app, write the AKS manifest and ACR Terraform` |
| `overseer` | Monitors every agent's runs and weaves the worth-learning ones into CortexWeave skills | `/infracortex:weave` · "what have my agents been doing?" |

More: `/infracortex:team [dir] [goal]` runs the specialists **in parallel** and routes their hand-offs · `/infracortex:provision <what>` creates infra end to end (code + verify + price) · `/infracortex:learn` reviews lessons · diagrams: "draw our network from ./infra" (official Azure icons, `.drawio`/PNG).

## Prerequisites

| Need | Windows | macOS / Linux |
|---|---|---|
| Claude Code (CLI, VS Code extension, or Desktop Code tab) **and/or** VS Code with GitHub Copilot | | |
| Git (+ Git Bash on Windows — the scripts are bash) | `winget install Git.Git` | built-in |
| Python 3.10+ (hooks, validator, CortexWeave, diagrams) | `winget install Python.Python.3.12` | built-in / package manager |
| Node 18+ (Azure/Kubernetes MCP via npx, Copilot MCP server) | `winget install OpenJS.NodeJS.LTS` | `brew install node` |
| jq | `winget install jqlang.jq` | `brew/apt install jq` |
| Docker (Terraform MCP, Docker agent's verify loop) | Docker Desktop | Docker Engine |
| Cloud access as needed: `az login` (Reader + Cost Management Reader), `aws sso login`, a kubeconfig | | |

Optional scanners (skipped if missing): `terraform tflint trivy checkov infracost kubectl kubeconform hadolint` · `pip install python-hcl2` (recommended: AST-level Terraform checks) · `pip install diagrams` + Graphviz (PNG diagrams).

## Quick start

**One click (recommended):** install the **InfraCortex** extension in VS Code — from the Marketplace once published, or now from a release `.vsix` (Extensions → ⋯ → *Install from VSIX…*). The *Get started* walkthrough opens and:
1. **Install missing tools** — checks and installs Git (+ Git Bash), Python, jq and the scanners with winget / Homebrew / apt;
2. the agents, skills and MCP tools are **already in GitHub Copilot** (Agent mode → pick an agent);
3. **Enable in Claude Code** — one click adds the plugin, then use `/infracortex:terraform-expert …`, `/infracortex:team . review`.

**Claude Code only (no VS Code):**
```text
/plugin marketplace add nandkishor986/infracortex
/plugin install infracortex@upinclouds
```
Restart Claude Code, open a project, then try: `/infracortex:team . review`. A HUD card pops up bottom-right for each agent while it works.

---

## Use in Claude Code

Works the same in the **terminal (`claude`)**, the **VS Code Claude Code panel** and the **Code tab of Claude Desktop** — they share `~/.claude` settings, so install once.

**Install scope**

| Goal | Command |
|---|---|
| Every repo on this machine | `claude plugin install infracortex@upinclouds` (user scope) |
| One repo, only you | `claude plugin install infracortex@upinclouds --scope local` |
| One repo, whole team | `--scope project`, commit `.claude/settings.json`; each teammate installs once |
| Off in one repo | `claude plugin disable infracortex@upinclouds --scope local` |

Try without installing: `claude --plugin-dir ./infracortex`. No marketplace: `./install.sh` (copies into `~/.claude`; `--no-mcp`, `--no-hook`, `--uninstall`).

**Three ways to use an agent**
1. **Slash commands** (cheapest, predictable): `/infracortex:tf-review ./infra`, `/infracortex:team . security`, `/infracortex:cortex <task>`, `/infracortex:weave`.
2. **Plain language** — Claude delegates automatically: "review the Terraform in infra/ for security", "why is the payments pod crashlooping?".
3. **By name**: `@agent-infracortex:terraform-engineer review modules/aks` or "use cortex to …".

**What you get in Claude Code (and not elsewhere):** subagents with their own context, persistent memory per agent, the **guard hook** (denies `terraform destroy`, `apply -auto-approve`, `az group delete`, namespace deletes…; asks before any apply), the **contract gate** (typed AgentReport), **self-learning**, **CortexWeave** harvesting, and the full-detail HUD. Check MCP servers with `/mcp` (`terraform`, `azure`, `kubernetes`).

**Tip:** for a one-line fix say "do it here, don't delegate" — an agent re-reads context from scratch, which costs more for tiny tasks.

## Use in GitHub Copilot (VS Code)

**With the InfraCortex extension (recommended):** nothing to configure. The extension contributes the agents (`chatAgents`), the expert skills (`chatSkills`) and the InfraCortex MCP server (`mcpServerDefinitionProviders`, run on VS Code's own Node). Open Copilot Chat → **Agent** mode → pick **terraform-engineer**, **k8s-troubleshooter**, **docker-engineer**, **finops-analyst** or **cortex** → ask, e.g. "review infra/ for security". Copilot shows each tool call with its input and output.

**Manual setup (without the extension):**
1. Build the MCP server (Node 18+): `bash extensions/build.sh`, unzip `dist/infracortex-<ver>.mcpb` to `~/.infracortex/mcp-server`, and add it to VS Code's user `mcp.json` (Command Palette → *MCP: Open User Configuration*):
   ```json
   { "servers": { "infracortex": { "type": "stdio", "command": "node",
       "args": ["${userHome}/.infracortex/mcp-server/server/index.js"],
       "env": { "DEVOPS_WORKSPACE": "${workspaceFolder}", "DEVOPS_CURRENCY": "INR", "DEVOPS_CLIENT": "Copilot (VS Code)" } } } }
   ```
2. `python scripts/make-copilot-agents.py` writes the agents into your VS Code user prompts folder (or `--out .github/agents` for one repo).

MCP tools available to Copilot: `tf_scan` · `k8s_triage` · `docker_audit` · `docker_verify` · `finops_scan` · `az_price` · `azure_diagram` · `validate_report` · `check_command` · `search_skills` · `pull_skill` · `agent_activity`.

**Differences from Claude Code:** no persistent agent memory, no guard hook (Copilot asks before running terminal commands — read each one), no contract gate, and the HUD shows only the MCP tool calls (Copilot has no hook API). Copilot agents *read* CortexWeave skills; weaving new ones happens in Claude Code via the `overseer`.

**Optional:** the VS Code extension (`code --install-extension dist/infracortex-<ver>.vsix`) adds one-click scans (sidebar, right-click, Problems panel) with no AI and no tokens. The same `.mcpb` installs in **Claude Desktop** (double-click) to use the tools in Desktop chat.

---

## CortexWeave and the overseer (shared skill memory)

Agents already learn one-line **lessons** from their own mistakes. CortexWeave goes further: it turns real runs into **reusable procedures** that every agent — in Claude Code or Copilot — can look up.

```
 WRITE (after a run, in the background)                           READ (at the start of a task, the agent chooses)
 agent finishes ──► hooks record the run in the activity log      agent ──► search_skills("terraform validate location")
               └──► selector: failed steps? rejected report?               ◄── descriptions only (cheap)
                    BLOCKED? very long run? ──► harvest queue      agent ──► pull_skill("fix-azurerm-missing-location")
 overseer ──► judges each queued run, skips one-offs,                      ◄── the full procedure, versioned
              weaves a capsule (procedure, heuristics, failure modes, check, stop condition)
              ──► validated (structure, secrets/IDs/IPs, dangerous steps) ──► saved for review
 you ──► /infracortex:weave review ──► approve ──► active: now searchable by every agent
```

- **Monitor:** every agent run is logged (agent, project, status, steps, failed calls, report severity mix). `/infracortex:weave stats` or Copilot's `agent_activity` shows it per agent.
- **Harvest:** `/infracortex:weave` (or "overseer, harvest the queue") reviews the queue and weaves or improves skills. Run it after a batch of agent work, e.g. weekly.
- **Review (required):** new skills are saved as *awaiting review* and no agent can find them until you approve them — `/infracortex:weave review` shows each one in full; `approve <slug>` / `reject <slug>`. This keeps text from a malicious repo or tool output from turning into instructions other agents follow.
- **Safety built in:** run records are redacted before they're stored (secrets, tokens, cloud IDs, public IPs); capsules containing any of those, or dangerous steps (pipe-to-shell, auto-approve/destroy, disabling the guard, prompt-injection, exfiltration), are rejected; writes are locked and self-repairing; activity is kept 90 days.
- **Use:** every agent's first step is a CortexWeave search; it pulls a skill only when one clearly fits. Nothing is injected.
- **Inspect:** `/infracortex:weave list`, `/infracortex:weave pull <slug>`, or the files under `~/.infracortex/cortexweave/skills/`.
- **Share:** a generic, secret-free skill that helped you is a great contribution (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## More features
- **Self-learning:** failed commands, guard blocks and rejected reports are recorded per agent; the next run is told about new or REPEATED mistakes and writes a LESSON to its memory; `/infracortex:learn all --promote` moves proven lessons into `skills/*/references/learned.md`.
- **Team mode:** `/infracortex:team` picks agents by what the folder contains, runs them in parallel, routes `handoff:` items, and merges one deduped findings table.
- **HUD:** always-on-top panel (never steals focus): agent, status pill (Running / Stalled / Passed / Warning / Failed / Blocked / Idle), source (`VS Code · project · 1m 12s`), task, last steps, errors recorded for learning. Windows WinForms (`scripts/hud.ps1`), macOS/Linux tkinter (`scripts/hud.py`).
- **Typed reports + guard + diagrams + Docker self-healing loop** — see [Reference](#reference).

## Configuration

| Setting | Default | What it does |
|---|---|---|
| `INFRACORTEX_HOME` | `~/.infracortex` | where HUD state, the learning journal and CortexWeave live |
| `DEVOPS_HUD=off` | on | disable the on-screen HUD |
| `DEVOPS_LEARN=off` | on | disable mistake recording / lesson prompts |
| `INFRACORTEX_WEAVE=off` | on | disable CortexWeave activity logging and harvesting |
| `INFRACORTEX_WEAVE_RETENTION_DAYS` | 90 | how long the CortexWeave activity log is kept |
| `INFRACORTEX_WEAVE_AUTO_APPROVE=1` | off | skip human review of new skills (not recommended on shared machines) |
| `DEVOPS_GUARD=off` | on | disable the destructive-command guard (not recommended) |
| currency (plugin option) | INR | FinOps currency — `/plugin configure infracortex@upinclouds` |
| `TFE_TOKEN`, `TFE_ADDRESS` | — | HCP Terraform access for the Terraform MCP |

## Data and privacy
Everything runs locally with your own credentials. Stored on your machine only: `~/.infracortex/` (HUD state, normalised mistake journal, CortexWeave activity log, queue and skills) and `~/.claude/agent-memory/infracortex-*/` (agent memories). Capsules and lessons are rejected if they contain secret-, ID- or public-IP-like strings. Optional exceptions: the hosted draw.io MCP (off by default) and TypeSafe Jev (off unless you set a key). See [SECURITY.md](SECURITY.md).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `/infracortex:…` commands missing | `claude plugin list` → enabled? Restart Claude Code after installing or updating. |
| An MCP server shows "failed" in `/mcp` | `terraform` needs Docker running; `azure` needs `az login`; `kubernetes` needs a reachable cluster (check your IP is in the API server allow-list). |
| Scripts fail on Windows / "python3 not found" | Install Git for Windows and Python from python.org; the toolkit falls back from the Store `python3` stub to `python` automatically. |
| No HUD popup | `DEVOPS_HUD` not `off`? Windows needs PowerShell 5.1+; macOS/Linux need Python with tkinter. It appears only while an InfraCortex agent runs. |
| Copilot doesn't list the agents | Re-run `python scripts/make-copilot-agents.py`, then reload VS Code; use **Agent** mode in Copilot Chat. |
| Copilot can't call `tf_scan` etc. | MCP view → start `infracortex`; check the `mcp.json` path points at `~/.infracortex/mcp-server/server/index.js`. |
| `/infracortex:weave` says the queue is empty | Only runs worth learning from are queued (failed steps, rejected reports, blocked or very long runs); clean runs and no-match searches are logged but not queued. |
| A woven skill isn't found by agents | New skills need approval: `/infracortex:weave review`. |
| `stats` shows `recording_errors` | CortexWeave couldn't write to `~/.infracortex/cortexweave` (disk full, permissions); see `errors.log` there. |

## Update and uninstall
- **Update:** `claude plugin marketplace update upinclouds && claude plugin update infracortex@upinclouds`, then restart. For Copilot, rebuild/unzip the `.mcpb` and re-run `make-copilot-agents.py`.
- **Uninstall:** `claude plugin uninstall infracortex@upinclouds`; remove the `infracortex` entry from VS Code's `mcp.json`, the `.agent.md` files from your prompts folder, and optionally `~/.infracortex` and `~/.claude/agent-memory/infracortex-*`.

---

# Reference

## AWS: "create a secure EC2" end to end

```
You: create a t3.micro EC2 in ap-south-1 for dev, private subnet subnet-0abc in vpc-0def, considering security
```
1. **provision** confirms the account (`aws sts get-caller-identity`) and fills gaps (region, env, subnet).
2. **terraform-engineer** writes `infra/<name>/` from the secure baseline in `skills/terraform-expert/references/aws-patterns.md`: aws provider `~> 6.0`, private subnet, no public IP, no SSH (SSM Session Manager), IMDSv2 required, encrypted gp3 root, scoped instance profile, AMI from the SSM parameter, monitoring.
3. Verify gate: `terraform fmt/validate` + `tf-scan.sh` must be clean, then `terraform plan`.
4. **finops-analyst** prices it (`aws-price.sh`, converted to your currency).
5. One summary (plan + monthly cost). **Nothing is created until you approve.**

Setup: `aws configure sso && aws sso login --profile dev` (no static keys); optional official AWS MCP: `/plugin install aws-core@claude-plugins-official`.

## Why it's light on tokens

1. **Scripts digest, the model reasons.** `scripts/*-scan.sh` print **one line per issue, already tagged with a rule ID**. No raw YAML/JSON enters context.
2. **Progressive disclosure.** Each `SKILL.md` is short; checklists and patterns live in `references/` and load only when needed.
3. **Subagents isolate context.** Your main chat gets back a compact JSON report.
4. **Slash skills are invisible until used**, so they cost nothing per turn.
5. **Docs on demand** via the Terraform MCP instead of guessing attributes.
6. **CortexWeave search returns descriptions only**; the full procedure is pulled only when it fits.

## Extensions: Claude Desktop and VS Code

`bash extensions/build.sh` builds both into `dist/` (needs Node ≥ 18).

| | Claude Desktop / Copilot MCP server (`.mcpb`) | VS Code extension (`.vsix`) |
|---|---|---|
| Install | Double-click (Desktop) or unzip + `mcp.json` (Copilot) | `code --install-extension dist/infracortex-<ver>.vsix` |
| What you get | 12 MCP tools (scanners, diagrams, guard check, CortexWeave) | Sidebar, right-click, command palette; findings in **Problems** |
| Uses tokens | yes (it's chat) | no (scripts only) |

MCP server security: paths are locked inside the workspace, scripts run with argument arrays (never a shell string), inputs are schema-validated (an injection such as `ns; rm -rf /` is rejected), scans are read-only.

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
agents/      terraform-engineer · k8s-troubleshooter · docker-engineer · finops-analyst · cortex (all-in-one) · overseer (monitor)
skills/      terraform-expert · k8s-expert · docker-expert · finops-expert · azure-diagrams   (knowledge + references/)
             provision · team · cortex · weave · learn · tf-review · k8s-debug · docker-audit · finops-scan (entry points)
scripts/     tf-scan · tf_inspect.py · k8s-triage · docker-audit · docker-verify · finops-scan · az-price · azdiagram.py
             guard.py · jev_judge.py · contract_gate.py · validate_report.py · build-desktop
             agent_events.py (HUD + learning hooks) · cortexweave.py (skill memory) · hud.ps1/hud.py · make-copilot-agents.py
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
Contributions follow one standard path — **issue → fork → branch → signed-off Conventional Commits → pull request → CI → code-owner review → squash/rebase merge**. Nobody pushes to `main` directly (maintainers included); GitHub rulesets enforce it, release tags are maintainer-only, and workflows from first-time contributors need approval. Most valuable: new rules, better fixes, more clouds/tools, and **lessons or CortexWeave skills your agents learned** (generic and secret-free). Read [CONTRIBUTING.md](CONTRIBUTING.md) first; report security problems privately ([SECURITY.md](SECURITY.md)); changes are in [CHANGELOG.md](CHANGELOG.md).

## License
[MIT](LICENSE)
