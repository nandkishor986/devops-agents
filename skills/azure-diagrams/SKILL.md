---
name: azure-diagrams
description: Create Azure architecture diagrams with official Microsoft Azure icons — editable draw.io files or PNG/SVG from one typed JSON spec (or straight from Terraform); edit/export .drawio via CLI-Anything's draw.io CLI. Use when asked to draw, diagram, visualise or document Azure/AKS/network architecture.
---

# Azure architecture diagrams (official icons)

One typed spec → any output. The model writes ~30 lines of JSON; scripts own layout and icons (token-lean, local, diff-able).

| Need | Command | Deps |
|---|---|---|
| Editable diagram (draw.io / diagrams.net / VS Code draw.io extension) | `azdiagram.py render arch.json -o docs/arch --format drawio` | none |
| PNG/SVG for README, ADR, wiki, PR | `azdiagram.py render arch.json -o docs/arch --format png` (or svg) | `pip install diagrams` + Graphviz |
| Tweak / export an existing .drawio (PNG, PDF, SVG, **Visio .vsdx**) | `cli-anything-drawio` (CLI-Anything) — see below | optional |

Script: `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/azdiagram.py` (Windows: `python`)

## Workflow
1. Draft: `azdiagram.py from-tf <tf_dir> > docs/arch.json`, or write the spec (shape: `${CLAUDE_PLUGIN_ROOT}/examples/hub-spoke-aks.json`).
2. Group nodes `subscription → vnet → subnet` (also `rg`, `cluster`, `onprem`, `box`); add `edges` for real traffic / identity / data flows with short labels (protocol, port, auth). ≤ 25 nodes per diagram — split by concern (network, app, CI/CD) beyond that.
3. Render the format the user needs (default: `drawio` + `png` when diagrams is installed). `azdiagram.py types` lists node types. Spec errors come back with exact paths — fix the JSON, don't read the script.
4. Commit `arch.json` alongside outputs: the spec is the source of truth; regenerate rather than hand-editing when the architecture changes.

## Editing/exporting .drawio with CLI-Anything (optional)
If `cli-anything-drawio` is on PATH (HKUDS CLI-Anything draw.io harness), use it for incremental edits instead of regenerating, always with `--json`:
```bash
cli-anything-drawio --json --project docs/arch.drawio shape list
cli-anything-drawio --json --project docs/arch.drawio shape add "image;aspect=fixed;html=1;verticalLabelPosition=bottom;verticalAlign=top;image=img/lib/azure2/databases/Cache_Redis.svg;" --label redis-prod --x 400 --y 300 -w 50 -h 50
cli-anything-drawio --json --project docs/arch.drawio connect add <source_id> <target_id> --style orthogonal
cli-anything-drawio --project docs/arch.drawio export render docs/arch.vsdx -f vsdx
```
- Azure icon styles: copy the `image=img/lib/azure2/...` path for a type from the `DRAWIO` map in azdiagram.py (verified paths). Its built-in shape presets are generic; pass the raw style string as shown.
- It has no container/parent option — add/move icons only; regenerate from the spec for structural (grouping) changes.
- `export render` needs draw.io Desktop installed. `--project` auto-saves on exit.

## Hosted draw.io MCP (opt-in)
Not enabled by default (extra tool schemas every session, and diagram content goes to draw.io's server). Enable only for inline rendering in chat: `claude mcp add --transport http drawio https://mcp.draw.io/mcp`.

## Conventions
Left→right request flow (users → edge → app → data); identity/CI edges `dashed`; logging `dotted`; label every icon with its resource name (Microsoft icon guidance: never crop/recolour/distort icons); title states env + scope.
