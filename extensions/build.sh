#!/usr/bin/env bash
# Build both extensions into dist/:  dist/devops-agents-<ver>.mcpb (Claude Desktop) and dist/devops-agents-<ver>.vsix (VS Code)
# Needs: node ≥18, npm. Uses npx @anthropic-ai/mcpb and @vscode/vsce (pinned).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; DIST="$ROOT/dist"; mkdir -p "$DIST"
VER=$(cd "$ROOT" && for c in python3 python; do "$c" -c "import json;print(json.load(open('.claude-plugin/plugin.json'))['version'])" 2>/dev/null && break; done)
[[ -n "$VER" ]] || { echo 'cannot read plugin version'; exit 1; }
bundle(){ rm -rf "$1/scripts" "$1/contracts" "$1/examples"; cp -R "$ROOT/scripts" "$ROOT/contracts" "$ROOT/examples" "$1/"; find "$1/scripts" -name '__pycache__' -prune -exec rm -rf {} +; cp "$ROOT/LICENSE" "$1/LICENSE"; }

echo "== Claude Desktop extension"
D=$(mktemp -d); cp -R "$ROOT/extensions/claude-desktop/." "$D/"; bundle "$D"
(cd "$D" && npm install --omit=dev --no-audit --no-fund --loglevel=error && npx -y @anthropic-ai/mcpb@2.1.2 validate manifest.json && npx -y @anthropic-ai/mcpb@2.1.2 pack . "$DIST/devops-agents-$VER.mcpb")

echo "== VS Code extension"
V=$(mktemp -d); cp -R "$ROOT/extensions/vscode/." "$V/"; bundle "$V"
(cd "$V" && node test/parse.test.js && node test/activate.test.js && npx -y @vscode/vsce@4.1.1 package --no-dependencies --allow-missing-repository -o "$DIST/devops-agents-$VER.vsix")
rm -rf "$D" "$V"; ls -la "$DIST"
