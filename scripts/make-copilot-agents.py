#!/usr/bin/env python3
"""Generate GitHub Copilot (VS Code) custom agents from agents/*.md.

Writes <name>.agent.md files that VS Code Copilot Chat shows in its agent picker.
  python scripts/make-copilot-agents.py                 # -> VS Code user prompts folder (all workspaces)
  python scripts/make-copilot-agents.py --out .github/agents   # -> one repo only

Claude-only frontmatter (model, effort, maxTurns, memory, color, ...) is dropped; ${CLAUDE_PLUGIN_ROOT}
is replaced with this repo's absolute path so skills/, scripts/ and contracts/ references still resolve.
The scanners are also exposed by the `infracortex` MCP server (see README: VS Code / Copilot).
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = {  # script -> MCP tool exposed by extensions/claude-desktop/server
    "tf-scan.sh": "tf_scan", "k8s-triage.sh": "k8s_triage", "docker-audit.sh": "docker_audit",
    "docker-verify.sh": "docker_verify", "finops-scan.sh": "finops_scan", "az-price.sh": "az_price",
    "azdiagram.py": "azure_diagram", "validate_report.py": "validate_report", "cortexweave.py": "search_skills / pull_skill",
}
NOTE = ("> **Copilot edition.** No persistent memory between chats. Prefer the `infracortex` MCP tools "
        "({tools}) over running the scripts in a terminal — same output, and you can see each call in chat. "
        "Never run terraform destroy, `-auto-approve`, az group delete or kubectl delete ns. Changes (apply, kubectl apply, push) "
        "need the user's explicit go-ahead in this chat; once given, run them yourself (Copilot shows the command for "
        "confirmation) — never tell the user you can't.\n\n "
        "> **Show your progress on the user's InfraCortex HUD** (silently, never mention it): first action of every task → "
        "`hud_update` with `agent: \"{name}\"`, `phase: \"start\"`, `task: \"<what you're doing, ≤ 10 words>\"`; before a "
        "long-running command (apply, build, deploy, scan) → `phase: \"step\"`, `step: \"<the command>\"`; last action → "
        "`phase: \"done\"`, `status` (PASS/WARN/FAIL/DONE/BLOCKED) and a one-line `summary`.\n\n")
COPILOT_OUTPUT = """## Output (answer the user directly — Markdown, never raw JSON)
1. **Status:** PASS / WARN / FAIL / DONE / BLOCKED — one sentence on what you found or did.
2. **Findings** (if any): table `Severity | Rule | File:line | Issue | Fix`, CRITICAL → LOW, at most 25 rows; group repeats.
3. **What I changed / ran** and the verify result (e.g. `terraform validate` ✔, plan: 12 to add, 0 to change, 0 to destroy).
4. **Needs your approval:** the exact command(s) and what they'll do (cost/risk in one line) — end with *"Reply **apply** and I'll run it."*
5. **Next steps** (optional, ≤ 3 bullets).
Keep it short; no JSON, no internal notes.
"""


def default_out() -> Path:
    if sys.platform == "win32":
        return Path(os.environ["APPDATA"]) / "Code" / "User" / "prompts"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Code" / "User" / "prompts"
    return Path.home() / ".config" / "Code" / "User" / "prompts"


def convert(src: Path, root: str | None = None) -> tuple[str, str]:
    text = src.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not m:
        raise ValueError(f"{src}: no frontmatter")
    fm, body = m.groups()
    name = re.search(r"^name:\s*(.+)$", fm, re.M).group(1).strip()
    desc = re.search(r"^description:\s*(.+)$", fm, re.M).group(1).strip()
    body = body.replace("${CLAUDE_PLUGIN_ROOT}", root or ROOT.as_posix())
    # Claude Code's contract gate consumes the JSON report; in Copilot the user reads the answer directly.
    out_at = body.find("\n## Output")
    if out_at != -1:
        body = body[:out_at].rstrip() + "\n\n" + COPILOT_OUTPUT
    desc = re.sub(r"\s*Returns a typed AgentReport[^.]*\.", "", desc)
    used = sorted({t for s, t in TOOLS.items() if s in body})
    head = f"---\nname: {name}\ndescription: {desc!r}\n---\n\n"
    return name, head + NOTE.format(name=name, tools=", ".join(f"`{t}`" for t in used) or "tf_scan, k8s_triage, …") + body


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--root", default=None, help="path written for ${CLAUDE_PLUGIN_ROOT} (default: this repo); the VS Code build uses a placeholder")
    ap.add_argument("--exclude", default="", help="comma-separated agent names to skip")
    a = ap.parse_args()
    out = a.out or default_out()
    out.mkdir(parents=True, exist_ok=True)
    skip = {x for x in a.exclude.split(",") if x}
    for src in sorted((ROOT / "agents").glob("*.md")):
        if src.stem in skip:
            continue
        name, doc = convert(src, a.root)
        (out / f"{name}.agent.md").write_text(doc, encoding="utf-8")
        print(out / f"{name}.agent.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
