---
name: weave
description: CortexWeave — the agents' shared skill memory. Show what all agents did (monitor), have the overseer turn recent runs into reusable skills, or search/read a skill.
disable-model-invocation: true
argument-hint: "[harvest | review | approve <slug> | reject <slug> | stats | search <query> | pull <slug> | list]"
---
CLI: `python ${CLAUDE_PLUGIN_ROOT}/scripts/cortexweave.py` (macOS/Linux: `python3`).

By the first word of `$ARGUMENTS` (default `harvest`):
- `harvest` → delegate to the `overseer` subagent: "Monitor the last 7 days, then harvest the CortexWeave queue." Show its summary as-is, then remind the user that new skills need review.
- `review` → run `cortexweave.py review`; show each pending skill in full and ask the user, skill by skill, whether to approve. Approve or reject ONLY what the user explicitly says (`cortexweave.py approve <slug>` / `reject <slug> --reason "…"`). Never approve on your own.
- `approve <slug>` / `reject <slug> <reason>` → run the matching command (the user typed it, so that is their decision).
- `stats` → run `cortexweave.py stats --days 7`; show a table per agent: runs · PASS/WARN/FAIL/BLOCKED · findings by severity · failed steps · contract rejections · avg tool calls; then queue size, skills (active / awaiting review) and any recording errors.
- `search <query>` → run `cortexweave.py search "<query>"`; show the hits (slug, version, description).
- `pull <slug>` → run `cortexweave.py pull <slug>`; show the procedure.
- `list` → run `cortexweave.py list`.
Do not read the store files yourself; use the CLI.
