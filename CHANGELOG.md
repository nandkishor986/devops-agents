# Changelog

All notable changes are listed here. Versions follow `.claude-plugin/plugin.json`.

## [Unreleased]

## [3.1.0]
### Changed
- **Agents own approved changes.** When the user explicitly says "apply" for a reviewed saved plan, terraform-engineer / cortex run `terraform apply -input=false <plan>` themselves (k8s-troubleshooter: `kubectl apply` of the changed files; docker-engineer: the approved push/rm), then verify. Hard limits unchanged: no `-auto-approve`, no destroy, no re-plan-and-apply; approval is per action; the client still shows the command for one confirmation click. finops-analyst stays read-only.
- **Copilot agents answer in Markdown** (status, findings table, what changed, "Reply **apply** and I'll run it") instead of the raw JSON report meant for Claude Code's contract gate.
### Fixed
- Guard: Terraform global options before the subcommand (`terraform -chdir=infra destroy`, `… apply tfplan -auto-approve`) slipped past the deny/ask rules; they now match.

## [3.0.0] — one-click VS Code extension
### Added
- The VS Code extension sets everything up itself: Copilot custom agents (`chatAgents`: terraform-engineer, k8s-troubleshooter, docker-engineer, finops-analyst, cortex), expert skills (`chatSkills`), and the InfraCortex MCP server (`mcpServerDefinitionProviders`) running on VS Code's own Node — no `mcp.json`, no Node install, no repo commands.
- *Get started* walkthrough; prerequisite check (status bar) and **Install missing tools** (winget / Homebrew / apt in a visible terminal, after confirmation).
- **Enable in Claude Code**: one click adds the marketplace and installs (or updates) the plugin via the `claude` CLI or the Claude Code extension's bundled binary.
- One-time offer to remove the old manually installed Copilot agents / `mcp.json` entry; Marketplace icon and listing.
### Changed
- MCP server bundled into one file with esbuild (`.vsix`: 63 files, ~0.6 MB instead of ~3,700 files).
- Server honours `INFRACORTEX_ROOT`; `make-copilot-agents.py` gains `--root` and `--exclude`.

## [2.1.0]
### Added
- **CortexWeave** — shared procedural memory: hooks log every agent run (monitor log) and queue the runs worth learning from (failed steps, rejected reports, BLOCKED, very long runs); validated, versioned skill capsules (`skills/<slug>/vN.md`); `search` (descriptions only) and `pull` (full procedure) for every agent; MCP tools `search_skills`, `pull_skill`, `agent_activity` for Copilot / Claude Desktop.
- **overseer** agent — monitors all agents' activity and weaves queued runs into CortexWeave skills (`/infracortex:weave`); shown in the HUD.
- Every working agent searches CortexWeave at the start of a task and pulls a skill only when it fits.
- README rewritten around usage in Claude Code and GitHub Copilot (prerequisites, quick start, configuration, troubleshooting, update/uninstall).
- CortexWeave hardening (review of PR #7): run records redacted before storage; capsule validation detects secrets structurally (quoted JSON keys, CLI flags), provider tokens, GUIDs, AWS IDs/ARNs, public IPv4/IPv6 and dangerous steps; new skills need human approval (`/infracortex:weave review`); store lock + collision-safe writes + `repair` for interrupted saves and lost queue inserts; pending runs never dropped; bounded transcript parsing; no-match searches aren't failures; task read from the transcript; true failure totals; missing versions are errors (also over MCP); 90-day activity retention; severity mix in stats; recording failures logged visibly; `escalate_when` required.
- Standard contribution procedure (issue → fork → branch → signed-off Conventional Commits → PR → CI → code-owner review → merge), enforced by rulesets; release tags maintainer-only; outside-contributor workflows need approval.
### Security
- MCP server: `zod` 3 → 4.6.7 (fixes GHSA high: memory exhaustion validating oversized collections). Tool schemas, input validation and injection rejection re-tested.

## [2.0.0] — renamed to InfraCortex
### Changed (breaking)
- Project, plugin, repo and MCP server renamed from `devops-agents` to **`infracortex`**: install with `/plugin install infracortex@upinclouds`; commands are `/infracortex:team`, `/infracortex:tf-review`, …
- The all-in-one `devops-agent` is now **`cortex`** (`/infracortex:cortex`); its reports use `"agent": "cortex"`.
- Local state moved from `~/.devops-agents` to `~/.infracortex` (`INFRACORTEX_HOME` overrides); agent memory lives in `~/.claude/agent-memory/infracortex-<agent>/`.
- Old GitHub URLs redirect to the new repository.

## [1.9.1]
### Fixed
- Contract gate and HUD read the report from a `SubagentHandback` tool call (VS Code panel / Desktop background agents), so valid reports are no longer rejected and cards no longer show *Stalled*.
- A HUD card always finishes when its agent stops (and reopens if the agent keeps working).

## [1.9.0]
### Added
- `cortex`: one agent combining Terraform, Kubernetes, Docker and FinOps (`/infracortex:cortex`; also a Copilot agent). Reports may mix `TF-`, `K8S-`, `DKR-`, `FIN-` findings (`"agent": "devops"`).
- Redesigned on-screen HUD (custom-drawn, DPI-aware): status pills, progress ring, source (`VS Code · project`), task, last steps, errors recorded for learning, *Stalled* detection.
- The MCP server reports its tool calls to the HUD, so Copilot / Claude Desktop activity is visible.

## [1.8.x]
### Added
- On-screen agent HUD (Windows WinForms, macOS/Linux tkinter).
- Self-learning: hooks record failed commands, guard blocks and rejected reports; the agent is told about new/repeated mistakes on its next run and writes LESSON lines to its memory; `/infracortex:learn --promote` moves proven lessons into skills.
- `/infracortex:team`: runs the matching agents in parallel and routes `handoff:` items between them.
### Fixed
- HUD process survives Claude Code's hook job object on Windows.

## [1.7.x]
### Added
- GitHub Copilot custom agents (`scripts/make-copilot-agents.py`) and VS Code MCP setup.
- `kubernetes-mcp-server` pinned to 0.1.3 with a read-only TOML config (the `--read-only` flag was removed upstream).
### Fixed
- Windows: scripts no longer pick the Microsoft Store `python3` stub; the guard also covers PowerShell commands; draw.io labels no longer overlap.

## [1.7.0]
- Initial toolkit: Terraform (Azure-first, AWS), Kubernetes, Docker and FinOps agents and skills, official MCP servers, typed AgentReport contract, destructive-command guard, Azure diagrams, VS Code and Claude Desktop extensions.
