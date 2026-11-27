# Changelog

All notable changes are listed here. Versions follow `.claude-plugin/plugin.json`.

## [Unreleased]
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
