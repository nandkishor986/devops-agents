#!/usr/bin/env python3
"""Validate an AgentReport v1 against the contract — stdlib only, no jsonschema dep.

Usage:
  validate_report.py report.json          # file
  echo '{...}' | validate_report.py -     # stdin
  validate_report.py --extract transcript.md   # pull the last ```json block and validate

Exit 0 = valid, 1 = invalid (errors on stderr), 2 = usage/parse error.
Mirrors shared/contracts/report.schema.json; keep the two in sync.
"""
from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class Agent(str, Enum):
    TERRAFORM = "terraform"
    K8S = "k8s"
    DOCKER = "docker"
    FINOPS = "finops"
    DEVOPS = "devops"  # combined agent (devops-expert): any of the four domains


class Task(str, Enum):
    REVIEW = "review"
    IMPLEMENT = "implement"
    TROUBLESHOOT = "troubleshoot"
    SETUP = "setup"
    EXPLAIN = "explain"


class Status(str, Enum):
    PASS = "PASS"
    WARN = "WARN"
    FAIL = "FAIL"
    DONE = "DONE"
    BLOCKED = "BLOCKED"


class Severity(str, Enum):
    CRITICAL = "CRITICAL"
    HIGH = "HIGH"
    MEDIUM = "MEDIUM"
    LOW = "LOW"
    INFO = "INFO"


RULE_ID = re.compile(r"^(TF|K8S|DKR|FIN)-(SEC|REL|COST|MNT|COR|PERF|OPS)-[0-9]{3}$")
DOMAIN_FOR_AGENT = {Agent.TERRAFORM: ("TF",), Agent.K8S: ("K8S",), Agent.DOCKER: ("DKR",), Agent.FINOPS: ("FIN",),
                    Agent.DEVOPS: ("TF", "K8S", "DKR", "FIN")}

TOP_REQUIRED = {"v", "agent", "task", "status", "summary", "findings"}
TOP_ALLOWED = TOP_REQUIRED | {"est_monthly_saving_usd", "verify", "root_cause", "files_changed", "commands_run", "needs_approval", "next"}
FINDING_REQUIRED = {"id", "sev", "file", "issue", "fix"}
FINDING_ALLOWED = FINDING_REQUIRED | {"line", "monthly_saving_usd"}


@dataclass
class Result:
    errors: list[str] = field(default_factory=list)

    def err(self, msg: str) -> None:
        self.errors.append(msg)

    @property
    def ok(self) -> bool:
        return not self.errors


def _enum(r: Result, path: str, val: Any, enum: type[Enum]) -> Enum | None:
    try:
        return enum(val)
    except ValueError:
        r.err(f"{path}: {val!r} not in {[e.value for e in enum]}")
        return None


def _str(r: Result, path: str, val: Any, max_len: int | None = None) -> None:
    if not isinstance(val, str):
        r.err(f"{path}: expected string, got {type(val).__name__}")
    elif max_len and len(val) > max_len:
        r.err(f"{path}: length {len(val)} > {max_len}")


def _str_list(r: Result, path: str, val: Any, max_items: int | None = None, max_len: int | None = None) -> None:
    if not isinstance(val, list):
        r.err(f"{path}: expected array")
        return
    if max_items and len(val) > max_items:
        r.err(f"{path}: {len(val)} items > {max_items}")
    for i, s in enumerate(val):
        _str(r, f"{path}[{i}]", s, max_len)


def validate(doc: Any) -> Result:
    r = Result()
    if not isinstance(doc, dict):
        r.err("root: expected object")
        return r

    missing = TOP_REQUIRED - doc.keys()
    extra = doc.keys() - TOP_ALLOWED
    if missing:
        r.err(f"root: missing {sorted(missing)}")
    if extra:
        r.err(f"root: unknown fields {sorted(extra)}")

    if doc.get("v") != 1:
        r.err("v: must be 1")
    agent = _enum(r, "agent", doc.get("agent"), Agent)
    _enum(r, "task", doc.get("task"), Task)
    status = _enum(r, "status", doc.get("status"), Status)
    _str(r, "summary", doc.get("summary", ""), 400)

    findings = doc.get("findings", [])
    if not isinstance(findings, list):
        r.err("findings: expected array")
        findings = []
    if len(findings) > 40:
        r.err(f"findings: {len(findings)} > 40 (group duplicates)")

    worst = None
    order = list(Severity)
    for i, f in enumerate(findings):
        p = f"findings[{i}]"
        if not isinstance(f, dict):
            r.err(f"{p}: expected object")
            continue
        if FINDING_REQUIRED - f.keys():
            r.err(f"{p}: missing {sorted(FINDING_REQUIRED - f.keys())}")
        if f.keys() - FINDING_ALLOWED:
            r.err(f"{p}: unknown fields {sorted(f.keys() - FINDING_ALLOWED)}")
        fid = f.get("id", "")
        if not isinstance(fid, str) or not RULE_ID.match(fid):
            r.err(f"{p}.id: {fid!r} does not match DOMAIN-CAT-NNN")
        elif agent and not fid.startswith(tuple(d + "-" for d in DOMAIN_FOR_AGENT[agent])):
            r.err(f"{p}.id: {fid} wrong domain for agent {agent.value}")
        sev = _enum(r, f"{p}.sev", f.get("sev"), Severity)
        if sev and (worst is None or order.index(sev) < order.index(worst)):
            worst = sev
        _str(r, f"{p}.file", f.get("file", ""))
        _str(r, f"{p}.issue", f.get("issue", ""), 200)
        _str(r, f"{p}.fix", f.get("fix", ""), 300)
        if "line" in f and (not isinstance(f["line"], int) or f["line"] < 0):
            r.err(f"{p}.line: expected non-negative integer")

    # Invariants (the "type system" part LLM output can't enforce on its own)
    if status is Status.PASS and worst in (Severity.CRITICAL, Severity.HIGH):
        r.err(f"status: PASS is inconsistent with a {worst.value} finding (use FAIL/WARN)")
    if status is Status.FAIL and worst not in (Severity.CRITICAL, Severity.HIGH):
        r.err("status: FAIL requires at least one CRITICAL/HIGH finding")

    # verify: typed record {cmd: str, passed: bool, iterations?: int}
    ver = doc.get("verify")
    if ver is not None:
        if not isinstance(ver, dict) or set(ver) - {"cmd", "passed", "iterations"} or not {"cmd", "passed"} <= set(ver):
            r.err("verify: expected {cmd: str, passed: bool, iterations?: int}")
        else:
            _str(r, "verify.cmd", ver["cmd"], 300)
            if not isinstance(ver["passed"], bool):
                r.err("verify.passed: expected boolean")
            if "iterations" in ver and (not isinstance(ver["iterations"], int) or not 1 <= ver["iterations"] <= 5):
                r.err("verify.iterations: expected integer 1..5")
    changed = isinstance(doc.get("files_changed"), list) and len(doc["files_changed"]) > 0
    if status is Status.DONE and changed and not (isinstance(ver, dict) and ver.get("passed") is True):
        r.err("status: DONE with files_changed requires verify.passed == true (run the verify step, or report BLOCKED)")

    for key, mi, ml in (("files_changed", None, None), ("commands_run", 20, None),
                        ("needs_approval", None, None), ("next", 5, 160)):
        if key in doc:
            _str_list(r, key, doc[key], mi, ml)
    if "root_cause" in doc:
        _str(r, "root_cause", doc["root_cause"], 300)
    return r


def _extract_last_json_block(text: str) -> str:
    blocks = re.findall(r"```json\s*(\{.*?\})\s*```", text, re.S)
    if not blocks:
        raise ValueError("no ```json block found")
    return blocks[-1]


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    extract = argv[0] == "--extract"
    src = argv[1] if extract else argv[0]
    try:
        raw = sys.stdin.read() if src == "-" else open(src, encoding="utf-8").read()
        if extract:
            raw = _extract_last_json_block(raw)
        doc = json.loads(raw)
    except (OSError, ValueError) as e:
        print(f"parse error: {e}", file=sys.stderr)
        return 2
    res = validate(doc)
    if res.ok:
        print("OK")
        return 0
    for e in res.errors:
        print(f"ERR {e}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
