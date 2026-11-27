---
name: docker-expert
description: Run the Docker Expert agent — Study an app and write a secure Dockerfile, build and run containers, or troubleshoot container failures.
disable-model-invocation: true
argument-hint: "<task> [path]"
---
Delegate to the `docker-expert` subagent with the user's request: `$ARGUMENTS` (default: review `.`). Do not read files yourself.
When its AgentReport JSON returns, show the user — in Markdown, never the raw JSON:
1. **Status** and the one-line summary.
2. **Findings** table (`Severity | Rule | File:line | Issue | Fix`), CRITICAL → LOW.
3. **Changed / ran** — files changed, commands run, verify result.
4. **Needs your approval** — the exact commands from `needs_approval`, then: *"Reply **apply** and the Docker Expert will run it."*
5. `next` items (run `handoff:` items with `/infracortex:team` only if the user agrees).
If the user then says "apply" (or equivalent), delegate to the same `docker-expert` subagent with: "The user approved: <the exact command(s)>. Run them now per *Approved changes*, then verify."
