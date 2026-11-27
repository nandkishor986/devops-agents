---
name: weave
description: CortexWeave — the agents' shared skill memory. Show what all agents did (monitor), have the overseer turn recent runs into reusable skills, or search/read a skill.
disable-model-invocation: true
argument-hint: "[harvest | stats | search <query> | pull <slug> | list]"
---
CLI: `python ${CLAUDE_PLUGIN_ROOT}/scripts/cortexweave.py` (macOS/Linux: `python3`).

By the first word of `$ARGUMENTS` (default `harvest`):
- `harvest` → delegate to the `overseer` subagent: "Monitor the last 7 days, then harvest the CortexWeave queue." Show its summary as-is.
- `stats` → run `cortexweave.py stats --days 7`; show a table per agent: runs · PASS/WARN/FAIL/BLOCKED · failed steps · contract rejections · avg tool calls; then queue size and skill count.
- `search <query>` → run `cortexweave.py search "<query>"`; show the hits (slug, version, description).
- `pull <slug>` → run `cortexweave.py pull <slug>`; show the procedure.
- `list` → run `cortexweave.py list`.
Do not read the store files yourself; use the CLI.
