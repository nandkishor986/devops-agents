# Claude Code

One click adds the InfraCortex plugin to Claude Code (terminal, VS Code panel and Claude Desktop share it):

- subagents with their own memory, plus a **safety guard** that blocks destroy, auto-approve and resource-group deletes
- typed reports, **self-learning** and the **CortexWeave** skill memory curated by the `overseer`
- the live on-screen HUD showing which agent is working

Then, in the Claude Code panel:

```
/infracortex:terraform-playbook review the KV module in infra/
/infracortex:team . review
/infracortex:devops-expert containerise the app and write the AKS manifest
```

Needs the **Claude Code** extension (the button offers to install it) and Git.
