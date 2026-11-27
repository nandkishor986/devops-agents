#!/usr/bin/env python3
"""CortexWeave — procedural memory for the InfraCortex agents (stdlib only, local files).

Two paths that never block each other:
  WRITE  hooks record every agent run (activity log) → a selector queues the runs worth learning from
         (failed steps, rejected reports, BLOCKED/FAIL, very long runs) → the `overseer` agent judges each
         one and writes a *capsule* (a reusable procedure) → validated, versioned, indexed here.
  READ   any agent (Claude Code, Copilot via MCP) calls `search` (descriptions only — cheap) and, if one
         fits, `pull` (the full procedure). Nothing is injected; the agent chooses.

Store: ~/.infracortex/cortexweave/  (INFRACORTEX_HOME overrides ~/.infracortex)
  activity/YYYY-MM-DD.jsonl   one line per finished agent run (the monitor log)
  queue.json                  runs selected for learning (pending / woven / skipped)
  skills/<slug>/meta.json     versions, status, uses     skills/<slug>/vN.json + vN.md  the capsule
  index.json                  slug → description, tags, agents, version (what search reads)

CLI:  search "<query>" [--agent A] [--limit 5]  ·  pull <slug> [--version N]  ·  stats [--days 7]
      queue [--all]  ·  show <run_id>  ·  validate <capsule.json>  ·  save <capsule.json> [--runs id,id]
      skip <run_id> --reason "…"  ·  list
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HOME = Path(os.environ.get("INFRACORTEX_HOME") or Path.home() / ".infracortex")
ROOT = HOME / "cortexweave"
AGENTS = ("terraform-engineer", "k8s-troubleshooter", "docker-engineer", "finops-analyst", "cortex")
SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SECRETISH = re.compile(
    r"(?i)(password|passwd|secret|token|api[_-]?key|client[_-]?secret|sas)\s*[=:]\s*\S{6,}"
    r"|-----BEGIN [A-Z ]*PRIVATE KEY-----|\bAKIA[0-9A-Z]{16}\b|\bgh[pousr]_[A-Za-z0-9]{30,}\b"
    r"|\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"
    r"|\b(?!(?:10|127|0|169\.254|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.)(?:\d{1,3}\.){3}\d{1,3}\b")
MAX_QUEUE = 200


# ------------------------------------------------------------------ small JSON helpers
def _read(p: Path, default):
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def _write(p: Path, data) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, p)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


# ------------------------------------------------------------------ write path 1: record + select
def trace_from_transcript(path: str | None, limit: int = 8) -> dict:
    """Summarise an agent transcript: tool calls, and the calls that failed with their error (shortened)."""
    out = {"tool_calls": 0, "failed": [], "tools": {}}
    if not path:
        return out
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except OSError:
        return out
    calls: dict[str, str] = {}
    for line in lines:
        try:
            m = json.loads(line).get("message") or {}
        except ValueError:
            continue
        if not isinstance(m.get("content"), list):
            continue
        for b in m["content"]:
            if b.get("type") == "tool_use":
                out["tool_calls"] += 1
                out["tools"][b.get("name", "?")] = out["tools"].get(b.get("name", "?"), 0) + 1
                inp = b.get("input") or {}
                what = inp.get("command") or inp.get("file_path") or inp.get("pattern") or ""
                calls[b.get("id", "")] = f"{b.get('name')}: {' '.join(str(what).split())[:140]}"
            elif b.get("type") == "tool_result" and b.get("is_error"):
                c = b.get("content")
                text = c if isinstance(c, str) else " ".join(x.get("text", "") for x in c or [] if isinstance(x, dict))
                err = next((ln.strip() for ln in text.splitlines() if ln.strip() and not ln.startswith("Exit code")), text[:80])
                if len(out["failed"]) < limit:
                    out["failed"].append({"call": calls.get(b.get("tool_use_id", ""), "?"), "error": err[:200]})
    return out


def select_reason(run: dict) -> str | None:
    """Is this run worth learning from? A clean, short run teaches nothing."""
    if run.get("contract_errors"):
        return "report rejected by the contract gate"
    if run.get("status") == "BLOCKED":
        return "agent was blocked"
    if run.get("failed_steps", 0) >= 1:
        return f"{run['failed_steps']} failed step(s)"
    if run.get("tool_calls", 0) >= 45:
        return f"long run ({run['tool_calls']} tool calls) — look for a shorter procedure"
    return None


def record_run(run: dict, transcript: str | None = None) -> dict:
    """Append a finished run to the activity log and queue it if it's worth learning from."""
    if os.environ.get("INFRACORTEX_WEAVE", "on").lower() == "off":
        return run
    t = trace_from_transcript(transcript)
    run = {**run, "ts": _now(), "tool_calls": t["tool_calls"] or run.get("tool_calls", 0),
           "failed_steps": len(t["failed"]) or run.get("failed_steps", 0), "tools": t["tools"]}
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    (ROOT / "activity").mkdir(parents=True, exist_ok=True)
    with open(ROOT / "activity" / f"{day}.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps(run, ensure_ascii=False) + "\n")
    reason = select_reason(run)
    if reason and run.get("agent") in AGENTS:
        q = _read(ROOT / "queue.json", {"items": []})
        if not any(i["run_id"] == run.get("run_id") for i in q["items"]):
            q["items"].append({"run_id": run.get("run_id"), "agent": run.get("agent"), "project": run.get("project"),
                               "task": run.get("task", ""), "status": run.get("status"), "summary": run.get("summary", ""),
                               "reason": reason, "failed": t["failed"], "contract_errors": run.get("contract_errors", ""),
                               "transcript": transcript, "queued": _now(), "state": "pending"})
            q["items"] = q["items"][-MAX_QUEUE:]
            _write(ROOT / "queue.json", q)
    return run


# ------------------------------------------------------------------ write path 2: capsules
def validate(c: dict) -> list[str]:
    """The capsule contract: anything too thin to be a procedure, or carrying secrets, is rejected."""
    e: list[str] = []
    req = {"slug": str, "description": str, "agents": list, "procedure": list}
    for k, t in req.items():
        if not isinstance(c.get(k), t):
            e.append(f"{k}: required {t.__name__}")
    if e:
        return e
    if not SLUG.match(c["slug"]) or len(c["slug"]) > 60:
        e.append("slug: lowercase-kebab, ≤ 60 chars")
    d = c["description"].strip()
    if not 30 <= len(d) <= 280:
        e.append("description: 30–280 chars")
    if not d.lower().startswith("use when"):
        e.append('description: must start with "Use when …" (it is what search shows)')
    if not c["agents"] or any(a not in AGENTS for a in c["agents"]):
        e.append(f"agents: non-empty subset of {list(AGENTS)}")
    steps = [s for s in c["procedure"] if isinstance(s, str) and s.strip()]
    if len(steps) < 2:
        e.append("procedure: at least 2 concrete steps")
    for fm in c.get("failure_modes", []) or []:
        if not (isinstance(fm, dict) and all(isinstance(fm.get(k), str) and fm[k].strip() for k in ("symptom", "cause", "fix"))):
            e.append("failure_modes[]: each needs symptom, cause, fix")
            break
    for k in ("preconditions", "heuristics", "anti_patterns", "tags"):
        if k in c and not (isinstance(c[k], list) and all(isinstance(x, str) for x in c[k])):
            e.append(f"{k}: list of strings")
    if not (c.get("validator") or "").strip():
        e.append("validator: say how to check the result is right")
    blob = json.dumps(c, ensure_ascii=False)
    if SECRETISH.search(blob):
        e.append("contains something that looks like a secret, ID or public IP — make it generic")
    if len(blob) > 12000:
        e.append("capsule too long (> 12k chars) — a skill is a procedure, not a transcript")
    return e


def render(c: dict) -> str:
    out = [f"# {c['slug']} (v{c['version']})", "", c["description"], "",
           f"Agents: {', '.join(c['agents'])}" + (f" · Tags: {', '.join(c.get('tags', []))}" if c.get("tags") else ""), ""]
    def section(title: str, items, numbered: bool = False) -> None:
        if items:
            out.extend([f"## {title}", *[(f"{i}. " if numbered else "- ") + s for i, s in enumerate(items, 1)], ""])
    section("Preconditions", c.get("preconditions"))
    section("Procedure", c["procedure"], numbered=True)
    section("Heuristics", c.get("heuristics"))
    if c.get("failure_modes"):
        out.append("## Failure modes")
        out += [f"- **{f['symptom']}** — cause: {f['cause']} → fix: {f['fix']}" for f in c["failure_modes"]]
        out.append("")
    section("Anti-patterns", c.get("anti_patterns"))
    out += ["## Check the result", c["validator"], ""]
    if c.get("escalate_when"):
        out += ["## Stop and ask the user when", c["escalate_when"], ""]
    p = c.get("provenance", {})
    out.append(f"_Woven by {c.get('owner', 'overseer')} from {len(p.get('runs', []))} run(s); updated {c.get('updated_at', '')}._")
    return "\n".join(out) + "\n"


def save(c: dict, runs: list[str] | None = None) -> dict:
    errs = validate(c)
    if errs:
        raise ValueError("; ".join(errs))
    d = ROOT / "skills" / c["slug"]
    meta = _read(d / "meta.json", {"slug": c["slug"], "versions": [], "uses": 0, "created_at": _now()})
    v = (meta["versions"][-1] + 1) if meta["versions"] else 1
    prev = _read(d / f"v{v - 1}.json", {}) if v > 1 else {}
    prov = {"runs": sorted(set((prev.get("provenance", {}).get("runs", [])) + (runs or []) +
                               c.get("provenance", {}).get("runs", [])))}
    c = {**c, "version": v, "status": c.get("status", "active"), "owner": c.get("owner", "overseer"),
         "provenance": prov, "updated_at": _now()}
    _write(d / f"v{v}.json", c)
    (d / f"v{v}.md").write_text(render(c), encoding="utf-8")
    meta.update(versions=meta["versions"] + [v], status=c["status"], updated_at=c["updated_at"])
    _write(d / "meta.json", meta)
    idx = _read(ROOT / "index.json", {})
    idx[c["slug"]] = {"description": c["description"], "agents": c["agents"], "tags": c.get("tags", []),
                      "version": v, "status": c["status"]}
    _write(ROOT / "index.json", idx)
    if runs:
        mark(runs, "woven", f"{c['slug']} v{v}")
    return c


def mark(run_ids: list[str], state: str, note: str = "") -> int:
    q = _read(ROOT / "queue.json", {"items": []})
    n = 0
    for i in q["items"]:
        if i["run_id"] in run_ids:
            i["state"], i["note"], i["closed"] = state, note, _now()
            n += 1
    _write(ROOT / "queue.json", q)
    return n


# ------------------------------------------------------------------ read path
def _tokens(s: str) -> list[str]:
    return [t for t in re.findall(r"[a-z0-9]+", s.lower()) if len(t) > 1]


def search(query: str, agent: str | None = None, limit: int = 5) -> list[dict]:
    """Keyword ranking (BM25-style) over slug + description + tags. Returns descriptions only."""
    idx = {k: v for k, v in _read(ROOT / "index.json", {}).items() if v.get("status") != "deprecated"}
    if agent:
        idx = {k: v for k, v in idx.items() if agent in v.get("agents", [])}
    docs = {k: _tokens(k.replace("-", " ") + " " + v["description"] + " " + " ".join(v.get("tags", []))) for k, v in idx.items()}
    q = _tokens(query)
    if not q or not docs:
        return []
    n, avg = len(docs), sum(len(d) for d in docs.values()) / len(docs)
    df = {t: sum(t in d for d in docs.values()) for t in set(q)}
    scored = []
    for k, d in docs.items():
        s = 0.0
        for t in q:
            tf = d.count(t)
            if tf:
                idf = math.log(1 + (n - df[t] + 0.5) / (df[t] + 0.5))
                s += idf * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * len(d) / avg))
        if s > 0:
            scored.append((s, k))
    return [{"slug": k, "score": round(s, 2), **idx[k]} for s, k in sorted(scored, reverse=True)[:limit]]


def pull(slug: str, version: int | None = None) -> str:
    d = ROOT / "skills" / slug
    meta = _read(d / "meta.json", None)
    if not meta:
        raise KeyError(f"no skill named {slug!r} — run search first")
    v = version or meta["versions"][-1]
    meta["uses"] = meta.get("uses", 0) + 1
    meta["last_used"] = _now()
    _write(d / "meta.json", meta)
    return (d / f"v{v}.md").read_text(encoding="utf-8")


def stats(days: int = 7) -> dict:
    cutoff = time.time() - days * 86400
    per: dict[str, dict] = {}
    for f in sorted((ROOT / "activity").glob("*.jsonl")) if (ROOT / "activity").exists() else []:
        for line in f.read_text(encoding="utf-8").splitlines():
            try:
                r = json.loads(line)
                if datetime.fromisoformat(r["ts"]).timestamp() < cutoff:
                    continue
            except (ValueError, KeyError):
                continue
            a = per.setdefault(r.get("agent", "?"), {"runs": 0, "by_status": {}, "failed_steps": 0, "tool_calls": 0,
                                                     "contract_rejections": 0, "projects": set()})
            a["runs"] += 1
            a["by_status"][r.get("status", "?")] = a["by_status"].get(r.get("status", "?"), 0) + 1
            a["failed_steps"] += r.get("failed_steps", 0)
            a["tool_calls"] += r.get("tool_calls", 0)
            a["contract_rejections"] += 1 if r.get("contract_errors") else 0
            a["projects"].add(r.get("project", "?"))
    for a in per.values():
        a["projects"] = sorted(a["projects"])
        a["avg_tool_calls"] = round(a["tool_calls"] / a["runs"], 1) if a["runs"] else 0
    q = _read(ROOT / "queue.json", {"items": []})["items"]
    return {"days": days, "agents": per, "queue_pending": sum(i["state"] == "pending" for i in q),
            "skills": len(_read(ROOT / "index.json", {}))}


# ------------------------------------------------------------------ CLI
def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="cortexweave", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("search"); s.add_argument("query"); s.add_argument("--agent"); s.add_argument("--limit", type=int, default=5)
    p = sub.add_parser("pull"); p.add_argument("slug"); p.add_argument("--version", type=int)
    st = sub.add_parser("stats"); st.add_argument("--days", type=int, default=7)
    qu = sub.add_parser("queue"); qu.add_argument("--all", action="store_true")
    sh = sub.add_parser("show"); sh.add_argument("run_id")
    va = sub.add_parser("validate"); va.add_argument("file")
    sv = sub.add_parser("save"); sv.add_argument("file"); sv.add_argument("--runs", default="")
    sk = sub.add_parser("skip"); sk.add_argument("run_id"); sk.add_argument("--reason", required=True)
    sub.add_parser("list")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "search":
            hits = search(a.query, a.agent, a.limit)
            print("\n".join(f"{h['slug']} (v{h['version']}, score {h['score']}): {h['description']}" for h in hits)
                  or "no matching skill — proceed with your normal workflow")
        elif a.cmd == "pull":
            print(pull(a.slug, a.version))
        elif a.cmd == "stats":
            print(json.dumps(stats(a.days), indent=1))
        elif a.cmd == "queue":
            items = _read(ROOT / "queue.json", {"items": []})["items"]
            for i in items if a.all else [i for i in items if i["state"] == "pending"]:
                print(f"{i['run_id']} | {i['agent']} | {i['project']} | {i['reason']} | {i['state']} | {i.get('task', '')[:60]}")
        elif a.cmd == "show":
            item = next((i for i in _read(ROOT / "queue.json", {"items": []})["items"] if i["run_id"] == a.run_id), None)
            if not item:
                print(f"no queued run {a.run_id}", file=sys.stderr)
                return 1
            print(json.dumps({k: v for k, v in item.items() if k != "transcript"}, indent=1, ensure_ascii=False))
        elif a.cmd == "validate":
            errs = validate(json.loads(Path(a.file).read_text(encoding="utf-8")))
            print("\n".join(errs) or "valid")
            return 1 if errs else 0
        elif a.cmd == "save":
            c = save(json.loads(Path(a.file).read_text(encoding="utf-8")), [r for r in a.runs.split(",") if r])
            print(f"saved {c['slug']} v{c['version']} → {ROOT / 'skills' / c['slug']}")
        elif a.cmd == "skip":
            print(f"skipped {mark([a.run_id], 'skipped', a.reason)} run(s)")
        elif a.cmd == "list":
            for k, v in sorted(_read(ROOT / "index.json", {}).items()):
                print(f"{k} v{v['version']} [{v['status']}] {','.join(v['agents'])}: {v['description']}")
    except (ValueError, KeyError) as e:
        print(f"ERR {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
