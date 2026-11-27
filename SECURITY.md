# Security policy

## Reporting a vulnerability
Please **do not open a public issue** for security problems. Use GitHub's private reporting instead: **Security → Report a vulnerability** on this repository. Include what you found, how to reproduce it, and the impact. You'll get an acknowledgement within a few days.

In scope, for example:
- a way to make an agent run a destructive command without the user's approval (bypassing `scripts/guard.py` or the permission prompt),
- secrets, credentials or Kubernetes Secret values leaking into reports, memory, the learning journal or the HUD state,
- path traversal or command injection in the MCP server (`extensions/claude-desktop/server`) or the VS Code extension,
- anything that sends user data to a third party without the user enabling it,
- a way to get content into an *active* CortexWeave skill without human approval, or to smuggle secrets/IDs/IPs or dangerous steps past capsule validation.

## What the toolkit stores locally
- `~/.infracortex/learning/*.json` — normalised error lines of failed agent commands (paths, quoted strings and numbers are replaced with placeholders).
- `~/.infracortex/cortexweave/` — CortexWeave: activity log of agent runs (agent, project folder name, status, step counts, shortened failed commands/errors), the harvest queue (incl. local transcript paths) and the woven skills. Run records are redacted before storage (secrets incl. CLI-flag and quoted-JSON forms, provider tokens, GUIDs, AWS account/resource IDs and ARNs, public IPv4/IPv6). Skills containing any of those, or dangerous steps (pipe-to-shell, auto-approve/destroy, disabling safety, prompt-injection, exfiltration), are rejected, and every new skill waits for human approval before agents can read it. Activity is kept 90 days. `INFRACORTEX_WEAVE=off` disables it.
- `~/.infracortex/hud/state.json` — agent names, project folder names, last tool steps (shortened), timings.
- `~/.claude/agent-memory/infracortex-*/MEMORY.md` — conventions and lessons written by the agents (instructed never to store secrets, IDs or IPs).
Nothing is uploaded by the toolkit itself. Delete those folders at any time; `DEVOPS_HUD=off` and `DEVOPS_LEARN=off` disable the HUD and learning.

## Supported versions
Only the latest release receives fixes.
