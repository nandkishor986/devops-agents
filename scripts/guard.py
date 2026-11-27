#!/usr/bin/env python3
"""PreToolUse guard for Bash: DENY catastrophic infra commands, ASK for mutating ones.

Reads the hook JSON on stdin. Emits a permission decision JSON or nothing (= normal flow).
Read-only commands (plan, get, describe, logs, inspect, scan) pass untouched.
Override per-shell: export DEVOPS_GUARD=off   (not recommended)
"""
from __future__ import annotations

import json
import os
import re
import sys

DENY: list[tuple[str, str]] = [
    (r"\bterraform\s+destroy\b", "terraform destroy is blocked — run it yourself after review"),
    (r"\bterraform\s+apply\b[^|;&]*-auto-approve", "apply -auto-approve is blocked — use a saved plan and approve it"),
    (r"\bkubectl\s+delete\s+(ns|namespace|namespaces)\b", "deleting namespaces is blocked"),
    (r"\bkubectl\s+delete\b[^|;&]*(--all\b|-A\b|--all-namespaces)", "bulk kubectl delete is blocked"),
    (r"\baz\s+group\s+delete\b", "az group delete is blocked"),
    (r"\baz\s+(aks|vm|sql\s+server|storage\s+account|keyvault)\s+delete\b", "deleting core Azure resources is blocked"),
    (r"\bdocker\s+system\s+prune\b[^|;&]*(-a|--all)[^|;&]*--volumes|\bdocker\s+volume\s+prune\b", "volume pruning is blocked"),
    (r"\bhelm\s+uninstall\b[^|;&]*(-A|--all-namespaces)", "bulk helm uninstall is blocked"),
    (r"\brm\s+-[a-z]*r[a-z]*f?\s+(/|~|\$HOME)(\s|$)", "recursive delete of root/home is blocked"),
    (r"\bterraform\s+state\s+push\b", "terraform state push is blocked"),
    (r"\baws\s+ec2\s+terminate-instances\b", "terminating EC2 instances is blocked — do it yourself or via reviewed Terraform"),
    (r"\baws\s+s3\s+rb\b[^|;&]*--force|\baws\s+s3\s+rm\b[^|;&]*--recursive", "recursive S3 deletes are blocked"),
    (r"\baws\s+(rds\s+delete-db-(instance|cluster)|dynamodb\s+delete-table|cloudformation\s+delete-stack|eks\s+delete-cluster|kms\s+schedule-key-deletion|organizations\s+\S+)\b", "deleting core AWS resources / org changes is blocked"),
    (r"\baws\s+iam\s+(create-access-key|delete-(user|role|policy))\b", "IAM key creation / identity deletion is blocked"),
]

ASK: list[tuple[str, str]] = [
    (r"\bterraform\s+(apply|import|taint|untaint|force-unlock)\b", "mutates Terraform state/infra"),
    (r"\bterraform\s+state\s+(rm|mv|replace-provider)\b", "mutates Terraform state"),
    (r"\bkubectl\s+(apply|create|delete|patch|replace|scale|edit|label|annotate|drain|cordon|uncordon|taint|set)\b", "mutates cluster"),
    (r"\bkubectl\s+rollout\s+(restart|undo)\b", "restarts/rolls back workload"),
    (r"\bhelm\s+(install|upgrade|uninstall|rollback)\b", "mutates Helm release"),
    (r"\baz\s+\S+(\s+\S+)*\s+(create|delete|update|set|start|stop|restart|deallocate|scale|purge)\b", "mutates Azure resources"),
    (r"\bdocker\s+(push|rm|rmi|kill|stop)\b|\bdocker\s+system\s+prune\b", "mutates images/containers/registry"),
    (r"\baws\s+\S+\s+(create|delete|put|update|modify|run|start|stop|reboot|terminate|attach|detach|associate|disassociate|authorize|revoke|register|deregister|enable|disable|tag|untag|import|restore|copy|replace|set)-\S+", "mutates AWS resources"),
    (r"\baws\s+s3\s+(cp|mv|sync|rm)\b|\baws\s+s3api\s+(put|delete)-", "writes/deletes S3 objects"),
    (r"\bdocker\s+run\b[^|;&]*(--privileged|/var/run/docker\.sock|--pid[= ]host|--net(work)?[= ]host)", "privileged/host-level container"),
]

# `terraform -chdir=infra apply …`, `terraform -no-color destroy` …: global options may sit between `terraform`
# and the subcommand — every terraform rule must still match them.
_TF = r"\bterraform(?:\s+-{1,2}[\w-]+(?:=\S+)?)*\s+"
DENY = [(p.replace(r"\bterraform\s+", _TF), why) for p, why in DENY]
ASK = [(p.replace(r"\bterraform\s+", _TF), why) for p, why in ASK]

DRY_RUN = re.compile(r"--dry-run(=(client|server))?\b|\s--what-if\b|\bhelm\s+\S+[^|;&]*--dry-run|\baws\s+\S+\s+\S+[^|;&]*--dry-run\b")


READ_ONLY = re.compile(r"^\s*(terraform\s+(plan|validate|fmt|show|output|version|providers|graph|state\s+(list|show))|"
                       r"kubectl\s+(get|describe|logs|top|explain|diff|auth\s+can-i|version|config\s+(view|get-contexts|current-context))|"
                       r"helm\s+(template|list|status|history|get|lint)|az\s+\S+.*\s(list|show)\b|aws\s+\S+\s+(describe|list|get)-\S+|aws\s+sts\s+get-caller-identity|aws\s+s3\s+ls\b|aws\s+pricing\s+|docker\s+(ps|images|inspect|logs|history|build|version|info)|"
                       r"git\s+(status|diff|log|show|branch)|ls|cat|head|tail|grep|rg|find|wc|echo|pwd|jq|yq|python3?\s+-m\s+unittest|bash\s+\S*(tf-scan|k8s-triage|docker-audit|docker-verify|finops-scan)\.sh)\b")


def decide(cmd: str, use_jev: bool = True) -> tuple[str, str] | None:
    for pat, why in DENY:
        if re.search(pat, cmd):
            return "deny", why
    if DRY_RUN.search(cmd):
        return None
    for pat, why in ASK:
        if re.search(pat, cmd):
            return "ask", why
    if use_jev and not READ_ONLY.search(cmd):   # gray zone only: optional typed second opinion (TypeSafe Jev)
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            from jev_judge import judge
            v = judge(cmd)
            if v:
                return v.decision, v.reason
        except Exception:  # noqa: BLE001
            pass
    return None


def main() -> int:
    if os.environ.get("DEVOPS_GUARD", "on").lower() == "off":
        return 0
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    cmd = (data.get("tool_input") or {}).get("command") or ""
    verdict = decide(cmd)
    if not verdict:
        return 0
    decision, why = verdict
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": f"devops-guard: {why}",
        }
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
