# InfraCortex for VS Code (upinclouds)

Runs the InfraCortex scanners from VS Code and puts the findings, tagged with rule IDs, into the **Problems** panel. It works on its own (no chat, no tokens) and alongside the Claude Code plugin.

- **Sidebar:** the *InfraCortex* icon in the activity bar lists every action.
- **Right-click:** a folder gives *Terraform: Scan Folder*, *Kubernetes: Review Manifests*, *Terraform: Cost* and *Diagram: Spec from Terraform*. A Dockerfile gives *Docker: Audit* and *Docker: Build → Run → Diagnose*. A `.json` spec gives *Diagram: Render Spec*.
- **Command palette:** every command is under `InfraCortex:`.
- **Settings:** `devopsAgents.currency` (default INR), `defaultRegion`, `bashPath` (Windows: Git Bash, auto-detected), `pythonPath`, `terraformInit`.

Each script skips any tool you don't have installed (terraform, tflint, trivy, kubectl, hadolint, az, docker), so start with what you have. Severity comes from the toolkit's rule registry: CRITICAL/HIGH are errors, MEDIUM a warning, LOW/INFO information.
