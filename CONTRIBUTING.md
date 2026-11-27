# Contributing to InfraCortex

Thanks for helping! This project is a Claude Code plugin (agents, skills, hooks, MCP config) plus a VS Code extension, a Claude Desktop extension and GitHub Copilot agents generated from the same sources.

## Ground rules
- **Token-lean first.** Agent and SKILL files stay under 120 lines (CI enforces it). Put long checklists in `skills/<x>/references/` and load them only when needed. Scripts print one line per finding, not raw tool output.
- **Typed output.** Every agent ends with an AgentReport (`contracts/report.schema.json`). New finding types need a rule ID in `contracts/RULES.md` (`DOMAIN-CAT-NNN`, e.g. `TF-SEC-012`).
- **Safe by default.** Agents never apply, delete or push without the user's approval. Destructive commands belong in `scripts/guard.py` (DENY) or need an ASK rule. Never add anything that prints secrets.
- **No real environment data.** No subscription/tenant IDs, IPs, hostnames, customer or company names in examples, fixtures, evals or `learned.md`.
- **Cross-platform.** Scripts run in bash (Linux, macOS, Git Bash on Windows). Use the `python3 || python` pattern; don't assume `python3` works on Windows.

## Layout
| Path | What |
|---|---|
| `agents/` | the five agents (terraform-engineer, k8s-troubleshooter, docker-engineer, finops-analyst, cortex) |
| `skills/` | expert skills (+ `references/`, `references/learned.md`), slash commands (`tf-review`, `team`, `learn`, …) |
| `scripts/` | scanners (`tf-scan.sh`, `k8s-triage.sh`, …), `guard.py`, `contract_gate.py`, `agent_events.py` (HUD + learning), `hud.ps1`/`hud.py` |
| `hooks/hooks.json` | guard, contract gate, HUD and learning hooks |
| `contracts/` | report schema + rule registry |
| `extensions/` | Claude Desktop (`.mcpb`) and VS Code (`.vsix`) extensions; `build.sh` builds both into `dist/` |
| `evals/` | behaviour evals (`claude plugin eval`) |
| `tests/` | stdlib unit tests + script tests |

## Develop and test
```bash
git clone https://github.com/nandkishor986/infracortex && cd infracortex
pip install python-hcl2 diagrams          # optional extras used by some tests
python -m unittest discover -s tests -v   # must pass
claude plugin validate .                  # plugin manifest/hooks/skills check
claude plugin marketplace add "$PWD" && claude plugin install infracortex@upinclouds   # try it locally
bash extensions/build.sh                  # optional: build .mcpb + .vsix (Node >= 18)
python scripts/make-copilot-agents.py     # optional: regenerate Copilot agents after editing agents/
```
After changing plugin files, bump `version` in `.claude-plugin/plugin.json` (and the extension manifests) and run `claude plugin update infracortex@upinclouds`.

## Improving the agents with real lessons
Agents record their own mistakes and write lessons to local memory. When a lesson proves itself, run `/infracortex:learn all --promote` — it moves generic, secret-free lessons into `skills/<domain>-expert/references/learned.md`. Open a PR with that diff: it's the most valuable kind of contribution, because every user's agents then skip that mistake.

## Pull requests
1. One topic per PR; describe the problem and how you verified the fix (test, eval or a real run).
2. Add or update a test for behaviour changes (`tests/test_contracts.py`).
3. CI must be green (Linux + Windows).
4. Update `CHANGELOG.md` under *Unreleased*.

By contributing you agree your contribution is licensed under the MIT License (see `LICENSE`).
