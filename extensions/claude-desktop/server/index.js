#!/usr/bin/env node
// InfraCortex — Claude Desktop extension (MCP server over stdio).
// Exposes the toolkit's scanners as typed MCP tools. Every tool:
//   · runs a bundled script with an argument ARRAY (execFile, no shell → no injection)
//   · resolves paths inside the configured workspace only (no ../ escapes)
//   · returns the script's compact, rule-ID-tagged digest (capped), never raw tool dumps
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFile } from "node:child_process";
import { existsSync, realpathSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = process.env.INFRACORTEX_ROOT ? path.resolve(process.env.INFRACORTEX_ROOT) : path.resolve(HERE, "..");   // VS Code extension passes its own dir; .mcpb bundles scripts next to server/
const SCRIPTS = path.join(ROOT, "scripts");
const WORKSPACE = process.env.DEVOPS_WORKSPACE ? path.resolve(process.env.DEVOPS_WORKSPACE) : process.cwd();
const CURRENCY = (process.env.DEVOPS_CURRENCY || "INR").toUpperCase();
const MAX_OUT = 20000;

function findBash() {
  const cfg = process.env.DEVOPS_BASH;
  if (cfg && existsSync(cfg)) return cfg;
  if (process.platform === "win32") {
    for (const p of ["C:\\Program Files\\Git\\bin\\bash.exe", "C:\\Program Files (x86)\\Git\\bin\\bash.exe",
      path.join(process.env.LOCALAPPDATA || "", "Programs", "Git", "bin", "bash.exe")]) if (existsSync(p)) return p;
  }
  return "bash";
}
function findPython() {
  const cfg = process.env.DEVOPS_PYTHON;
  if (cfg) return cfg;
  return process.platform === "win32" ? "python" : "python3";
}
const BASH = findBash(), PYTHON = findPython();

/** Resolve a user path inside WORKSPACE; throws on escape. Relative paths are relative to WORKSPACE. */
export function inWorkspace(p, { mustExist = true } = {}) {
  const abs = path.resolve(WORKSPACE, p || ".");
  const real = existsSync(abs) ? realpathSync(abs) : abs;
  const root = existsSync(WORKSPACE) ? realpathSync(WORKSPACE) : WORKSPACE;
  const rel = path.relative(root, real);
  if (rel.startsWith("..") || path.isAbsolute(rel)) throw new Error(`path outside workspace (${root}): ${p}`);
  if (mustExist && !existsSync(real)) throw new Error(`not found in workspace: ${p}`);
  return real;
}

function run(cmd, args, { cwd = WORKSPACE, timeoutMs = 300000, env = {} } = {}) {
  return new Promise((resolve) => {
    execFile(cmd, args, { cwd, timeout: timeoutMs, maxBuffer: 8 * 1024 * 1024, windowsHide: true,
      env: { ...process.env, DEVOPS_CURRENCY: CURRENCY, ...env } },
      (err, stdout, stderr) => {
        let out = (stdout || "") + (stderr ? `\n${stderr}` : "");
        if (err && err.code === "ENOENT") out = `ERR cannot start ${cmd} — install it or set its path in the extension settings`;
        else if (err && err.killed) out += `\nERR timed out after ${Math.round(timeoutMs / 1000)}s`;
        if (out.length > MAX_OUT) out = out.slice(0, MAX_OUT) + `\n… truncated (${out.length - MAX_OUT} chars)`;
        resolve({ text: out.trim() || "(no output)", code: err ? (typeof err.code === "number" ? err.code : 1) : 0 });
      });
  });
}
const bash = (script, args, opts) => run(BASH, [path.join(SCRIPTS, script), ...args], opts);
const py = (script, args, opts) => run(PYTHON, [path.join(SCRIPTS, script), ...args], opts);
const reply = ({ text, code }) => ({ content: [{ type: "text", text }], isError: code !== 0 && /^ERR /m.test(text) });
const safe = (fn) => async (a) => { try { return reply(await fn(a)); } catch (e) { return { content: [{ type: "text", text: `ERR ${e.message}` }], isError: true }; } };

const NAME = /^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$/;           // k8s names / namespaces
const IMAGE = /^[A-Za-z0-9][A-Za-z0-9._\/:@-]{0,254}$/;
const KV = /^[A-Za-z_][A-Za-z0-9_]{0,63}=[^\n]{0,500}$/;
const RO = { readOnlyHint: true, openWorldHint: false };

export const server = new McpServer({ name: "infracortex", version: "3.1.0" });

// On-screen HUD: report each tool call (MCP clients such as Copilot don't run Claude Code hooks).
// Shows tool-level activity only — the client's own reads/edits are not visible to this server.
const CLIENT = process.env.DEVOPS_CLIENT || "MCP client";
const TOOL_AGENT = { tf_scan: "terraform-engineer", k8s_triage: "k8s-troubleshooter", docker_audit: "docker-engineer",
  docker_verify: "docker-engineer", finops_scan: "finops-analyst", az_price: "finops-analyst" };
function hudEvent(ev) {
  if ((process.env.DEVOPS_HUD || "on").toLowerCase() === "off") return;
  try {
    const c = execFile(PYTHON, [path.join(SCRIPTS, "agent_events.py")], { windowsHide: true, timeout: 8000 }, () => {});
    c.stdin.end(JSON.stringify({ hook_event_name: "McpTool", source: CLIENT, cwd: WORKSPACE, session: String(process.pid), ...ev }));
  } catch { /* never break a tool call for the HUD */ }
}
const registerTool = server.registerTool.bind(server);
server.registerTool = (name, def, handler) => registerTool(name, def, async (args, extra) => {
  const agent = TOOL_AGENT[name] || "cortex";
  hudEvent({ agent_type: agent, tool: name, phase: "start" });
  const res = await handler(args, extra);
  hudEvent({ agent_type: agent, tool: name, phase: "end", ok: !res?.isError });
  return res;
});

server.registerTool("tf_scan", {
  title: "Terraform scan",
  description: "Scan a Terraform directory: fmt, validate, tflint, trivy/checkov, python-hcl2 AST checks, Infracost. Returns one line per finding tagged with a rule ID (TF-SEC-003 …). Read-only.",
  inputSchema: { dir: z.string().default(".").describe("Terraform dir, relative to the workspace"),
                 init: z.boolean().default(false).describe("Run terraform init -backend=false first (downloads providers)") },
  annotations: RO,
}, safe(async ({ dir, init }) => bash("tf-scan.sh", [inWorkspace(dir), ...(init ? [] : ["--no-init"])])));

server.registerTool("k8s_triage", {
  title: "Kubernetes triage",
  description: "READ-ONLY Kubernetes triage digest. Give manifests_dir for static manifest review (no cluster), or namespace (+ pod) / all_namespaces for live triage via your kube context.",
  inputSchema: { manifests_dir: z.string().optional(), namespace: z.string().regex(NAME).optional(), pod: z.string().regex(NAME).optional(),
                 all_namespaces: z.boolean().default(false), context: z.string().regex(/^[A-Za-z0-9._@:\/-]{1,200}$/).optional(),
                 tail: z.number().int().min(10).max(500).default(60) },
  annotations: { ...RO, openWorldHint: true },
}, safe(async (a) => {
  if (a.manifests_dir) return bash("k8s-triage.sh", ["--manifests", inWorkspace(a.manifests_dir)]);
  const args = []; if (a.context) args.push("--context", a.context);
  if (a.all_namespaces) args.push("-A"); else args.push("-n", a.namespace || "default");
  if (a.pod) args.push("-p", a.pod); args.push("--tail", String(a.tail));
  return bash("k8s-triage.sh", args);
}));

server.registerTool("docker_audit", {
  title: "Docker audit",
  description: "Security + efficiency audit: Dockerfile (hadolint + heuristics + .dockerignore), image (user, size, layers, fixable HIGH/CRITICAL CVEs, baked secrets), or running container (privileges, caps, mounts). Read-only.",
  inputSchema: { dockerfile: z.string().optional(), image: z.string().regex(IMAGE).optional(), container: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/).optional() },
  annotations: { ...RO, openWorldHint: true },
}, safe(async (a) => {
  const args = [];
  if (a.dockerfile) args.push("-f", inWorkspace(a.dockerfile));
  if (a.image) args.push("-i", a.image);
  if (a.container) args.push("-c", a.container);
  if (!args.length) args.push("-f", inWorkspace("Dockerfile"));
  return bash("docker-audit.sh", args);
}));

server.registerTool("docker_verify", {
  title: "Docker build → run → health diagnose",
  description: "Builds the image, runs a temporary container, waits for HEALTHCHECK and prints DIAG codes + HINTs (HC_CMD_MISSING, HC_PORT_MISMATCH, BIND_LOCALHOST, RO_FS, EXIT_127, BUILD_COPY_MISSING …) then removes the container. Use in a fix loop: diagnose → edit Dockerfile → verify again (max 3), finish with hardened=true. Never fix by going root, removing the healthcheck or adding privileges.",
  inputSchema: { dockerfile: z.string().default("Dockerfile"), context: z.string().optional(), port: z.number().int().min(1).max(65535).optional(),
                 path: z.string().regex(/^\/[A-Za-z0-9._~\/-]{0,200}$/).default("/"), hardened: z.boolean().default(false),
                 env: z.array(z.string().regex(KV)).max(20).default([]), build_args: z.array(z.string().regex(KV)).max(20).default([]),
                 timeout: z.number().int().min(10).max(300).default(60) },
  annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: true },
}, safe(async (a) => {
  const args = ["-f", inWorkspace(a.dockerfile), "--timeout", String(a.timeout), "--path", a.path];
  if (a.context) args.push("-C", inWorkspace(a.context));
  if (a.port) args.push("-p", String(a.port));
  if (a.hardened) args.push("--hardened");
  for (const e of a.env) args.push("-e", e);
  for (const b of a.build_args) args.push("--build-arg", b);
  return bash("docker-verify.sh", args, { timeoutMs: (a.timeout + 600) * 1000 });
}));

server.registerTool("finops_scan", {
  title: "Azure FinOps scan",
  description: "READ-ONLY Azure cost digest using your az login: orphaned/idle resources (Resource Graph), Advisor cost recs, budgets, top resource groups by actual cost. Or tf_dir → Infracost breakdown/diff, or aks_namespace → requests vs usage. Needs Reader + Cost Management Reader.",
  inputSchema: { subscription: z.string().regex(/^[A-Za-z0-9 ._()-]{1,100}$/).optional(), days: z.number().int().min(1).max(365).default(30),
                 tf_dir: z.string().optional(), aks_namespace: z.string().regex(NAME).optional() },
  annotations: { ...RO, openWorldHint: true },
}, safe(async (a) => {
  if (a.tf_dir) return bash("finops-scan.sh", ["--tf", inWorkspace(a.tf_dir)], { timeoutMs: 600000 });
  if (a.aks_namespace) return bash("finops-scan.sh", ["--aks", "-n", a.aks_namespace]);
  const args = ["--days", String(a.days)]; if (a.subscription) args.push("--sub", a.subscription);
  return bash("finops-scan.sh", args, { timeoutMs: 600000 });
}));

server.registerTool("az_price", {
  title: "Azure retail price lookup",
  description: `Azure Retail Prices (public, no login) in ${CURRENCY} by default. mode=preset (private-endpoint | private-dns-zone | storage <SKU> | vm <size> | aks-uptime), mode=query (region/service/product/sku/meter filters), mode=fx (USD→currency rate from Microsoft's price lists). Monthly = hourly × 730 × qty. Retail list prices; no EA discounts.`,
  inputSchema: { mode: z.enum(["preset", "query", "fx"]).default("preset"),
                 preset: z.enum(["private-endpoint", "private-dns-zone", "storage", "vm", "aks-uptime"]).optional(),
                 arg: z.string().regex(/^[A-Za-z0-9 _.-]{1,60}$/).optional().describe("storage SKU like 'Hot LRS' or VM size like D4s_v5"),
                 region: z.string().regex(/^[a-z0-9]{2,40}$/).default("eastus2"), service: z.string().regex(/^[A-Za-z0-9 .-]{1,60}$/).optional(),
                 product: z.string().regex(/^[A-Za-z0-9 .\/-]{1,80}$/).optional(), sku: z.string().regex(/^[A-Za-z0-9 ._-]{1,60}$/).optional(),
                 meter: z.string().regex(/^[A-Za-z0-9 .\/-]{1,80}$/).optional(), qty: z.number().min(0).max(100000).default(1),
                 currency: z.string().regex(/^[A-Za-z]{3}$/).optional(), max: z.number().int().min(1).max(50).default(15) },
  annotations: { ...RO, openWorldHint: true },
}, safe(async (a) => {
  const cur = (a.currency || CURRENCY).toUpperCase();
  if (a.mode === "fx") return bash("az-price.sh", ["fx", cur]);
  if (a.mode === "preset") {
    if (!a.preset) throw new Error("preset required for mode=preset");
    return bash("az-price.sh", ["preset", a.preset, ...(a.arg ? [a.arg] : []), "--region", a.region, "--qty", String(a.qty), "--currency", cur, "--max", String(a.max)]);
  }
  const args = ["query", "--region", a.region, "--currency", cur, "--max", String(a.max)];
  for (const [k, v] of [["--service", a.service], ["--product", a.product], ["--sku", a.sku], ["--meter", a.meter]]) if (v) args.push(k, v);
  return bash("az-price.sh", args);
}));

server.registerTool("azure_diagram", {
  title: "Azure architecture diagram",
  description: "Official-Azure-icon diagrams. action=from_tf drafts a JSON spec from a Terraform dir; action=render turns a spec into an editable .drawio (no deps) or png/svg (needs pip diagrams + Graphviz); action=types lists node types. Writes only inside the workspace.",
  inputSchema: { action: z.enum(["render", "from_tf", "types"]).default("render"), spec: z.string().optional().describe("spec .json path (render)"),
                 tf_dir: z.string().optional(), out: z.string().optional().describe("output path WITHOUT extension"),
                 format: z.enum(["drawio", "png", "svg", "pdf"]).default("drawio") },
  annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
}, safe(async (a) => {
  if (a.action === "types") return py("azdiagram.py", ["types"]);
  if (a.action === "from_tf") return py("azdiagram.py", ["from-tf", inWorkspace(a.tf_dir || ".")]);
  const spec = inWorkspace(a.spec || "docs/arch.json");
  const out = inWorkspace(a.out || spec.replace(/\.json$/i, ""), { mustExist: false });
  if (!existsSync(path.dirname(out)) || !statSync(path.dirname(out)).isDirectory()) throw new Error("output folder does not exist");
  return py("azdiagram.py", ["render", spec, "-o", out, "--format", a.format]);
}));

server.registerTool("validate_report", {
  title: "Validate AgentReport",
  description: "Type-check an AgentReport v1 JSON against the contract (enums, rule-ID domains, caps, invariants such as DONE+files_changed ⇒ verify.passed). Returns OK or the exact errors.",
  inputSchema: { report_json: z.string().min(2).max(200000) },
  annotations: RO,
}, safe(async ({ report_json }) => new Promise((resolve) => {
  const child = execFile(PYTHON, [path.join(SCRIPTS, "validate_report.py"), "-"], { windowsHide: true }, (err, so, se) =>
    resolve({ text: ((so || "") + (se || "")).trim() || "(no output)", code: err ? 1 : 0 }));
  child.stdin.end(report_json);
})));

server.registerTool("check_command", {
  title: "Command safety check",
  description: "Classify a shell command with the toolkit's guard rules: deny (destroy, -auto-approve, namespace delete, az group delete…), ask (apply, kubectl/helm mutations, az create/delete…), or allow. Use before suggesting a command to run.",
  inputSchema: { command: z.string().min(1).max(4000) },
  annotations: RO,
}, safe(async ({ command }) => new Promise((resolve) => {
  const child = execFile(PYTHON, ["-c", "import json,sys; sys.path.insert(0, sys.argv[1]); import guard; v=guard.decide(sys.stdin.read(), use_jev=False); print(json.dumps({'decision': v[0] if v else 'allow', 'reason': v[1] if v else 'no rule matched'}))", SCRIPTS],
    { windowsHide: true }, (err, so, se) => resolve({ text: ((so || "") + (se || "")).trim(), code: err ? 1 : 0 }));
  child.stdin.end(command);
})));

// CortexWeave — the agents' shared skill memory (written by the overseer agent, read by any agent).
const SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
// CortexWeave CLI exits non-zero on any failure (missing skill/version, unapproved skill): surface that as isError.
const strict = (fn) => async (a) => {
  try { const r = await fn(a); return { content: [{ type: "text", text: r.text }], isError: r.code !== 0 }; }
  catch (e) { return { content: [{ type: "text", text: `ERR ${e.message}` }], isError: true }; }
};
const AGENT = z.enum(["terraform-engineer", "k8s-troubleshooter", "docker-engineer", "finops-analyst", "cortex"]);
server.registerTool("search_skills", {
  title: "Search CortexWeave skills",
  description: "Search the skills InfraCortex agents learned from past runs. Returns short descriptions only (cheap). Call at the start of a task with task + tool keywords; pull_skill only if one clearly fits.",
  inputSchema: { query: z.string().min(2).max(200), agent: AGENT.optional(), limit: z.number().int().min(1).max(10).default(5) },
  annotations: RO,
}, strict(async (a) => py("cortexweave.py", ["search", a.query, "--limit", String(a.limit), ...(a.agent ? ["--agent", a.agent] : [])])));

server.registerTool("pull_skill", {
  title: "Read a CortexWeave skill",
  description: "Return the full procedure of one skill (steps, heuristics, failure modes, how to check the result). Use after search_skills.",
  inputSchema: { slug: z.string().regex(SLUG).max(60), version: z.number().int().min(1).optional() },
  annotations: { readOnlyHint: true, openWorldHint: false },
}, strict(async (a) => py("cortexweave.py", ["pull", a.slug, ...(a.version ? ["--version", String(a.version)] : [])])));

server.registerTool("agent_activity", {
  title: "Agent activity (monitor)",
  description: "What the InfraCortex agents did recently: runs, status mix, failed steps, contract rejections, avg tool calls per agent, plus queued runs and skill count.",
  inputSchema: { days: z.number().int().min(1).max(90).default(7) },
  annotations: RO,
}, strict(async (a) => py("cortexweave.py", ["stats", "--days", String(a.days)])));

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  await server.connect(new StdioServerTransport());
  console.error(`infracortex MCP ready · workspace=${WORKSPACE} · bash=${BASH} · currency=${CURRENCY}`);
}
