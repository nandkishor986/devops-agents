#!/usr/bin/env python3
"""SubagentStop hook — runtime type check for agent output (the "deserializer that throws").

Reads the hook JSON on stdin, extracts the AgentReport from `last_assistant_message`, validates it with
validate_report.py (enums, rule-ID domains, length caps, invariants). Invalid → {"decision": "block"} so the
agent must re-emit a corrected report. Loop-safe: if the agent was already blocked once (stop_hook_active),
it lets the stop through and leaves a note instead of blocking forever.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import validate_report as vr  # noqa: E402

AGENTS = re.compile(r"^(devops-agents:)?(terraform-engineer|k8s-troubleshooter|docker-engineer|finops-analyst|devops-agent)$")


def extract(msg: str) -> object:
    msg = msg.strip()
    for candidate in (msg, *(m for m in re.findall(r"```(?:json)?\s*(\{.*?\})\s*```", msg, re.S)[::-1])):
        try:
            return json.loads(candidate)
        except ValueError:
            pass
    if "{" in msg and "}" in msg:
        try:
            return json.loads(msg[msg.index("{"): msg.rindex("}") + 1])
        except ValueError:
            pass
    raise ValueError("no parseable JSON object in final message")


HANDBACK_TOOLS = ("SubagentHandback",)


def handback_report(transcript_path: str | None) -> str | None:
    """Background agents (VS Code panel, Desktop) deliver their report with a SubagentHandback tool call instead of
    their final message. Return the last handback message from the agent transcript, if any."""
    if not transcript_path:
        return None
    try:
        lines = Path(transcript_path).read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    for line in reversed(lines[-200:]):
        try:
            m = (json.loads(line).get("message") or {})
        except ValueError:
            continue
        if m.get("role") != "assistant" or not isinstance(m.get("content"), list):
            continue
        for b in reversed(m["content"]):
            if b.get("type") == "tool_use" and b.get("name") in HANDBACK_TOOLS:
                msg = (b.get("input") or {}).get("message")
                if isinstance(msg, str) and msg.strip():
                    return msg
    return None


def final_report(data: dict) -> object:
    """The agent's AgentReport: from its final message, else from its SubagentHandback call."""
    try:
        return extract(data.get("last_assistant_message") or "")
    except ValueError:
        hb = handback_report(data.get("agent_transcript_path"))
        if hb is None:
            raise
        return extract(hb)


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    if not AGENTS.match(str(data.get("agent_type", ""))):
        return 0
    try:
        errors = vr.validate(final_report(data)).errors
    except ValueError as e:
        errors = [str(e)]
    if not errors:
        return 0
    errs = "; ".join(errors[:8])
    try:  # self-learning: a rejected report is a mistake the agent is told about next run
        import agent_events
        agent_events.record(AGENTS.match(str(data.get("agent_type", ""))).group(2), "contract", "report", "", errs)
    except Exception:  # noqa: BLE001
        pass
    if data.get("stop_hook_active"):
        print(json.dumps({"systemMessage": f"devops-agents: report still invalid after one retry ({errs})"}))
        return 0
    print(json.dumps({
        "decision": "block",
        "reason": ("Your final message must be ONLY a valid AgentReport v1 JSON object (contracts/report.schema.json). "
                   f"Validation errors: {errs}. Re-emit the corrected JSON object only — no prose, no code fences."),
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
