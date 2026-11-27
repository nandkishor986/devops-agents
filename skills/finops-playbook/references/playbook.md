# FinOps playbook (load only when proposing optimisations)

## Decision rules
| Signal | Action | Typical saving |
|---|---|---|
| Unattached managed disk > 7 days | snapshot (if unsure) → delete | 100% of disk cost |
| Unassociated Standard public IP | delete | ~$3.6/mo each |
| VM p95 CPU < 5% for 14d, not a DR/standby | deallocate or delete | 100% compute |
| VM p95 CPU < 40% and mem < 50% | downsize one size in family (D4s→D2s) | ~50% |
| Dev/test VMs running nights/weekends | auto-shutdown 19:00–09:00 + weekends (`az vm auto-shutdown`) or Start/Stop VMs v2 | ~65% |
| AKS non-prod | `az aks stop` schedule, or user pools min=0 + autoscaler; spot pool for tolerant workloads | 40–90% |
| AKS requests ≫ usage | rightsize requests → fewer nodes via autoscaler | 20–50% node cost |
| Steady 24×7 compute ≥ 1 yr | Savings Plan (flexible) or Reserved Instance (fixed size/region) | 1yr ~30–40%, 3yr ~55–65% |
| App Service Plan with 0 apps | delete | 100% |
| Premium SSD on dev | Standard SSD | ~50% disk |
| Blob hot data untouched 30/90d | lifecycle → cool/cold/archive | 50–90% storage |
| Log Analytics high ingestion | drop debug logs at source, DCR transformations, Basic/Auxiliary logs for verbose tables, commitment tier if > 100 GB/day | 30–70% |
| Snapshots > retention | delete via policy | 100% |
| SQL DTU/vCore underused | serverless (auto-pause) for dev; elastic pool for many small DBs | 30–70% |

## Savings maths (show your formula)
- Monthly = hourly × 730.
- Schedule saving = monthly × (off_hours / 168) per week. 14h weekdays + 48h weekend off = 118/168 = 70%.
- Commitment break-even months = upfront ÷ (PAYG_monthly − committed_monthly). Recommend only if workload stable for > 1.5 × break-even.
- Rightsizing confidence: HIGH if ≥ 14 days of metrics incl. a peak period, else MEDIUM.

## Metrics lookup (targeted)
```bash
az monitor metrics list --resource <vmId> --metric "Percentage CPU" --interval PT1H --aggregation Maximum Average \
  --start-time $(date -u -d '-14 days' +%FT%TZ) -o json | jq '[.value[0].timeseries[0].data[].maximum // empty] | sort | .[(length*0.95|floor)]'
```

## Governance (FIN-OPS)
- Required tags via Azure Policy (deny or modify/inherit from RG): env, owner, cost-center, app.
- Budgets per subscription + per RG for teams; alerts at 50/80/100% actual and 100% forecast to an action group.
- Monthly review: Advisor cost recs, orphan sweep (this script in a scheduled pipeline), commitments utilisation.
- Showback: Cost Management export to storage → Power BI / FOCUS-format export for cross-cloud.

## Terraform cost gate (ADO)
Pipeline step after `plan`: `infracost breakdown --path tfplan.json --format json --out-file base.json` on main, `infracost diff --compare-to base.json` on PR, `infracost comment azure-repos ...` for PR comment; fail if Δ% > policy without `cost-approved` label.
