#!/usr/bin/env bash
# install.sh — fallback installer when you DON'T want to use the plugin marketplace.
# Copies agents/skills into ~/.claude (user scope), registers MCP servers, merges the guard hook.
# Preferred instead:  /plugin marketplace add nandkishor986/infracortex  &&  /plugin install infracortex@upinclouds
#
# Usage: [DEVOPS_CURRENCY=INR] ./install.sh [--no-mcp] [--no-hook] [--uninstall]
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CLAUDE_DIR/infracortex"
MCP=1; HOOK=1; UNINSTALL=0
for a in "$@"; do case "$a" in --no-mcp) MCP=0;; --no-hook) HOOK=0;; --uninstall) UNINSTALL=1;; esac; done
AGENTS=(terraform-engineer k8s-troubleshooter docker-engineer finops-analyst)
SKILLS=(terraform-expert k8s-expert docker-expert finops-expert azure-diagrams provision tf-review k8s-debug docker-audit finops-scan)
PY=$(for c in python3 python; do command -v "$c" >/dev/null && "$c" -c "" 2>/dev/null && { command -v "$c"; break; }; done)
[[ -n "$PY" ]] || { echo "python3 is required"; exit 1; }

if [[ $UNINSTALL -eq 1 ]]; then
  for a in "${AGENTS[@]}"; do rm -f "$CLAUDE_DIR/agents/$a.md"; done
  for s in "${SKILLS[@]}"; do rm -rf "$CLAUDE_DIR/skills/$s"; done
  rm -rf "$DEST"
  command -v claude >/dev/null && for m in terraform azure kubernetes drawio; do claude mcp remove -s user "$m" >/dev/null 2>&1 || true; done
  echo "Removed. Agent memory kept in $CLAUDE_DIR/agent-memory/ (delete manually if wanted). Hook entry in settings.json left in place — remove the infracortex guard line if desired."
  exit 0
fi

mkdir -p "$DEST" "$CLAUDE_DIR/agents" "$CLAUDE_DIR/skills"
rm -rf "$DEST"/{scripts,contracts,examples}
cp -R "$SRC/scripts" "$SRC/contracts" "$SRC/examples" "$DEST/"
chmod +x "$DEST"/scripts/*.sh "$DEST"/scripts/*.py

# substitute ${CLAUDE_PLUGIN_ROOT} (only resolved automatically in plugin mode)
subst(){ "$PY" - "$1" "$DEST" <<'EOF'
import sys,pathlib
import os
p=pathlib.Path(sys.argv[1]); t=p.read_text(encoding="utf-8").replace("${CLAUDE_PLUGIN_ROOT}", sys.argv[2].replace("\\","/"))
p.write_text(t.replace("${user_config.currency}", os.environ.get("DEVOPS_CURRENCY","INR").upper()), encoding="utf-8")
EOF
}
for a in "${AGENTS[@]}"; do cp "$SRC/agents/$a.md" "$CLAUDE_DIR/agents/$a.md"; subst "$CLAUDE_DIR/agents/$a.md"; done
for s in "${SKILLS[@]}"; do
  rm -rf "$CLAUDE_DIR/skills/$s"; cp -R "$SRC/skills/$s" "$CLAUDE_DIR/skills/$s"
  find "$CLAUDE_DIR/skills/$s" -name '*.md' | while read -r f; do subst "$f"; done
done
mkdir -p "$DEST/skills"; for s in terraform-expert k8s-expert docker-expert finops-expert; do rm -rf "$DEST/skills/$s"; ln -s "$CLAUDE_DIR/skills/$s" "$DEST/skills/$s" 2>/dev/null || cp -R "$CLAUDE_DIR/skills/$s" "$DEST/skills/$s"; done
echo "✓ agents + skills → $CLAUDE_DIR"

if [[ $MCP -eq 1 ]]; then
  if command -v claude >/dev/null; then
    add(){ claude mcp remove -s user "$1" >/dev/null 2>&1 || true; claude mcp add -s user "$@" >/dev/null && echo "✓ mcp $1" || echo "✗ mcp $1 (add manually, see README)"; }
    add terraform -- docker run -i --rm -e TFE_TOKEN -e TFE_ADDRESS hashicorp/terraform-mcp-server:1.1.0
    add azure -- npx -y @azure/mcp@latest server start
    add kubernetes -- npx -y kubernetes-mcp-server@latest --read-only
  else echo "! claude CLI not found — add MCP servers from .mcp.json manually"; fi
fi

if [[ $HOOK -eq 1 ]]; then
  "$PY" - "$CLAUDE_DIR/settings.json" "$DEST/scripts/guard.py" <<'EOF'
import json,sys,pathlib,shutil,time
p=pathlib.Path(sys.argv[1]); guard=sys.argv[2].replace("\\","/")
s=json.loads(p.read_text(encoding="utf-8")) if p.exists() and p.read_text().strip() else {}
if p.exists(): shutil.copy(p, f"{p}.bak.{int(time.time())}")
cmd=f'python3 "{guard}" 2>/dev/null || python "{guard}"'
pre=s.setdefault("hooks",{}).setdefault("PreToolUse",[])
if not any("infracortex" in h.get("command","") or "guard.py" in h.get("command","") for m in pre for h in m.get("hooks",[])):
    pre.append({"matcher":"Bash","hooks":[{"type":"command","command":cmd,"timeout":5}]})
gate=guard.replace("guard.py","contract_gate.py")
stop=s["hooks"].setdefault("SubagentStop",[])
if not any("contract_gate.py" in h.get("command","") for m in stop for h in m.get("hooks",[])):
    stop.append({"matcher":"^(infracortex:)?(terraform-engineer|k8s-troubleshooter|docker-engineer|finops-analyst)$","hooks":[{"type":"command","command":f'python3 "{gate}" 2>/dev/null || python "{gate}"',"timeout":10}]})
p.write_text(json.dumps(s,indent=2),encoding="utf-8"); print("✓ guard + contract-gate hooks merged into", p)
EOF
fi

echo
echo "Check optional CLIs:"
for t in terraform tflint trivy checkov infracost kubectl kubeconform kube-linter hadolint docker az jq dot; do
  command -v "$t" >/dev/null && printf '  ✓ %s\n' "$t" || printf '  · %s (optional)\n' "$t"
done
"$PY" -c "import diagrams" 2>/dev/null && echo "  ✓ python diagrams" || echo "  · python diagrams (pip install diagrams) for PNG/SVG diagrams"
command -v cli-anything-drawio >/dev/null && echo "  ✓ cli-anything-drawio" || echo "  · cli-anything-drawio (optional: edit/export .drawio, see README)"
echo "Restart Claude Code, then try:  /tf-review ./infra   or   'use the k8s-troubleshooter on namespace payments'"
