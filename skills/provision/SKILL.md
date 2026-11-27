---
name: provision
description: Create or change Azure or AWS infrastructure end to end (e.g. "storage account in eastus2 with private endpoint", "secure EC2 in ap-south-1") — Terraform engineer writes + verifies the code with a security baseline, FinOps analyst prices it, one combined summary with approvals. Use for any provisioning request.
argument-hint: "<what to create> [region] [env] [dir]"
---

# Provision workflow (multi-agent, use-case driven)

Subagents can't call each other — YOU orchestrate. Keep your own context small: pass each agent a precise brief, keep only their JSON reports.

## 0. Clarify only what changes the code (one question max, else assume and state it)
cloud (Azure or AWS — from the request: EC2/VPC/S3/IAM = AWS) · region · env (dev/prod → size, redundancy, prevent_destroy/termination protection) · network (existing VNet/subnet + private DNS zone IDs, or AWS VPC + private subnet IDs, or create) · target dir (default `./infra/<short-name>`). Confirm the identity so the user knows where the plan/cost lands: `az account show -o tsv --query name` (Azure) or `aws sts get-caller-identity --query Account --output text` (AWS).

## 1. Pick agents by use case
| Request contains | Agents (in order) |
|---|---|
| create/modify Azure resources | `terraform-expert` → `finops-expert` |
| + containers / images | add `docker-expert` before finops if a Dockerfile is involved |
| + AKS workloads / manifests | add `kubernetes-expert` (manifests) after terraform |
| "how much will X cost" only | `finops-expert` alone (no code) |
| "review/fix existing IaC" | `terraform-expert` alone; finops only if SKUs/scale change |

## 2. terraform-expert brief
"task=implement. Create <resources> in <region> for <env> under <dir>. Azure: follow azure-patterns (private endpoint + private DNS zone group, public access off, TLS1_2, tags, prevent_destroy for prod). AWS: follow aws-patterns secure EC2 baseline (private subnet, no public IP, no SSH ingress, SSM instance profile, IMDSv2, encrypted gp3, AMI via SSM parameter, monitoring). Verify gate required. Do NOT apply." → keep its report (files_changed, verify, needs_approval).

## 3. finops-expert brief
"task=review (cost estimate) for <dir> in <region>: monthly cost of each new resource. Use Infracost if configured (`finops-scan.sh --tf <dir>`), else per resource: Azure → `az-price.sh` presets/queries; AWS → `aws-price.sh ec2 <type> --region <r>` and `aws-price.sh ebs gp3 --gb N` (+ NAT gateway / endpoints if created), with stated usage assumptions. Flag cheaper alternatives (e.g. LRS vs ZRS for dev, one PE per needed subresource only)."

Report all money in ${user_config.currency} (`az-price.sh --currency ${user_config.currency}`; Infracost USD × `az-price.sh fx ${user_config.currency}`).

## 4. Present ONE summary
files created · verify result · plan counts (add/change/destroy) · monthly estimate table (resource | basis | ${user_config.currency}/mo) + assumptions · findings above LOW · exact commands awaiting approval (`terraform apply tfplan`). Nothing is applied without the user saying so.
