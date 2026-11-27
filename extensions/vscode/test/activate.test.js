// Activation smoke test with a stub 'vscode' module: every contributed command is registered, the MCP provider is
// registered with a definition that runs VS Code's own Node, and nothing slow runs during activation.
const Module = require("module"), assert = require("assert"), path = require("path"), fs = require("fs");
const registered = [], mcp = [];
class EventEmitter { constructor() { this.event = () => ({ dispose() {} }); } fire() {} dispose() {} }
class McpStdioServerDefinition { constructor(label, command, args, env, version) { Object.assign(this, { label, command, args, env, version }); } }
const stub = {
  window: { createOutputChannel: () => ({ appendLine() {}, show() {}, dispose() {} }), registerTreeDataProvider: () => ({ dispose() {} }),
            showInformationMessage: async () => {}, showErrorMessage: async () => {}, showWarningMessage: async () => {},
            createStatusBarItem: () => ({ show() {}, hide() {}, dispose() {} }), createTerminal: () => ({ show() {}, sendText() {} }),
            withProgress: async (_o, fn) => fn() },
  languages: { createDiagnosticCollection: () => ({ set() {}, clear() {}, dispose() {} }) },
  commands: { registerCommand: (id) => { registered.push(id); return { dispose() {} }; }, executeCommand: async () => {} },
  workspace: { getConfiguration: () => ({ get: (_k, d) => d }), workspaceFolders: [{ uri: { fsPath: process.cwd() } }],
               onDidChangeWorkspaceFolders: () => ({ dispose() {} }) },
  extensions: { getExtension: () => undefined },
  lm: { registerMcpServerDefinitionProvider: (id, provider) => { mcp.push({ id, provider }); return { dispose() {} }; } },
  McpStdioServerDefinition, EventEmitter,
  StatusBarAlignment: { Left: 1 }, ThemeColor: class { constructor(c) { this.id = c; } },
  TreeItem: class { constructor(l) { this.label = l; } }, ThemeIcon: class { constructor(i) { this.id = i; } },
  ProgressLocation: { Notification: 15 }, Uri: { file: (p) => ({ fsPath: p, toString: () => p }) }, Range: class {}, Diagnostic: class {},
};
const orig = Module._load; Module._load = function (req, ...a) { return req === "vscode" ? stub : orig.call(this, req, ...a); };
const ext = require("../src/extension");
const extRoot = fs.existsSync(path.resolve(__dirname, "../contracts")) ? path.resolve(__dirname, "..") : path.resolve(__dirname, "../../..");
const state = new Map(); const subs = [];
ext.activate({ extensionPath: extRoot, subscriptions: subs, globalState: { get: (k) => state.get(k), update: async (k, v) => state.set(k, v) },
               extension: { id: "upinclouds.infracortex", packageJSON: require("../package.json") } });
const pkg = require("../package.json");
const contributed = pkg.contributes.commands.map((c) => c.command).sort();
assert.deepStrictEqual([...registered].sort(), contributed);
for (const m of [...pkg.contributes.menus["explorer/context"], ...pkg.contributes.menus["editor/context"]]) assert.ok(contributed.includes(m.command), m.command);
for (const s of pkg.contributes.walkthroughs[0].steps) {
  for (const cmd of (s.description.match(/command:([\w.]+)/g) || []).map((x) => x.slice(8))) assert.ok(contributed.includes(cmd), `walkthrough uses unknown ${cmd}`);
  assert.ok(fs.existsSync(path.resolve(__dirname, "..", s.media.markdown)), `walkthrough media missing: ${s.media.markdown}`);
}
assert.strictEqual(mcp.length, 1, "MCP provider registered once");
assert.strictEqual(mcp[0].id, pkg.contributes.mcpServerDefinitionProviders[0].id);
(async () => {
  const [def] = await mcp[0].provider.provideMcpServerDefinitions();
  assert.strictEqual(def.command, process.execPath, "runs VS Code's own Node");
  assert.strictEqual(def.env.ELECTRON_RUN_AS_NODE, "1");
  assert.strictEqual(def.env.INFRACORTEX_ROOT, extRoot);
  assert.ok(def.args[0].endsWith(path.join("mcp", "server", "index.js")));
  console.log(`activate OK: ${registered.length} commands, MCP provider '${mcp[0].id}', ${subs.length} disposables`);
})().catch((e) => { console.error(e); process.exit(1); });
