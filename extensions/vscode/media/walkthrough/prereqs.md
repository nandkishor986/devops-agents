# Prerequisites

InfraCortex runs the real DevOps tools on your machine and reports the results to the agents.

| Tool | Needed for |
|---|---|
| **Git** (+ Git Bash on Windows) | the scanner scripts; Claude Code installs plugins with git |
| **Python 3** | safety guard, report validator, CortexWeave skill memory |
| **jq** | scanner scripts |
| terraform · tflint · trivy | Terraform reviews and security scans |
| hadolint · Docker | Dockerfile audits and the build → run → verify loop |
| kubectl · Azure CLI | cluster triage, Azure lookups, FinOps |

**Install missing tools** uses winget (Windows), Homebrew (macOS) or apt (Linux) in a visible terminal — the installers may ask for permission. Restart VS Code afterwards so it sees the new tools. Missing scanners are simply skipped; nothing breaks.
