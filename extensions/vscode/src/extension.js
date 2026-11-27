// InfraCortex — VS Code extension. Runs the toolkit's bundled scripts, shows the digest in an
// Output channel and puts rule-ID findings into the Problems panel. No chat, no tokens.
"use strict";
const vscode = require("vscode");
const { execFile } = require("child_process");
const fs = require("fs");
const path = require("path");
const { parseFindings, loadRuleSeverities } = require("./parse");

let out, diags, rules = {};
const SEV = { CRITICAL: 0, HIGH: 0, MEDIUM: 1, LOW: 2, INFO: 3 }; // vscode.DiagnosticSeverity values

function cfg(k, d) { return vscode.workspace.getConfiguration("devopsAgents").get(k, d); }
function root(ctx) { return ctx.extensionPath; }
function ws() {
  const f = vscode.workspace.workspaceFolders;
  if (!f || !f.length) throw new Error("Open a folder first.");
  return f[0].uri.fsPath;
}
function bash() {
  const c = cfg("bashPath", "");
  if (c) return c;
  if (process.platform === "win32") {
    for (const p of ["C:\\Program Files\\Git\\bin\\bash.exe", "C:\\Program Files (x86)\\Git\\bin\\bash.exe"]) if (fs.existsSync(p)) return p;
  }
  return "bash";
}
function python() { return cfg("pythonPath", "") || (process.platform === "win32" ? "python" : "python3"); }

function run(ctx, title, cmd, args, parseCtx) {
  out.show(true);
  out.appendLine(`\n━━ ${title}  ·  ${new Date().toLocaleTimeString()}`);
  return vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: `InfraCortex: ${title}`, cancellable: true },
    (_p, token) => new Promise((resolve) => {
      const child = execFile(cmd, args, { cwd: ws(), maxBuffer: 16 * 1024 * 1024, windowsHide: true,
        env: { ...process.env, DEVOPS_CURRENCY: cfg("currency", "INR") } }, (err, so, se) => {
        const text = `${so || ""}${se ? `\n${se}` : ""}`;
        out.appendLine(text.trim() || "(no output)");
        if (err && err.code === "ENOENT") vscode.window.showErrorMessage(`Cannot start ${cmd}. Set devopsAgents.bashPath / pythonPath.`);
        if (parseCtx) publish(text, parseCtx);
        resolve(text);
      });
      token.onCancellationRequested(() => child.kill());
    }));
}
const sh = (ctx, title, script, args, parseCtx) => run(ctx, title, bash(), [path.join(root(ctx), "scripts", script), ...args], parseCtx);

function publish(text, parseCtx) {
  const found = parseFindings(text, parseCtx);
  const byFile = new Map();
  for (const f of found) {
    if (!f.file) continue;
    const r = rules[f.id];
    const sev = f.sev || (r ? r.sev : "MEDIUM");
    const d = new vscode.Diagnostic(new vscode.Range(f.line, 0, f.line, 200), `${f.message}${r ? ` — ${r.title}` : ""}`, SEV[sev] ?? 1);
    d.source = "infracortex"; d.code = f.id;
    const k = vscode.Uri.file(f.file).toString();
    if (!byFile.has(k)) byFile.set(k, []);
    byFile.get(k).push(d);
  }
  for (const [k, list] of byFile) diags.set(vscode.Uri.parse(k), list);
  const n = found.length;
  vscode.window.showInformationMessage(n ? `InfraCortex: ${n} finding(s) — see Problems panel.` : "InfraCortex: no findings.", ...(n ? ["Open Problems"] : []))
    .then((b) => b && vscode.commands.executeCommand("workbench.actions.view.problems"));
}

async function pickFolder(label, uri) {
  if (uri && uri.fsPath) return fs.statSync(uri.fsPath).isDirectory() ? uri.fsPath : path.dirname(uri.fsPath);
  const ed = vscode.window.activeTextEditor;
  const def = ed ? vscode.Uri.file(path.dirname(ed.document.uri.fsPath)) : vscode.Uri.file(ws());
  const r = await vscode.window.showOpenDialog({ canSelectFolders: true, canSelectFiles: false, defaultUri: def, openLabel: label });
  return r && r[0] ? r[0].fsPath : null;
}
async function pickFile(label, filters, uri) {
  if (uri && uri.fsPath && fs.statSync(uri.fsPath).isFile()) return uri.fsPath;
  const ed = vscode.window.activeTextEditor;
  if (ed && filters.test(path.basename(ed.document.uri.fsPath))) return ed.document.uri.fsPath;
  const r = await vscode.window.showOpenDialog({ canSelectFiles: true, defaultUri: vscode.Uri.file(ws()), openLabel: label });
  return r && r[0] ? r[0].fsPath : null;
}

function activate(ctx) {
  out = vscode.window.createOutputChannel("InfraCortex");
  diags = vscode.languages.createDiagnosticCollection("infracortex");
  rules = loadRuleSeverities(path.join(root(ctx), "contracts", "RULES.md"));
  require("./setup").activate(ctx, out);   // one-click layer: Copilot agents/skills, MCP server, prerequisites, Claude Code
  const reg = (id, fn) => ctx.subscriptions.push(vscode.commands.registerCommand(id, async (...a) => {
    try { await fn(...a); } catch (e) { vscode.window.showErrorMessage(`InfraCortex: ${e.message}`); }
  }));

  reg("devopsAgents.tfScan", async (uri) => {
    const dir = await pickFolder("Scan Terraform", uri); if (!dir) return;
    await sh(ctx, `Terraform scan · ${path.basename(dir)}`, "tf-scan.sh", [dir, ...(cfg("terraformInit", false) ? [] : ["--no-init"])], { baseDir: dir });
  });
  reg("devopsAgents.k8sManifests", async (uri) => {
    const dir = await pickFolder("Review manifests", uri); if (!dir) return;
    await sh(ctx, `K8s manifest review · ${path.basename(dir)}`, "k8s-triage.sh", ["--manifests", dir], { baseDir: dir });
  });
  reg("devopsAgents.k8sTriage", async () => {
    const ns = await vscode.window.showInputBox({ prompt: "Namespace (empty = all, read-only)", validateInput: (v) => !v || /^[a-z0-9-]{1,63}$/.test(v) ? null : "invalid namespace" });
    if (ns === undefined) return;
    const pod = ns ? await vscode.window.showInputBox({ prompt: "Pod (optional deep dive)", validateInput: (v) => !v || /^[a-z0-9.-]{1,253}$/.test(v) ? null : "invalid pod" }) : "";
    await sh(ctx, `K8s triage · ${ns || "all"}`, "k8s-triage.sh", ns ? ["-n", ns, ...(pod ? ["-p", pod] : [])] : ["-A"]);
  });
  reg("devopsAgents.dockerAudit", async (uri) => {
    const f = await pickFile("Audit Dockerfile", /Dockerfile/i, uri); if (!f) return;
    await sh(ctx, `Docker audit · ${path.basename(path.dirname(f))}`, "docker-audit.sh", ["-f", f], { dockerfile: f, baseDir: path.dirname(f) });
  });
  reg("devopsAgents.dockerVerify", async (uri) => {
    const f = await pickFile("Verify Dockerfile", /Dockerfile/i, uri); if (!f) return;
    const port = await vscode.window.showInputBox({ prompt: "Container port to probe (empty = skip)", validateInput: (v) => !v || (/^\d+$/.test(v) && +v < 65536) ? null : "port number" });
    if (port === undefined) return;
    const hard = await vscode.window.showQuickPick(["normal", "hardened (read-only, cap-drop ALL)"], { placeHolder: "Run mode" });
    if (!hard) return;
    await sh(ctx, `Docker verify · ${path.basename(path.dirname(f))}`, "docker-verify.sh",
      ["-f", f, ...(port ? ["-p", port] : []), ...(hard.startsWith("hardened") ? ["--hardened"] : [])], { dockerfile: f, baseDir: path.dirname(f) });
  });
  reg("devopsAgents.finopsScan", async () => {
    const sub = await vscode.window.showInputBox({ prompt: "Subscription name/id (empty = current az account)" });
    if (sub === undefined) return;
    await sh(ctx, "FinOps waste scan", "finops-scan.sh", sub ? ["--sub", sub] : []);
  });
  reg("devopsAgents.tfCost", async (uri) => {
    const dir = await pickFolder("Cost of Terraform", uri); if (!dir) return;
    await sh(ctx, `Terraform cost · ${path.basename(dir)}`, "finops-scan.sh", ["--tf", dir]);
  });
  reg("devopsAgents.price", async () => {
    const preset = await vscode.window.showQuickPick(["private-endpoint", "private-dns-zone", "storage", "vm", "aks-uptime", "fx (USD→currency rate)"], { placeHolder: "Price preset" });
    if (!preset) return;
    const cur = cfg("currency", "INR");
    if (preset.startsWith("fx")) return sh(ctx, `FX USD→${cur}`, "az-price.sh", ["fx", cur]);
    let arg = "";
    if (preset === "storage" || preset === "vm") {
      arg = await vscode.window.showInputBox({ prompt: preset === "vm" ? "VM size (e.g. D4s_v5)" : "Storage SKU (e.g. Hot LRS)", value: preset === "vm" ? "D4s_v5" : "Hot LRS" });
      if (!arg) return;
    }
    const region = await vscode.window.showInputBox({ prompt: "Region", value: cfg("defaultRegion", "eastus2"), validateInput: (v) => /^[a-z0-9]{2,40}$/.test(v) ? null : "e.g. eastus2, centralindia" });
    if (!region) return;
    await sh(ctx, `Price · ${preset} ${arg} · ${region} · ${cur}`, "az-price.sh", ["preset", preset, ...(arg ? [arg] : []), "--region", region, "--currency", cur]);
  });
  reg("devopsAgents.diagram", async (uri) => {
    const spec = await pickFile("Render diagram spec", /\.json$/i, uri); if (!spec) return;
    const fmt = await vscode.window.showQuickPick(["drawio", "png", "svg"], { placeHolder: "Format (drawio needs nothing; png/svg need pip diagrams + Graphviz)" });
    if (!fmt) return;
    const outBase = spec.replace(/\.json$/i, "");
    await run(ctx, `Diagram · ${path.basename(spec)} → ${fmt}`, python(), [path.join(root(ctx), "scripts", "azdiagram.py"), "render", spec, "-o", outBase, "--format", fmt]);
    const file = `${outBase}.${fmt}`;
    if (fs.existsSync(file)) vscode.commands.executeCommand("vscode.open", vscode.Uri.file(file));
  });
  reg("devopsAgents.diagramFromTf", async (uri) => {
    const dir = await pickFolder("Draft diagram from Terraform", uri); if (!dir) return;
    const text = await run(ctx, `Diagram spec from ${path.basename(dir)}`, python(), [path.join(root(ctx), "scripts", "azdiagram.py"), "from-tf", dir]);
    const target = path.join(dir, "arch.json");
    if (text.trim().startsWith("{") && !fs.existsSync(target)) { fs.writeFileSync(target, text); vscode.commands.executeCommand("vscode.open", vscode.Uri.file(target)); }
    else if (fs.existsSync(target)) vscode.window.showWarningMessage(`${target} exists — not overwritten (spec printed in Output).`);
  });
  reg("devopsAgents.checkCommand", async () => {
    const ed = vscode.window.activeTextEditor;
    const sel = ed && !ed.selection.isEmpty ? ed.document.getText(ed.selection) : "";
    const cmd = sel || await vscode.window.showInputBox({ prompt: "Shell command to classify (deny / ask / allow)" });
    if (!cmd) return;
    const res = await new Promise((resolve) => {
      const c = execFile(python(), ["-c", "import json,sys; sys.path.insert(0, sys.argv[1]); import guard; v=guard.decide(sys.stdin.read(), use_jev=False); print(json.dumps({'decision': v[0] if v else 'allow', 'reason': v[1] if v else 'no rule matched'}))", path.join(root(ctx), "scripts")],
        { windowsHide: true }, (e, so) => resolve(so));
      c.stdin.end(cmd);
    });
    try { const r = JSON.parse(res); const fn = r.decision === "deny" ? "showErrorMessage" : r.decision === "ask" ? "showWarningMessage" : "showInformationMessage"; vscode.window[fn](`${r.decision.toUpperCase()}: ${r.reason}`); }
    catch { vscode.window.showErrorMessage("Python not found — set devopsAgents.pythonPath."); }
  });
  reg("devopsAgents.clear", async () => diags.clear());

  const tree = new ActionsTree();
  ctx.subscriptions.push(out, diags, vscode.window.registerTreeDataProvider("devopsAgents.actions", tree));
}

class ActionsTree {
  getTreeItem(e) { return e; }
  getChildren() {
    return [
      ["Terraform: scan folder", "devopsAgents.tfScan", "search"], ["Terraform: cost (Infracost)", "devopsAgents.tfCost", "credit-card"],
      ["Kubernetes: review manifests", "devopsAgents.k8sManifests", "checklist"], ["Kubernetes: triage cluster (read-only)", "devopsAgents.k8sTriage", "pulse"],
      ["Docker: audit Dockerfile", "devopsAgents.dockerAudit", "shield"], ["Docker: build → run → diagnose", "devopsAgents.dockerVerify", "debug-alt"],
      ["FinOps: waste scan (az login)", "devopsAgents.finopsScan", "graph"], ["FinOps: price lookup", "devopsAgents.price", "tag"],
      ["Diagram: spec from Terraform", "devopsAgents.diagramFromTf", "type-hierarchy"], ["Diagram: render spec", "devopsAgents.diagram", "file-media"],
      ["Check command safety", "devopsAgents.checkCommand", "lock"], ["Clear findings", "devopsAgents.clear", "clear-all"],
    ].map(([label, command, icon]) => { const t = new vscode.TreeItem(label); t.command = { command, title: label }; t.iconPath = new vscode.ThemeIcon(icon); return t; });
  }
}

function deactivate() {}
module.exports = { activate, deactivate };
