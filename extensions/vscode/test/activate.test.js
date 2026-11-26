// Activation smoke test with a stub 'vscode' module: every contributed command must be registered.
const Module = require("module"), assert = require("assert"), path = require("path");
const registered = [];
const stub = {
  window: { createOutputChannel: () => ({ appendLine() {}, show() {}, dispose() {} }), registerTreeDataProvider: () => ({ dispose() {} }),
            showInformationMessage: async () => {}, showErrorMessage: async () => {}, showWarningMessage: async () => {} },
  languages: { createDiagnosticCollection: () => ({ set() {}, clear() {}, dispose() {} }) },
  commands: { registerCommand: (id) => { registered.push(id); return { dispose() {} }; }, executeCommand: async () => {} },
  workspace: { getConfiguration: () => ({ get: (_k, d) => d }), workspaceFolders: [{ uri: { fsPath: process.cwd() } }] },
  TreeItem: class { constructor(l) { this.label = l; } }, ThemeIcon: class { constructor(i) { this.id = i; } },
  ProgressLocation: { Notification: 15 }, Uri: { file: (p) => ({ fsPath: p, toString: () => p }) }, Range: class {}, Diagnostic: class {},
};
const orig = Module._load; Module._load = function (req, ...a) { return req === "vscode" ? stub : orig.call(this, req, ...a); };
const ext = require("../src/extension");
const fs = require("fs"); const extRoot = fs.existsSync(path.resolve(__dirname, "../contracts")) ? path.resolve(__dirname, "..") : path.resolve(__dirname, "../../..");
const subs = []; ext.activate({ extensionPath: extRoot, subscriptions: subs });
const pkg = require("../package.json");
const contributed = pkg.contributes.commands.map(c => c.command).sort();
assert.deepStrictEqual([...registered].sort(), contributed);
for (const m of [...pkg.contributes.menus["explorer/context"], ...pkg.contributes.menus["editor/context"]]) assert.ok(contributed.includes(m.command), m.command);
console.log(`activate OK: ${registered.length} commands registered, ${subs.length} disposables`);
