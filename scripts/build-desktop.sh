#!/usr/bin/env bash
# build-desktop.sh — package the knowledge skills for Claude Desktop / claude.ai chat (Settings → Capabilities → Skills → Upload),
# plus a claude_desktop_config.json snippet for the MCP servers.
# Note: Desktop CHAT has no subagents/hooks, and skill scripts run in Claude's sandbox (not against your cluster/subscription).
# For full power use Claude Code (CLI or VS Code extension) with the plugin.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$SRC/dist"; rm -rf "$OUT"; mkdir -p "$OUT"
PY=$(for c in python3 python; do command -v "$c" >/dev/null && "$c" -c "" 2>/dev/null && { command -v "$c"; break; }; done)
for s in terraform-expert k8s-expert docker-expert finops-expert azure-diagrams; do
  tmp=$(mktemp -d); cp -R "$SRC/skills/$s" "$tmp/$s"; mkdir -p "$tmp/$s/scripts" "$tmp/$s/contracts"
  cp "$SRC"/scripts/*.sh "$SRC"/scripts/*.py "$tmp/$s/scripts/"; cp "$SRC"/contracts/* "$tmp/$s/contracts/"
  [[ "$s" == azure-diagrams ]] && cp -R "$SRC/examples" "$tmp/$s/examples"
  find "$tmp/$s" -name '*.md' -exec "$PY" -c 'import sys,pathlib
p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text(encoding="utf-8").replace("${CLAUDE_PLUGIN_ROOT}/skills/'"$s"'/","").replace("${CLAUDE_PLUGIN_ROOT}/",""),encoding="utf-8")' {} \;
  (cd "$tmp" && "$PY" -c "import shutil; shutil.make_archive('$OUT/$s','zip','.', '$s')")
  rm -rf "$tmp"; echo "✓ dist/$s.zip"
done
cat > "$OUT/claude_desktop_config.snippet.json" <<'EOF'
{
  "mcpServers": {
    "terraform": { "command": "docker", "args": ["run", "-i", "--rm", "hashicorp/terraform-mcp-server:1.1.0"] },
    "azure": { "command": "npx", "args": ["-y", "@azure/mcp@latest", "server", "start"] },
    "kubernetes": { "command": "npx", "args": ["-y", "kubernetes-mcp-server@latest", "--read-only"] }
  }
}
EOF
echo "✓ dist/claude_desktop_config.snippet.json  (merge into %APPDATA%\\Claude\\claude_desktop_config.json; add draw.io as a custom connector: https://mcp.draw.io/mcp)"
