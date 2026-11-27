#!/usr/bin/env bash
# Build both extensions into dist/:  dist/infracortex-<ver>.mcpb (Claude Desktop) and dist/infracortex-<ver>.vsix (VS Code)
# Needs: node ≥18, npm. Uses npx @anthropic-ai/mcpb and @vscode/vsce (pinned).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; DIST="$ROOT/dist"; mkdir -p "$DIST"
VER=$(cd "$ROOT" && for c in python3 python; do "$c" -c "import json;print(json.load(open('.claude-plugin/plugin.json'))['version'])" 2>/dev/null && break; done)
[[ -n "$VER" ]] || { echo 'cannot read plugin version'; exit 1; }
bundle(){ rm -rf "$1/scripts" "$1/contracts" "$1/examples"; cp -R "$ROOT/scripts" "$ROOT/contracts" "$ROOT/examples" "$1/"; find "$1/scripts" -name '__pycache__' -prune -exec rm -rf {} +; cp "$ROOT/LICENSE" "$1/LICENSE"; }

echo "== Claude Desktop extension"
D=$(mktemp -d); cp -R "$ROOT/extensions/claude-desktop/." "$D/"; bundle "$D"
(cd "$D" && npm install --omit=dev --no-audit --no-fund --loglevel=error && npx -y @anthropic-ai/mcpb@2.1.2 validate manifest.json && npx -y @anthropic-ai/mcpb@2.1.2 pack . "$DIST/infracortex-$VER.mcpb")

echo "== VS Code extension (one-click: Copilot agents + skills + built-in MCP server + setup)"
winpath(){ if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
PY=$(for c in python3 python; do "$c" -c "" 2>/dev/null && { echo "$c"; break; }; done)
V=$(mktemp -d); cp -R "$ROOT/extensions/vscode/." "$V/"; bundle "$V"
# tests first: activation simulates a first start (it fills in paths), so run it before the agents/skills are added
(cd "$V" && node test/parse.test.js && node test/activate.test.js && node test/setup.test.js)
# Copilot custom agents (overseer stays Claude-Code-only: it curates memory through hooks); paths fixed at first activation
"$PY" "$(winpath "$ROOT/scripts/make-copilot-agents.py")" --out "$(winpath "$V/agents")" --root "{{INFRACORTEX_ROOT}}" --exclude overseer
# Expert skills for Copilot (chatSkills) — same SKILL.md files as the Claude Code plugin
mkdir -p "$V/skills"; for s in terraform-expert k8s-expert docker-expert finops-expert azure-diagrams; do cp -R "$ROOT/skills/$s" "$V/skills/"; done
find "$V/skills" -name '*.md' -exec sed -i 's#${CLAUDE_PLUGIN_ROOT}#{{INFRACORTEX_ROOT}}#g' {} +
# MCP server, run by VS Code's own Node (ELECTRON_RUN_AS_NODE) — no Node install, no mcp.json
mkdir -p "$V/mcp"; cp -R "$ROOT/extensions/claude-desktop/server" "$ROOT/extensions/claude-desktop/package.json" "$V/mcp/"
(cd "$V/mcp" && npm install --omit=dev --no-audit --no-fund --loglevel=error   && npx -y esbuild@0.25.5 server/index.js --bundle --platform=node --format=esm --target=node20 --log-level=warning        "--banner:js=import { createRequire as __cr } from 'module'; const require = __cr(import.meta.url);" --outfile=server/index.bundle.js   && mv server/index.bundle.js server/index.js && rm -rf node_modules package-lock.json)   # one file instead of ~3,500
# guard: the shipped agents/skills must still carry the placeholder (never a build-machine path)
if grep -rlE '([A-Za-z]:/|/tmp/|/Users/)[^ ]*/(scripts|contracts)/' "$V/agents" "$V/skills" >/dev/null; then echo "ERROR: absolute path leaked into bundled agents/skills" >&2; exit 1; fi
grep -q '{{INFRACORTEX_ROOT}}' "$V/agents/terraform-engineer.agent.md" || { echo "ERROR: placeholder missing in bundled agents" >&2; exit 1; }
(cd "$V" && npx -y @vscode/vsce@4.1.1 package --no-dependencies --allow-missing-repository -o "$DIST/infracortex-$VER.vsix")
rm -rf "$D" "$V"; ls -la "$DIST"
