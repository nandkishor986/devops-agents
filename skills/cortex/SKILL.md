---
name: cortex
description: Run cortex, the all-in-one agent (Terraform + Kubernetes + Docker + FinOps in one context) on a task and return typed findings.
disable-model-invocation: true
argument-hint: "<task> [dir]"
---
Delegate to the `cortex` subagent with the user's task: `$ARGUMENTS` (default: review `.`). Do not read files yourself. When its AgentReport JSON returns, show: status, findings table (sev | id | file:line | issue | fix) sorted CRITICAL→INFO, files changed + verify result, `needs_approval`, then `next` (run any `handoff:` items with `/infracortex:team` only if the user agrees). Nothing else.
