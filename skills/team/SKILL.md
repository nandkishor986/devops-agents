---
name: team
description: Run the DevOps agents as one team on a repo or folder — picks terraform-engineer, k8s-troubleshooter, docker-engineer and finops-analyst by what the folder contains, runs them in parallel, routes their `handoff:` items to each other, and merges one report. Use for "review everything", "full platform review", "check this repo end to end", or any task spanning Terraform + Kubernetes + Docker + cost.
argument-hint: "[dir] [goal, e.g. review | security | cost | fix]"
---

# DevOps team (orchestrated by you — subagents can't call each other)

Keep your own context small: never read the repo yourself; pass briefs, keep only the agents' JSON reports.

## 1. Detect stacks (one Glob each, count only) in `$ARGUMENTS` dir (default `.`)
| Found | Agent | Brief scope |
|---|---|---|
| `**/*.tf` | `terraform-engineer` | the dirs holding .tf |
| k8s YAML (`kind:` in `**/*.y*ml`), `Chart.yaml`, `kustomization.yaml` | `k8s-troubleshooter` | manifests/charts (files only unless the user asked for live cluster triage) |
| `**/Dockerfile*`, `compose*.y*ml` | `docker-engineer` | each Dockerfile |
| .tf present and goal mentions cost/FinOps/"everything" | `finops-analyst` | cost of the .tf dirs (Infracost or price lookups) |

Small cross-domain task (≤ ~15 files, e.g. "Dockerfile + manifest + ACR for one service")? Use the single `devops-agent` instead of several specialists — one context, cheaper. Use the specialists in parallel for anything bigger.

Skip agents with nothing to do. If nothing is found, say so and stop.

## 2. Wave 1 — launch the chosen agents IN PARALLEL (one message, several Agent calls)
Brief each: "task=<review|implement|troubleshoot> for <scope>. Goal: <goal>. Stay in your lane; put cross-domain items in `next` as `handoff:<agent>: …`. Do NOT apply/deploy."
Each agent shows up live in the DevOps Agents HUD on screen while it works.

## 3. Wave 2 — hand-offs (at most one extra wave)
Collect every `next` item starting `handoff:<terraform|k8s|docker|finops>:` from wave-1 reports. Group by target agent, drop duplicates and anything that agent already covered, then launch the targets in parallel with exactly those items as the brief. Never loop beyond wave 2 — remaining hand-offs go to the user as follow-ups.

## 4. One merged answer
1. Status line per agent (PASS/WARN/FAIL/DONE/BLOCKED) + overall = worst of them.
2. One findings table across agents, sorted CRITICAL→INFO, deduped (same file:line + same issue → keep one, list both rule IDs): `sev | id | agent | file:line | issue | fix`.
3. Cross-cutting issues: chains that span agents (e.g. unpinned image tag → k8s pulls `latest`; public ACR in TF → image supply chain).
4. Cost (if finops ran), files changed, `needs_approval` (exact commands), open follow-ups.
Nothing is applied without the user's explicit yes.
