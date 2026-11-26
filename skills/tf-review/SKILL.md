---
name: tf-review
description: Review a Terraform directory with the terraform-engineer agent and return typed findings.
disable-model-invocation: true
argument-hint: "[dir] [extra instructions]"
---
Delegate to the `terraform-engineer` subagent: task=review, target=`$ARGUMENTS` (default `.`). Do not read files yourself. When it returns its AgentReport JSON, show the user: status, then findings as a table (sev | id | file:line | issue | fix) sorted CRITICAL→INFO, then `needs_approval` and `next`. Nothing else.
