---
name: devops
description: Run the all-in-one devops-agent (Terraform + Kubernetes + Docker + FinOps in one context) on a task and return typed findings.
disable-model-invocation: true
argument-hint: "<task> [dir]"
---
Delegate to the `devops-agent` subagent with the user's task: `$ARGUMENTS` (default: review `.`). Do not read files yourself. When its AgentReport JSON returns, show: status, findings table (sev | id | file:line | issue | fix) sorted CRITICAL→INFO, files changed + verify result, `needs_approval`, then `next` (run any `handoff:` items with `/devops-agents:team` only if the user agrees). Nothing else.
