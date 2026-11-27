---
name: finops-playbook
description: Azure FinOps — find waste (orphaned/idle/oversized resources), read cost by RG/service, AKS rightsizing, Terraform cost impact with Infracost, reservations/savings plans, tagging and budgets. Use for cost reviews, "why is the bill high", cost-aware IaC review, or saving plans.
---

> **Learned lessons:** read `references/learned.md` first (short) — rules promoted from past mistakes; they override older guidance below.

# FinOps expert (Azure-first)

## Token rules
1. **Script first**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/finops-scan.sh [--sub <id>] [--days 30]` (waste + Advisor + top RGs), `--tf <dir>` (Infracost breakdown/diff), `--aks -n <ns>` (requests vs usage). Never page raw `az consumption usage list` output.
2. **Price lookups without Infracost or login**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/az-price.sh preset <private-endpoint|private-dns-zone|storage "Hot LRS"|vm D4s_v5|aks-uptime> --region <r> --qty N` or `az-price.sh query --region <r> --service "<svc>" --product "<substr>" --meter "<substr>"` (public Retail Prices API). State usage assumptions (GB, ops, hours) next to every estimate. Always pass `--currency ${user_config.currency}`; convert USD-only sources with `az-price.sh fx ${user_config.currency}`.
2b. **AWS prices**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/aws-price.sh ec2 <type> --region <r> --currency ${user_config.currency}` / `aws-price.sh ebs gp3 --gb N` (aws CLI login, read-only Price List API; USD converted with the fx rate and labelled).
3. Azure MCP for targeted follow-ups only (one resource's metrics/SKU), never bulk listing.
4. Load `references/playbook.md` only when proposing optimisations (decision rules + savings maths).
5. Findings use FIN-* IDs from `${CLAUDE_PLUGIN_ROOT}/contracts/RULES.md`; add `monthly_saving_usd` per finding when estimable and `est_monthly_saving_usd` total. Say "estimate" — retail list prices, not negotiated/EA rates. Report in ${user_config.currency}.

## Workflow
| Task | Steps |
|---|---|
| waste review | scan → group by rule → estimate savings (playbook formulas) → rank by $ × confidence → quick wins (delete orphans, schedules) vs commitments (RI/SP) |
| bill spike | top RGs last 30d vs previous 30d (`--days 60` and compare) → drill one RG by `ServiceName`/`Meter` via Cost Management query → correlate with deploy dates / autoscale / log ingestion |
| new resources (provision) | Infracost `--tf <dir>` if key set, else az-price per resource → table resource / basis / $ per month + cheaper alternatives |
| IaC cost gate | `--tf <dir>` → diff vs main → flag FIN-COST-011 if Δ > threshold (default +10% or +$100/mo) → cheaper SKU/tier alternatives |
| AKS | `--aks` → over-requested workloads → new requests = p95 usage × 1.2 (CPU), p99 × 1.2 (mem) → node pool consolidation / spot pool / autoscaler bounds |

## Auth & permissions (Azure CLI)
Uses your `az login` session — `az account set -s <name>` first. Needs **Reader** (Resource Graph, Advisor) + **Cost Management Reader** (actual cost, budgets) on the subscription. `az-price.sh` needs no login at all.

## Safety
Read-only. Deleting/deallocating/resizing resources goes to `needs_approval` with the exact `az` command and a rollback note. Never buy reservations — recommend with break-even.
