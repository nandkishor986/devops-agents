// InfraCortex one-click layer: Copilot agents/skills path fix-up, built-in MCP server, prerequisite check + installer,
// "Enable in Claude Code", first-run walkthrough and cleanup of the old manual setup.
const vscode = require("vscode");
const { execFile, execFileSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const PLACEHOLDER = "{{INFRACORTEX_ROOT}}";
const WIN = process.platform === "win32", MAC = process.platform === "darwin";
const MARKETPLACE = { repo: "nandkishor986/infracortex", name: "upinclouds", plugin: "infracortex@upinclouds" };

// need: required = core features break without it · recommended = a domain's scanner · optional = extra
const TOOLS = [
  { id: "git", label: "Git (+ Git Bash on Windows)", need: "required", bins: ["git"], win: "Git.Git", mac: "git", apt: "git", why: "scripts run in bash; Claude Code installs plugins with git" },
  { id: "python", label: "Python 3", need: "required", bins: WIN ? ["python"] : ["python3"], win: "Python.Python.3.12", mac: "python@3.12", apt: "python3 python3-pip", why: "hooks, guard, report validator, CortexWeave" },
  { id: "jq", label: "jq", need: "required", bins: ["jq"], win: "jqlang.jq", mac: "jq", apt: "jq", why: "scanner scripts parse JSON" },
  { id: "terraform", label: "Terraform", need: "recommended", bins: ["terraform"], win: "Hashicorp.Terraform", mac: "hashicorp/tap/terraform", why: "fmt/validate for terraform-engineer" },
  { id: "tflint", label: "tflint", need: "recommended", bins: ["tflint"], win: "TerraformLinters.tflint", mac: "tflint", why: "Terraform lint rules" },
  { id: "trivy", label: "Trivy", need: "recommended", bins: ["trivy"], win: "AquaSecurity.Trivy", mac: "trivy", why: "IaC + image security scans" },
  { id: "hadolint", label: "hadolint", need: "recommended", bins: ["hadolint"], win: "hadolint.hadolint", mac: "hadolint", why: "Dockerfile lint for docker-engineer" },
  { id: "kubectl", label: "kubectl", need: "recommended", bins: ["kubectl"], win: "Kubernetes.kubectl", mac: "kubectl", why: "cluster triage for k8s-troubleshooter" },
  { id: "az", label: "Azure CLI", need: "recommended", bins: ["az"], win: "Microsoft.AzureCLI", mac: "azure-cli", why: "Azure lookups + FinOps" },
  { id: "docker", label: "Docker", need: "optional", bins: ["docker"], win: "Docker.DockerDesktop", mac: "--cask docker", apt: "docker.io", why: "Docker verify loop, Terraform MCP" },
  { id: "infracost", label: "Infracost", need: "optional", bins: ["infracost"], win: "Infracost.Infracost", mac: "infracost", why: "Terraform cost diffs" },
];

let out, status, mcpChanged;

function cfg(k, d) { return vscode.workspace.getConfiguration("devopsAgents").get(k, d); }

// ---------------------------------------------------------------- PATH / tool detection (sees installs made after VS Code started)
function freshPath() {
  if (!WIN) return process.env.PATH || "";
  try {
    return execFileSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command",
      "[Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')"],
      { encoding: "utf8", windowsHide: true, timeout: 8000 }).trim() + ";" + (process.env.PATH || "");
  } catch { return process.env.PATH || ""; }
}

function which(bin, pathStr) {
  const exts = WIN ? (process.env.PATHEXT || ".EXE;.CMD;.BAT").split(";").concat([""]) : [""];
  const extra = WIN ? [path.join(process.env.LOCALAPPDATA || "", "Microsoft", "WinGet", "Links")] : ["/opt/homebrew/bin", "/usr/local/bin"];
  for (const dir of pathStr.split(path.delimiter).concat(extra)) {
    if (!dir) continue;
    for (const e of exts) {
      const p = path.join(dir.replace(/^"|"$/g, ""), bin + e);
      try { if (fs.statSync(p).isFile() && !/WindowsApps[\\/]python3?\.exe$/i.test(p)) return p; } catch { /* next */ }
    }
  }
  return null;
}

function gitBash() {
  const cands = [cfg("bashPath", ""), "C:\\Program Files\\Git\\bin\\bash.exe", "C:\\Program Files (x86)\\Git\\bin\\bash.exe",
    path.join(process.env.LOCALAPPDATA || "", "Programs", "Git", "bin", "bash.exe")];
  return cands.find((p) => p && fs.existsSync(p)) || null;
}

function realPython(p) {           // the Microsoft Store stub exists on PATH but can't run code
  try { execFileSync(p, ["-c", "pass"], { windowsHide: true, timeout: 8000, stdio: "ignore" }); return true; } catch { return false; }
}

function checkTools() {
  const pathStr = freshPath();
  return TOOLS.map((t) => {
    let found = t.bins.map((b) => which(b, pathStr)).find(Boolean) || null;
    if (t.id === "python" && found && !realPython(found)) found = null;
    if (t.id === "git" && WIN && found && !gitBash()) return { ...t, found: null, note: "git found but Git Bash missing" };
    return { ...t, found };
  });
}

function summarize(results) {
  const missing = results.filter((r) => !r.found);
  return { missing, required: missing.filter((r) => r.need === "required"), recommended: missing.filter((r) => r.need === "recommended") };
}

function updateStatus(results) {
  if (!status) return;
  const s = summarize(results);
  status.text = s.required.length ? `$(warning) InfraCortex: ${s.required.length} required missing` : s.recommended.length ? `$(hubot) InfraCortex · ${s.recommended.length} optional scanners missing` : "$(hubot) InfraCortex ready";
  status.tooltip = s.missing.length ? "Missing: " + s.missing.map((m) => m.label).join(", ") + "\nClick to check / install" : "All prerequisites found";
  status.backgroundColor = s.required.length ? new vscode.ThemeColor("statusBarItem.warningBackground") : undefined;
  status.show();
}

async function cmdCheck() {
  const results = await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: "InfraCortex: checking prerequisites…" }, async () => checkTools());
  updateStatus(results);
  out.appendLine("\n== Prerequisites");
  for (const r of results) out.appendLine(`${r.found ? "✓" : "✗"} ${r.label.padEnd(28)} ${r.need.padEnd(12)} ${r.found || r.note || "missing — " + r.why}`);
  const s = summarize(results);
  if (!s.missing.length) { vscode.window.showInformationMessage("InfraCortex: all prerequisites are installed."); return results; }
  const pick = await vscode.window.showWarningMessage(
    `InfraCortex: ${s.required.length} required and ${s.missing.length - s.required.length} optional tools missing (${s.missing.map((m) => m.label).join(", ")}).`,
    "Install missing tools", "Show details");
  if (pick === "Install missing tools") await cmdInstall(results);
  if (pick === "Show details") out.show(true);
  return results;
}

function installCommand(missing) {
  if (WIN) {
    const ids = missing.filter((m) => m.win).map((m) => m.win);
    const parts = ids.map((id) => `winget install -e --id ${id} --silent --accept-package-agreements --accept-source-agreements`);
    if (missing.some((m) => m.id === "python") || !missing.length) parts.push("python -m pip install --user python-hcl2");
    return parts.join("; ");
  }
  if (MAC) {
    const casks = missing.filter((m) => (m.mac || "").startsWith("--cask")).map((m) => m.mac.replace("--cask ", ""));
    const pk = missing.filter((m) => m.mac && !m.mac.startsWith("--cask")).map((m) => m.mac);
    return [pk.length ? `brew install ${pk.join(" ")}` : "", casks.length ? `brew install --cask ${casks.join(" ")}` : "", "python3 -m pip install --user python-hcl2"].filter(Boolean).join(" && ");
  }
  const apt = missing.filter((m) => m.apt).map((m) => m.apt);
  return [apt.length ? `sudo apt-get update && sudo apt-get install -y ${apt.join(" ")}` : "", "python3 -m pip install --user python-hcl2"].filter(Boolean).join(" && ");
}

async function cmdInstall(results) {
  const missing = summarize(results && results.length ? results : checkTools()).missing.filter((m) => m.need !== "optional" || cfg("installOptionalTools", false));
  if (!missing.length) { vscode.window.showInformationMessage("InfraCortex: nothing to install."); return; }
  const cmd = installCommand(missing);
  const how = WIN ? "winget" : MAC ? "Homebrew" : "apt (you'll be asked for your sudo password)";
  const ok = await vscode.window.showInformationMessage(
    `Install ${missing.map((m) => m.label).join(", ")} with ${how}? It runs in a visible terminal; installers may ask for permission.`,
    { modal: true, detail: cmd }, "Install");
  if (ok !== "Install") return;
  const term = vscode.window.createTerminal({ name: "InfraCortex setup", shellPath: WIN ? "powershell.exe" : undefined });
  term.show();
  term.sendText(cmd);
  vscode.window.showInformationMessage("InfraCortex: when the installs finish, restart VS Code so it sees the new tools, then run 'InfraCortex: Check prerequisites'.");
}

// ---------------------------------------------------------------- Claude Code
function claudeBinary() {
  const onPath = which("claude", freshPath());
  if (onPath) return onPath;
  const ext = vscode.extensions && vscode.extensions.getExtension("anthropic.claude-code");
  if (!ext) return null;
  const p = path.join(ext.extensionPath, "resources", "native-binary", WIN ? "claude.exe" : "claude");
  return fs.existsSync(p) ? p : null;
}

function runClaude(bin, args) {
  return new Promise((resolve) => {
    out.appendLine(`$ claude ${args.join(" ")}`);
    execFile(bin, args, { windowsHide: true, timeout: 180000, env: { ...process.env, PATH: freshPath() } }, (err, so, se) => {
      const text = `${so || ""}${se || ""}`.trim();
      if (text) out.appendLine(text);
      resolve({ ok: !err, text });
    });
  });
}

async function cmdEnableClaude() {
  const bin = claudeBinary();
  if (!bin) {
    const pick = await vscode.window.showWarningMessage("InfraCortex: Claude Code isn't installed. Install the Claude Code extension first, then click 'Enable in Claude Code' again.", "Install Claude Code");
    if (pick) await vscode.commands.executeCommand("workbench.extensions.installExtension", "anthropic.claude-code");
    return false;
  }
  out.show(true);
  return vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: "InfraCortex: enabling in Claude Code…" }, async () => {
    const list = await runClaude(bin, ["plugin", "list"]);
    if (/infracortex@/i.test(list.text)) {
      await runClaude(bin, ["plugin", "marketplace", "update", MARKETPLACE.name]);
      const up = await runClaude(bin, ["plugin", "update", MARKETPLACE.plugin]);
      vscode.window.showInformationMessage(`InfraCortex is enabled in Claude Code${up.ok ? " and up to date" : ""}. Restart the Claude Code panel, then try /infracortex:terraform-expert or /infracortex:team.`);
      return true;
    }
    const mk = await runClaude(bin, ["plugin", "marketplace", "list"]);
    if (!new RegExp(`\\b${MARKETPLACE.name}\\b`).test(mk.text)) {
      const add = await runClaude(bin, ["plugin", "marketplace", "add", MARKETPLACE.repo]);
      if (!add.ok) { vscode.window.showErrorMessage("InfraCortex: couldn't add the marketplace (is Git installed and GitHub reachable?). See Output → InfraCortex."); return false; }
    }
    const inst = await runClaude(bin, ["plugin", "install", MARKETPLACE.plugin, "--scope", "user"]);
    if (!inst.ok) { vscode.window.showErrorMessage("InfraCortex: plugin install failed. See Output → InfraCortex."); return false; }
    vscode.window.showInformationMessage("InfraCortex is enabled in Claude Code. Restart the Claude Code panel, then try /infracortex:terraform-expert or /infracortex:team.");
    return true;
  });
}

// ---------------------------------------------------------------- Copilot: bundled agents/skills + MCP server
function fixBundledPaths(root) {
  const fwd = root.replace(/\\/g, "/");
  let n = 0;
  const walk = (d) => {
    let entries = [];
    try { entries = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith(".md")) {
        try {
          const t = fs.readFileSync(p, "utf8");
          if (t.includes(PLACEHOLDER)) { fs.writeFileSync(p, t.split(PLACEHOLDER).join(fwd)); n++; }
        } catch (err) { out.appendLine(`could not update ${p}: ${err.message}`); }
      }
    }
  };
  for (const sub of ["agents", "skills"]) walk(path.join(root, sub));
  return n;
}

function registerMcp(ctx) {
  if (!vscode.lm || typeof vscode.lm.registerMcpServerDefinitionProvider !== "function" || !vscode.McpStdioServerDefinition) {
    out.appendLine("This VS Code has no MCP extension API — update VS Code to use the InfraCortex tools in Copilot.");
    return;
  }
  mcpChanged = new vscode.EventEmitter();
  ctx.subscriptions.push(mcpChanged, vscode.lm.registerMcpServerDefinitionProvider("infracortex", {
    onDidChangeMcpServerDefinitions: mcpChanged.event,
    provideMcpServerDefinitions: async () => {
      const folder = (vscode.workspace.workspaceFolders || [])[0];
      const env = { ELECTRON_RUN_AS_NODE: "1", INFRACORTEX_ROOT: ctx.extensionPath, DEVOPS_CLIENT: "Copilot (VS Code)",
        DEVOPS_WORKSPACE: folder ? folder.uri.fsPath : os.homedir(), DEVOPS_CURRENCY: vscode.workspace.getConfiguration("devopsAgents").get("currency", "INR"),
        DEVOPS_PYTHON: vscode.workspace.getConfiguration("devopsAgents").get("pythonPath", "") || (WIN ? "python" : "python3"),
        PATH: freshPath() };
      const bash = WIN ? gitBash() : "bash";
      if (bash) env.DEVOPS_BASH = bash;
      return [new vscode.McpStdioServerDefinition("InfraCortex", process.execPath, [path.join(ctx.extensionPath, "mcp", "server", "index.js")], env, ctx.extension ? ctx.extension.packageJSON.version : undefined)];
    },
  }));
  ctx.subscriptions.push(vscode.workspace.onDidChangeWorkspaceFolders(() => mcpChanged.fire()));
}

// ---------------------------------------------------------------- one-time cleanup of the old manual setup (files we generated)
function userDir() {
  return WIN ? path.join(process.env.APPDATA || "", "Code", "User") : MAC ? path.join(os.homedir(), "Library", "Application Support", "Code", "User") : path.join(os.homedir(), ".config", "Code", "User");
}

function legacyItems() {
  const items = [];
  const prompts = path.join(userDir(), "prompts");
  try {
    for (const f of fs.readdirSync(prompts)) {
      const p = path.join(prompts, f);
      if (f.endsWith(".agent.md") && fs.readFileSync(p, "utf8").includes("> **Copilot edition.**")) items.push({ kind: "agent", path: p });
    }
  } catch { /* none */ }
  const mcp = path.join(userDir(), "mcp.json");
  try {
    const j = JSON.parse(fs.readFileSync(mcp, "utf8"));
    for (const [k, v] of Object.entries(j.servers || {})) {
      if ((v.args || []).some((a) => /[\\/]\.(infracortex|devops-agents)[\\/]mcp-server[\\/]/.test(a))) items.push({ kind: "mcp", path: mcp, key: k });
    }
  } catch { /* none */ }
  return items;
}

async function offerCleanup(ctx) {
  if (ctx.globalState.get("legacyCleanupAsked")) return;
  const items = legacyItems();
  if (!items.length) { await ctx.globalState.update("legacyCleanupAsked", true); return; }
  const pick = await vscode.window.showInformationMessage(
    `InfraCortex now provides its Copilot agents and MCP server itself. Remove the ${items.length} old manually installed copies so they don't appear twice?`,
    "Remove old copies", "Keep");
  await ctx.globalState.update("legacyCleanupAsked", true);
  if (pick !== "Remove old copies") return;
  for (const it of items) {
    try {
      if (it.kind === "agent") fs.unlinkSync(it.path);
      else { const j = JSON.parse(fs.readFileSync(it.path, "utf8")); delete j.servers[it.key]; fs.writeFileSync(it.path, JSON.stringify(j, null, 2) + "\n"); }
      out.appendLine(`removed old ${it.kind}: ${it.path}${it.key ? " (" + it.key + ")" : ""}`);
    } catch (e) { out.appendLine(`could not remove ${it.path}: ${e.message}`); }
  }
}

// ---------------------------------------------------------------- activation
function activate(ctx, channel) {
  out = channel;
  const fixed = fixBundledPaths(ctx.extensionPath);
  if (fixed) out.appendLine(`InfraCortex: pointed ${fixed} bundled agent/skill files at ${ctx.extensionPath}`);
  registerMcp(ctx);
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 50);
  status.command = "infracortex.checkPrereqs";
  status.text = "$(hubot) InfraCortex";
  status.show();
  ctx.subscriptions.push(status);
  const reg = (id, fn) => ctx.subscriptions.push(vscode.commands.registerCommand(id, async (...a) => {
    try { return await fn(...a); } catch (e) { vscode.window.showErrorMessage(`InfraCortex: ${e.message}`); }
  }));
  reg("infracortex.checkPrereqs", cmdCheck);
  reg("infracortex.installPrereqs", () => cmdInstall(null));
  reg("infracortex.enableClaude", cmdEnableClaude);
  reg("infracortex.openCopilotAgent", async () => {
    await vscode.commands.executeCommand("workbench.action.chat.open", { mode: "agent" }).then(undefined, () => vscode.commands.executeCommand("workbench.action.chat.open"));
    vscode.window.showInformationMessage("In Copilot Chat, pick terraform-engineer, k8s-troubleshooter, docker-engineer, finops-analyst or cortex from the agent dropdown.");
  });
  reg("infracortex.getStarted", () => vscode.commands.executeCommand("workbench.action.openWalkthrough", `${ctx.extension ? ctx.extension.id : "upinclouds.infracortex"}#infracortex.setup`, false));
  // background: status bar check + first-run walkthrough + cleanup offer (never blocks activation)
  const t = setTimeout(async () => {
    try { updateStatus(checkTools()); } catch { /* ignore */ }
    if (!ctx.globalState.get("walkthroughShown")) {
      await ctx.globalState.update("walkthroughShown", true);
      vscode.commands.executeCommand("infracortex.getStarted").then(undefined, () => {});
    }
    offerCleanup(ctx).catch(() => {});
  }, 2500);
  if (t.unref) t.unref();
}

module.exports = { activate, TOOLS, installCommand, which, legacyItems, fixBundledPaths, PLACEHOLDER };
