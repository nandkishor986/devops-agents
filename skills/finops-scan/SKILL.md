---
name: finops-scan
description: Run an Azure cost-waste / Terraform cost / AKS rightsizing review with the finops-analyst agent.
disable-model-invocation: true
argument-hint: "[--sub <id>] | [--tf <dir>] | [--aks -n <ns>]"
---
Delegate to the `finops-analyst` subagent with scope `$ARGUMENTS` (default: current az subscription waste review). Show the user from its AgentReport: est_monthly_saving_usd, findings table sorted by monthly_saving_usd (id | resource | saving/mo | fix), `needs_approval`, `next`.
