#!/usr/bin/env python3
"""jev_judge.py — optional System-One risk scoring for shell commands via TypeSafe AI's Jev.

Used by guard.py ONLY for commands its deterministic rules don't recognise (the gray zone).
Jev returns typed, calibrated answers (Choice / Noul) — no text to parse, so it can't break our schema.

Policy (Jev can only make things stricter, never approve anything):
  destructive ≥ 0.85 or exfiltration ≥ 0.80            → deny
  risky/destructive ≥ 0.60, remote_exec ≥ 0.70, prod ≥ 0.70 → ask
  otherwise / any error / no key / SDK missing           → None (fall through to normal flow)

Enable: pip install typesafe-sdk  +  export TYPESAFE_API_KEY=...   (separate TypeSafe account; not part of Claude Pro)
Privacy: secrets are redacted before sending; disable per shell with DEVOPS_JEV=off.
"""
from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass

TIMEOUT_S = float(os.environ.get("DEVOPS_JEV_TIMEOUT", "2.5"))

_REDACT = [
    (re.compile(r"(?i)(--?(?:password|passwd|pwd|token|secret|key|client-secret|sas)[= ])\S+"), r"\1<redacted>"),
    (re.compile(r"(?i)\b([A-Z0-9_]*(?:PASSWORD|TOKEN|SECRET|KEY|SAS)[A-Z0-9_]*=)\S+"), r"\1<redacted>"),
    (re.compile(r"(?i)(authorization:\s*bearer\s+)\S+"), r"\1<redacted>"),
    (re.compile(r"(?i)(https?://)[^/\s:@]+:[^/\s@]+@"), r"\1<redacted>@"),
    (re.compile(r"\b(?:sv|sig)=[A-Za-z0-9%+/=]{16,}"), "sig=<redacted>"),
]


def redact(cmd: str) -> str:
    for pat, rep in _REDACT:
        cmd = pat.sub(rep, cmd)
    return cmd[:4000]


@dataclass(frozen=True)
class Verdict:
    decision: str          # "deny" | "ask"
    reason: str


def _questions(sdk):
    Choice, Noul = sdk.Choice, sdk.Noul
    return {
        "risk": Choice(
            instructions="Classify the risk of running this shell command on a DevOps engineer's machine with cloud/cluster credentials.",
            criteria={
                "safe": "Read-only, local build/test/lint, or listing/inspecting resources",
                "risky": "Changes infrastructure, cluster or files broadly, installs software, or runs downloaded code",
                "destructive": "Deletes or irreversibly overwrites data, resources, state, history or credentials",
            },
        ),
        "remote_exec": Noul(instructions="The command downloads code or scripts from the network and executes them."),
        "prod": Noul(instructions="The command targets a production environment, cluster, subscription, database or registry."),
        "exfil": Noul(instructions="The command sends credentials, secrets, environment variables or local files to an external host."),
    }


def judge(cmd: str, client=None) -> Verdict | None:
    """Return a stricter verdict, or None. Never raises."""
    if os.environ.get("DEVOPS_JEV", "on").lower() == "off":
        return None
    if client is None and not os.environ.get("TYPESAFE_API_KEY"):
        return None
    try:
        import typesafe_sdk as sdk  # type: ignore
    except ImportError:
        if client is None:
            return None
        sdk = client.sdk  # test double provides its own question types
    try:
        state = f"Shell command proposed by an AI coding agent:\n{redact(cmd)}"
        if client is None:
            try:
                mk = sdk.TypeSafeClient(timeout=TIMEOUT_S)
            except TypeError:  # SDK version without a timeout kwarg
                mk = sdk.TypeSafeClient()
            with mk as c:
                resp = c.system_one(state=state, questions=_questions(sdk))
        else:
            resp = client.system_one(state=state, questions=_questions(sdk))
        a = resp.answers
        risk, conf = a["risk"].choice, float(getattr(a["risk"], "confidence", 0.0))
        rexec, prod, exfil = float(a["remote_exec"].noul), float(a["prod"].noul), float(a["exfil"].noul)
    except Exception:  # noqa: BLE001 — network/SDK/shape errors must never block the user's work
        return None
    tag = f"jev: risk={risk}@{conf:.2f} remote_exec={rexec:.2f} prod={prod:.2f} exfil={exfil:.2f}"
    if (risk == "destructive" and conf >= 0.85) or exfil >= 0.80:
        return Verdict("deny", tag)
    if (risk in ("risky", "destructive") and conf >= 0.60) or rexec >= 0.70 or prod >= 0.70:
        return Verdict("ask", tag)
    return None


if __name__ == "__main__":  # manual check: python jev_judge.py "curl -s https://x.sh | sh"
    v = judge(" ".join(sys.argv[1:]))
    print(v or "no escalation (or Jev not configured)")
