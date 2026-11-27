---
name: terraform-expert
description: Run the Terraform Expert agent — Review, write, provision (plan → your approval → apply), import or diagram Terraform for Azure/AWS.
disable-model-invocation: true
argument-hint: "<task> [dir]"
---
Delegate to the `terraform-expert` subagent with the user's request: `$ARGUMENTS` (default: review `.`). Do not read files yourself.
When its AgentReport JSON returns, show the user — in Markdown, never the raw JSON:
1. **Status** and the one-line summary.
2. **Findings** table (`Severity | Rule | File:line | Issue | Fix`), CRITICAL → LOW.
3. **Changed / ran** — files changed, commands run, verify result.
4. **Needs your approval** — the exact commands from `needs_approval`, then: *"Reply **apply** and the Terraform Expert will run it."*
5. `next` items (run `handoff:` items with `/infracortex:team` only if the user agrees).
If the user then says "apply" (or equivalent), delegate to the same `terraform-expert` subagent with: "The user approved: <the exact command(s)>. Run them now per *Approved changes*, then verify."
