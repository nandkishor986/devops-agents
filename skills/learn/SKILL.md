---
name: learn
description: Review what the DevOps agents have learned — recorded mistakes, repeated ones and the lessons in each agent's memory — and promote proven lessons into the plugin's skills so every future run (and every machine) gets them.
disable-model-invocation: true
argument-hint: "[agent | all] [--promote]"
---

# Learning review (you run this; agents learn automatically between runs)

Data (read-only unless promoting):
- Mistake journal per agent: `~/.infracortex/learning/<agent>.json` (`count` = times seen, `delivered` = times the agent was told).
- Lessons per agent: `~/.claude/agent-memory/infracortex-<agent>/MEMORY.md`, section `## Lessons`.
Agents: terraform-engineer, k8s-troubleshooter, docker-engineer, finops-analyst (default: all).

## 1. Report (always)
Per agent: mistakes total · REPEATED (count ≥ 2 after delivery) · lessons count. Table: `agent | mistake (error, short) | count | lesson that covers it (or "none")`. A repeated mistake with no matching lesson, or whose lesson is vague, is the top problem — say which.

## 2. Promote (only with `--promote` or after the user says yes)
A lesson qualifies when it is generic, secret-free, and either covers a mistake seen ≥ 2 times or the user confirms it. For each qualifying lesson:
- Append it to `${CLAUDE_PLUGIN_ROOT}/skills/<domain>-expert/references/learned.md` (create with a `# Learned lessons` heading; one bullet each; dedupe). Domain: terraform-engineer→terraform, k8s-troubleshooter→k8s, docker-engineer→docker, finops-analyst→finops.
- If `${CLAUDE_PLUGIN_ROOT}` is the installed cache copy, write to the source repo instead (the marketplace directory, e.g. the user's infracortex clone) and tell the user to commit + `claude plugin update infracortex@upinclouds`.
- Remove the promoted lesson from MEMORY.md (it now ships with the skill), keep MEMORY.md ≤ 60 lines.
Show the diff of learned.md and stop. Never put IDs, IPs, hostnames, keys or customer names in learned.md.
