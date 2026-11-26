#!/usr/bin/env python3
"""tf_inspect.py — AST-level Terraform checks via python-hcl2 (pip install python-hcl2). One line per finding, rule-ID tagged.

Exit codes: 0 ran (findings or not) · 3 python-hcl2 not installed (caller falls back to grep heuristics).
Usage: tf_inspect.py <dir> [--max 40]
"""
from __future__ import annotations

import sys
from pathlib import Path

try:
    import hcl2
except ImportError:
    print("SKIP python-hcl2 not installed (pip install python-hcl2) — using grep heuristics")
    sys.exit(3)

STATEFUL = {"aws_db_instance", "aws_s3_bucket", "aws_dynamodb_table", "aws_efs_file_system", "azurerm_key_vault", "azurerm_storage_account", "azurerm_mssql_server", "azurerm_mssql_database",
            "azurerm_cosmosdb_account", "azurerm_postgresql_flexible_server", "azurerm_mysql_flexible_server",
            "azurerm_kubernetes_cluster", "azurerm_redis_cache", "azurerm_log_analytics_workspace"}
SECRETY = ("password", "secret", "token", "key", "connection_string", "client_secret")
PUBLIC_ATTRS = ("public_network_access_enabled",)
WEAK_TLS = {"TLS1_0", "TLS1_1", "1.0", "1.1"}
OVERPRIV = {"Owner", "Contributor", "User Access Administrator"}


def uq(v):
    """python-hcl2 v8 keeps HCL quoting; normalise to plain python values."""
    if isinstance(v, str) and len(v) >= 2 and v[0] == v[-1] == '"':
        return v[1:-1]
    return v


def blocks(doc: dict, kind: str):
    for entry in doc.get(kind, []) or []:
        for name, body in entry.items():
            yield uq(name), body


def main(argv: list[str]) -> int:
    root = Path(argv[0] if argv else ".")
    cap = int(argv[argv.index("--max") + 1]) if "--max" in argv else 40
    out: list[str] = []
    stateful_seen: list[str] = []
    for f in sorted(root.rglob("*.tf")):
        if ".terraform" in f.parts:
            continue
        rel = f.relative_to(root).as_posix()
        try:
            doc = hcl2.load(f.open(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001 — report parse failure as a finding, keep going
            out.append(f"TF-COR-001 {rel}: HCL parse error: {str(e).splitlines()[0][:120]}")
            continue
        for t in doc.get("terraform", []) or []:
            for rp in t.get("required_providers", []) or []:
                for prov, spec in rp.items():
                    if prov.startswith("__"):
                        continue
                    if isinstance(spec, dict) and "version" not in spec:
                        out.append(f"TF-REL-001 {rel}: provider {prov} has no version constraint")
        for name, body in blocks(doc, "variable"):
            if "type" not in body:
                out.append(f"TF-COR-004 {rel}: variable {name} has no type")
            if "description" not in body:
                out.append(f"TF-MNT-002 {rel}: variable {name} has no description")
            if any(s in name.lower() for s in SECRETY):
                if body.get("sensitive") is not True:
                    out.append(f"TF-SEC-002 {rel}: variable {name} looks secret but is not sensitive = true")
                if "default" in body and uq(body["default"]) not in (None, ""):
                    out.append(f"TF-SEC-001 {rel}: variable {name} has a default value (secret literal)")
        for name, body in blocks(doc, "output"):
            if any(s in name.lower() for s in SECRETY) and body.get("sensitive") is not True:
                out.append(f"TF-SEC-002 {rel}: output {name} looks secret but is not sensitive = true")
        for name, body in blocks(doc, "module"):
            src = str(uq(body.get("source", "")))
            if src.startswith(("git::", "github.com")) and "ref=" not in src:
                out.append(f"TF-REL-001 {rel}: module {name} git source without ?ref=")
            elif not src.startswith((".", "git::", "github.com", "http")) and "version" not in body:
                out.append(f"TF-REL-001 {rel}: registry module {name} without version")
        for rtype, insts in blocks(doc, "resource"):
            for rname, body in (insts or {}).items():
                rname = uq(rname)
                addr = f"{rtype}.{rname}"
                for a in PUBLIC_ATTRS:
                    if body.get(a) is True:
                        out.append(f"TF-SEC-003 {rel}: {addr} {a} = true")
                if str(uq(body.get("min_tls_version", ""))) in WEAK_TLS:
                    out.append(f"TF-SEC-005 {rel}: {addr} min_tls_version {uq(body['min_tls_version'])}")
                if rtype == "azurerm_role_assignment" and str(uq(body.get("role_definition_name", ""))) in OVERPRIV:
                    out.append(f"TF-SEC-006 {rel}: {addr} assigns {uq(body['role_definition_name'])}")
                if rtype in STATEFUL:
                    lc = (body.get("lifecycle") or [{}])[0]
                    if lc.get("prevent_destroy") is not True:
                        stateful_seen.append(f"{rel}: {addr}")
                out.extend(aws_checks(rel, rtype, addr, body))
                if "count" in body and "for_each" not in body and str(body["count"]).count("length(") > 0:
                    out.append(f"TF-REL-003 {rel}: {addr} uses count = length(...) — prefer for_each over a map")
    for s in stateful_seen[:10]:
        out.append(f"TF-REL-002 {s} has no lifecycle.prevent_destroy (ok for non-prod — confirm)")
    for line in out[:cap]:
        print(line)
    if len(out) > cap:
        print(f"... {len(out) - cap} more")
    if not out:
        print("clean (AST checks)")
    return 0


ADMIN_PORTS = {22, 3389, 5985, 5986, 3306, 5432, 1433, 6379, 27017}
OPEN = {"0.0.0.0/0", "::/0"}


def _first(v):
    """hcl2 renders nested blocks as [ {..} ]; return the first block dict or {}."""
    if isinstance(v, list) and v and isinstance(v[0], dict):
        return v[0]
    return v if isinstance(v, dict) else {}


def _port_open(frm, to, cidrs) -> bool:
    try:
        lo, hi = int(uq(frm)), int(uq(to))
    except (TypeError, ValueError):
        return False
    hits = {uq(c) for c in (cidrs or [])} & OPEN
    return bool(hits) and (lo == 0 and hi in (0, 65535) or any(lo <= p <= hi for p in ADMIN_PORTS))


def aws_checks(rel: str, rtype: str, addr: str, body: dict) -> list[str]:
    """AWS security baseline (EC2 / SG / EBS / launch templates)."""
    out: list[str] = []
    if rtype in ("aws_instance", "aws_launch_template"):
        md = _first(body.get("metadata_options"))
        if str(uq(md.get("http_tokens", ""))) != "required":
            out.append(f"TF-SEC-009 {rel}: {addr} allows IMDSv1 — set metadata_options {{ http_tokens = \"required\" }}")
        ami = str(uq(body.get("ami") or body.get("image_id") or ""))
        if ami.startswith("ami-"):
            out.append(f"TF-MNT-006 {rel}: {addr} hard-coded AMI {ami} — resolve via aws_ssm_parameter / data source")
    if rtype == "aws_instance":
        if body.get("associate_public_ip_address") is True:
            out.append(f"TF-SEC-010 {rel}: {addr} associate_public_ip_address = true")
        rbd = _first(body.get("root_block_device"))
        if rbd.get("encrypted") is not True:
            out.append(f"TF-SEC-005 {rel}: {addr} root volume not encrypted (root_block_device {{ encrypted = true }})")
        if "iam_instance_profile" not in body:
            out.append(f"TF-SEC-011 {rel}: {addr} has no iam_instance_profile (needed for SSM Session Manager, scoped permissions)")
        if body.get("monitoring") is not True:
            out.append(f"TF-OPS-003 {rel}: {addr} detailed monitoring off")
    if rtype == "aws_ebs_volume" and body.get("encrypted") is not True:
        out.append(f"TF-SEC-005 {rel}: {addr} EBS volume not encrypted")
    if rtype == "aws_security_group":
        for ing in body.get("ingress") or []:
            if isinstance(ing, dict) and _port_open(ing.get("from_port"), ing.get("to_port"), ing.get("cidr_blocks", []) + ing.get("ipv6_cidr_blocks", [])):
                out.append(f"TF-SEC-004 {rel}: {addr} ingress {uq(ing.get('from_port'))}-{uq(ing.get('to_port'))} open to the internet")
    if rtype == "aws_vpc_security_group_ingress_rule":
        if _port_open(body.get("from_port", 0), body.get("to_port", 65535), [body.get("cidr_ipv4"), body.get("cidr_ipv6")]):
            out.append(f"TF-SEC-004 {rel}: {addr} ingress {uq(body.get('from_port'))}-{uq(body.get('to_port'))} open to the internet")
    if rtype in ("aws_iam_role_policy_attachment", "aws_iam_policy_attachment") and "AdministratorAccess" in str(body.get("policy_arn", "")):
        out.append(f"TF-SEC-011 {rel}: {addr} attaches AdministratorAccess")
    if rtype == "aws_subnet" and body.get("map_public_ip_on_launch") is True:
        out.append(f"TF-SEC-010 {rel}: {addr} map_public_ip_on_launch = true (fine for ALB/NAT subnets, not for app instances)")
    return out


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
