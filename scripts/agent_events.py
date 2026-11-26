#!/usr/bin/env python3
"""Hook dispatcher for the four devops agents: live on-screen HUD + self-learning mistake journal.

Events (hook JSON on stdin; anything not from a devops agent exits immediately):
  SubagentStart       -> HUD card appears; inject this agent's unresolved past mistakes as additionalContext
  PreToolUse          -> HUD shows the step the agent is about to run
  PostToolUseFailure  -> journal the failure (normalised signature, counted) + HUD error count
  SubagentStop        -> HUD shows PASS/WARN/FAIL/DONE/BLOCKED (or "fixing report" if the contract gate will block)

State lives in ~/.devops-agents (override: DEVOPS_AGENTS_HOME). Switches: DEVOPS_HUD=off, DEVOPS_LEARN=off.
Never blocks the user: every error is swallowed and the hook exits 0.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOME = Path(os.environ.get("DEVOPS_AGENTS_HOME") or Path.home() / ".devops-agents")
HUD_DIR, LEARN_DIR = HOME / "hud", HOME / "learning"
AGENT_RE = re.compile(r"^(?:devops-agents:)?(terraform-engineer|k8s-troubleshooter|docker-engineer|finops-analyst|devops-agent)$")
MAX_MISTAKES, INJECT_TOP = 60, 6
# failures that are normal control flow, not mistakes (grep/test/diff exit 1)
BENIGN = re.compile(r"^\s*(grep|rg|test|\[|diff|cmp|command -v|which|ls)\b")
DENIED = re.compile(r"permission (to use|for this)|was denied|denied by|requires approval|user (rejected|declined)", re.I)


def agent_of(d: dict) -> str | None:
    m = AGENT_RE.match(str(d.get("agent_type") or ""))
    return m.group(1) if m else None


# ---------------------------------------------------------------- small locked JSON store
def _locked_update(path: Path, fn) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    lock = path.with_suffix(".lock")
    for _ in range(40):
        try:
            fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.close(fd)
            break
        except FileExistsError:
            try:
                if time.time() - lock.stat().st_mtime > 2:
                    lock.unlink(missing_ok=True)
            except OSError:
                pass
            time.sleep(0.025)
    try:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            data = {}
        fn(data)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, indent=1), encoding="utf-8")
        os.replace(tmp, path)
        return data
    finally:
        lock.unlink(missing_ok=True)


# ---------------------------------------------------------------- learning journal
def normalise(err: str) -> str:
    line = next((ln.strip() for ln in (err or "").splitlines() if ln.strip() and not ln.startswith("Exit code")), "")
    line = re.sub(r"([A-Za-z]:)?[\\/][^\s'\"]+", "<path>", line)
    line = re.sub(r"'[^']*'|\"[^\"]*\"", "<str>", line)
    line = re.sub(r"\b[0-9a-f]{7,}\b|\b\d+\b", "#", line)
    return line[:120]


def signature(agent: str, kind: str, tool: str, cmd: str, err: str) -> str:
    head = " ".join(cmd.split()[:2])
    return hashlib.sha1(f"{agent}|{kind}|{tool}|{head}|{normalise(err)}".encode()).hexdigest()[:10]


def record(agent: str, kind: str, tool: str, cmd: str, err: str) -> None:
    """Count a mistake. Same signature again = repeated mistake."""
    if os.environ.get("DEVOPS_LEARN", "on").lower() == "off":
        return
    sig, now = signature(agent, kind, tool, cmd, err), int(time.time())

    def upd(j: dict) -> None:
        ms = j.setdefault("mistakes", {})
        m = ms.setdefault(sig, {"kind": kind, "tool": tool, "cmd": cmd[:120], "error": normalise(err) or err[:120],
                                "count": 0, "first": now, "delivered": 0})
        m["count"] += 1
        m["last"] = now
        if len(ms) > MAX_MISTAKES:  # drop the oldest, already-delivered, single occurrences first
            for k in sorted(ms, key=lambda k: (ms[k]["count"] > 1, ms[k]["delivered"] == 0, ms[k]["last"]))[:len(ms) - MAX_MISTAKES]:
                ms.pop(k, None)
    _locked_update(LEARN_DIR / f"{agent}.json", upd)


def lessons_context(agent: str) -> str:
    """Top unresolved/repeated mistakes for the agent, and mark them delivered."""
    picked: list[dict] = []

    def upd(j: dict) -> None:
        ms = j.get("mistakes", {})
        # repeated after delivery first, then never delivered, newest first
        order = sorted(ms.values(), key=lambda m: (m["count"] > m.get("count_at_delivery", 0) and m["delivered"] > 0,
                                                   m["delivered"] == 0, m["last"]), reverse=True)
        for m in order:
            fresh = m["delivered"] == 0 or m["count"] > m.get("count_at_delivery", 0)
            if fresh and len(picked) < INJECT_TOP:
                picked.append(dict(m))
                m["delivered"] += 1
                m["count_at_delivery"] = m["count"]
    _locked_update(LEARN_DIR / f"{agent}.json", upd)
    if not picked:
        return ""
    rows = []
    for m in picked:
        tag = f"REPEATED x{m['count']}" if m["delivered"] > 0 or m["count"] > 1 else "new"
        what = "your final report was rejected by the contract gate" if m["kind"] == "contract" else \
               "a command you ran was blocked by the guard" if m["kind"] == "blocked" else f"{m['tool']} `{m['cmd'][:70]}` failed"
        rows.append(f"- [{tag}] {what}: {m['error'][:110]}")
    return ("## Mistakes from your previous runs (auto-recorded by devops-agents)\n" + "\n".join(rows) +
            "\nBefore starting: for each item, add or sharpen ONE line under `## Lessons` in your MEMORY.md — "
            "`- LESSON: <situation> → <do this instead>` (dedupe, keep ≤ 20). REPEATED items mean an existing lesson "
            "did not work: make it more specific. Then follow your lessons for this task.")


# ---------------------------------------------------------------- HUD state
def short_action(tool: str, inp: dict) -> str:
    inp = inp or {}
    if tool in ("Bash", "PowerShell"):
        return "$ " + " ".join(str(inp.get("command", "")).split())[:80]
    if tool in ("Read", "Edit", "Write", "NotebookEdit"):
        return f"{tool.lower()} {Path(str(inp.get('file_path', ''))).name}"
    if tool in ("Grep", "Glob"):
        return f"{tool.lower()} {str(inp.get('pattern', ''))[:60]}"
    if tool.startswith("mcp__"):
        return "mcp " + tool.split("__", 2)[-1][:60]
    return tool


def hud(update) -> None:
    if os.environ.get("DEVOPS_HUD", "on").lower() == "off":
        return

    def upd(s: dict) -> None:
        agents = s.setdefault("agents", {})
        update(agents)
        now = time.time()
        for k in [k for k, a in agents.items()
                  if (a.get("ended") and a["ended"] < now - (120 if k.startswith("pending:") else 600))
                  or (not a.get("ended") and a.get("seen", a.get("started", now)) < now - 1800)]:  # dead session
            agents.pop(k)
        s["updated"] = time.time()
    _locked_update(HUD_DIR / "state.json", upd)


def ensure_hud() -> None:
    if "off" in (os.environ.get("DEVOPS_HUD", "on").lower(), os.environ.get("DEVOPS_HUD_LAUNCH", "on").lower()):
        return
    HUD_DIR.mkdir(parents=True, exist_ok=True)
    beat, launching = HUD_DIR / "heartbeat", HUD_DIR / "launching"
    now = time.time()
    for f, age in ((beat, 4), (launching, 8)):
        try:
            if now - f.stat().st_mtime < age:
                return  # running, or another hook is starting it
        except OSError:
            pass
    launching.write_text(str(now))
    try:
        if os.name == "nt":
            args = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-STA",
                    "-WindowStyle", "Hidden", "-File", str(HERE / "hud.ps1"), "-StateDir", str(HUD_DIR)]
            base = 0x08000000 | 0x00000200  # CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP
            # Claude Code runs hooks inside a Windows job object that is torn down when the hook exits, which would
            # kill the HUD. Break away from the job; if the job forbids that, start it via WMI (outside any job).
            try:
                subprocess.Popen(args, creationflags=base | 0x01000000, stdin=subprocess.DEVNULL,  # BREAKAWAY_FROM_JOB
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=True)
            except OSError:
                cmdline = subprocess.list2cmdline(args).replace("'", "''")
                subprocess.Popen(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
                                  f"Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{{CommandLine='{cmdline}'}} | Out-Null"],
                                 creationflags=base, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, close_fds=True).wait(timeout=4)
        else:
            subprocess.Popen([sys.executable, str(HERE / "hud.py"), str(HUD_DIR)], start_new_session=True,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


# ---------------------------------------------------------------- events
SOURCES = {"claude-vscode": "VS Code", "cli": "CLI", "sdk-cli": "CLI (headless)", "claude-desktop": "Claude Desktop",
           "sdk-ts": "SDK", "sdk-py": "SDK", "copilot": "Copilot"}


def source() -> str:
    ep = os.environ.get("CLAUDE_CODE_ENTRYPOINT", "")
    return SOURCES.get(ep, ep or "Claude Code")


def _entry(a: dict, aid: str, agent: str, d: dict) -> dict:
    e = a.setdefault(aid, {"type": agent, "status": "running", "started": time.time(), "steps": 0, "errors": 0,
                           "history": [], "source": source(), "project": Path(str(d.get("cwd") or ".")).name})
    e["seen"] = time.time()
    return e


def _step(e: dict, text: str, ok: bool = True) -> None:
    e["action"] = text
    h = e.setdefault("history", [])
    h.append({"t": time.time(), "a": text[:90], "ok": ok})
    del h[:-4]


def on_start(d: dict, agent: str) -> dict | None:
    aid = d.get("agent_id") or agent

    def upd(a: dict) -> None:
        pend = a.pop(f"pending:{agent}", None) or {}
        a[aid] = {"type": agent, "status": "running", "started": time.time(), "seen": time.time(), "steps": 0,
                  "errors": 0, "history": [], "action": "starting", "task": pend.get("task", ""),
                  "source": source(), "project": Path(str(d.get("cwd") or ".")).name,
                  "session": str(d.get("session_id") or "")[:8]}
    hud(upd)
    ensure_hud()
    ctx = lessons_context(agent)
    if ctx:
        return {"hookSpecificOutput": {"hookEventName": "SubagentStart", "additionalContext": ctx}}
    return None


def on_mcp(d: dict, agent: str) -> None:
    """A tool call on the devops-agents MCP server. One card per (client process, domain); idle between calls."""
    aid = f"mcp:{d.get('session', '')}:{agent}"
    tool, phase = str(d.get("tool", "")), d.get("phase")

    def upd(a: dict) -> None:
        e = a.get(aid)
        if e is None or (phase == "start" and e.get("ended")):
            e = a[aid] = {"type": agent, "status": "running", "started": time.time(), "steps": 0, "errors": 0,
                          "history": (e or {}).get("history", []), "source": str(d.get("source") or "MCP client"),
                          "project": Path(str(d.get("cwd") or ".")).name, "task": "MCP tool calls"}
        e["seen"] = time.time()
        if phase == "start":
            e["steps"] = e.get("steps", 0) + 1
            _step(e, f"mcp {tool}")
        else:
            if not d.get("ok", True):
                e["errors"] = e.get("errors", 0) + 1
                if e.get("history"):
                    e["history"][-1]["ok"] = False
            e["status"], e["result"], e["ended"] = "done", ("DONE" if d.get("ok", True) else "WARN"), time.time()
            e["summary"], e["action"] = f"{tool} finished", "idle — waiting for the next tool call"
    hud(upd)
    if phase == "start":
        ensure_hud()


def on_delegate(d: dict) -> None:
    """Main thread is about to start one of our agents: remember the task description for its card."""
    inp = d.get("tool_input") or {}
    m = AGENT_RE.match(str(inp.get("subagent_type") or ""))
    if m:
        hud(lambda a: a.__setitem__(f"pending:{m.group(1)}", {"task": str(inp.get("description") or "")[:80],
                                                                "ended": time.time()}))


def on_pre(d: dict, agent: str) -> None:
    aid = d.get("agent_id") or agent
    tool, inp = str(d.get("tool_name", "")), d.get("tool_input") or {}
    act = "handing back report" if tool == "SubagentHandback" else short_action(tool, inp)
    result, summary = None, ""
    if tool == "SubagentHandback":  # report delivered by tool call: the card can finish now
        try:
            sys.path.insert(0, str(HERE))
            import contract_gate as cg
            import validate_report as vr
            doc = cg.extract(str(inp.get("message") or ""))
            if isinstance(doc, dict) and not vr.validate(doc).errors:
                result, summary = str(doc.get("status", "DONE")), str(doc.get("summary", ""))[:140]
        except Exception:  # noqa: BLE001
            pass

    def upd(a: dict) -> None:
        e = _entry(a, aid, agent, d)
        if e.get("ended") and not result:
            e["status"] = "running"
            e.pop("ended", None)
            e.pop("result", None)
        e["steps"] = e.get("steps", 0) + 1
        _step(e, act)
        if result:
            e["status"], e["result"], e["ended"], e["summary"], e["action"] = "done", result, time.time(), summary, "finished"
    hud(upd)


def on_fail(d: dict, agent: str) -> None:
    if d.get("is_interrupt"):
        return
    tool, inp = str(d.get("tool_name", "")), d.get("tool_input") or {}
    cmd = str(inp.get("command") or inp.get("file_path") or inp.get("pattern") or "")
    err = str(d.get("error") or "")
    if tool in ("Bash", "PowerShell") and BENIGN.match(cmd) and "Exit code 1" in err:
        return
    if DENIED.search(err):  # the user's permission choice, not the agent's mistake
        return
    kind = "blocked" if "devops-guard" in err else "tool_error"
    record(agent, kind, tool, cmd, err)
    aid = d.get("agent_id") or agent

    def upd(a: dict) -> None:
        e = _entry(a, aid, agent, d)
        e["errors"] = e.get("errors", 0) + 1
        h = e.get("history") or []
        if h:
            h[-1]["ok"] = False          # the step that just failed
        e["action"] = "failed: " + short_action(tool, inp)
    hud(upd)


def on_stop(d: dict, agent: str) -> None:
    """Always finish the card with what we know. The contract gate may ask the agent to re-emit its report, but an
    agent that already handed its report back usually ends anyway — if it does continue, its next step reopens the card."""
    aid = d.get("agent_id") or agent
    status, summary, nerr = "DONE", "", 0
    try:
        sys.path.insert(0, str(HERE))
        import contract_gate as cg
        import validate_report as vr
        doc = cg.final_report(d)   # final message, or the SubagentHandback report
        nerr = len(vr.validate(doc).errors)
        if isinstance(doc, dict):
            status, summary = str(doc.get("status", "DONE")), str(doc.get("summary", ""))[:140]
    except Exception:  # noqa: BLE001
        status, nerr = "BLOCKED", 1
        summary = "no AgentReport found in the agent's output"

    def upd(a: dict) -> None:
        e = _entry(a, aid, agent, d)
        if nerr:
            _step(e, f"report failed {nerr} contract check(s) — recorded for learning", ok=False)
        e["status"], e["result"], e["ended"], e["summary"], e["action"] = "done", status, time.time(), summary, "finished"
    hud(upd)


def main() -> int:
    try:
        d = json.load(sys.stdin)
    except ValueError:
        return 0
    ev = d.get("hook_event_name")
    agent = agent_of(d)
    if ev == "McpTool" and agent:  # from the devops-agents MCP server (Copilot / Claude Desktop)
        try:
            on_mcp(d, agent)
        except Exception:  # noqa: BLE001
            pass
        return 0
    if not agent:
        if ev == "PreToolUse" and d.get("tool_name") in ("Agent", "Task"):
            try:
                on_delegate(d)
            except Exception:  # noqa: BLE001
                pass
        return 0
    try:
        out = {"SubagentStart": on_start, "PreToolUse": on_pre, "PostToolUseFailure": on_fail,
               "SubagentStop": on_stop}.get(ev, lambda *_: None)(d, agent)
        if out:
            print(json.dumps(out))
    except Exception:  # noqa: BLE001 — the HUD/journal must never break the agent
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
