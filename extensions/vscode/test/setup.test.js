// Unit tests for the one-click layer helpers (no VS Code needed).
const Module = require("module"), assert = require("assert"), fs = require("fs"), os = require("os"), path = require("path");
const orig = Module._load;
Module._load = function (req, ...a) { return req === "vscode" ? { workspace: { getConfiguration: () => ({ get: (_k, d) => d }) } } : orig.call(this, req, ...a); };
const setup = require("../src/setup");

// every required tool has an installer id for each OS family it supports
for (const t of setup.TOOLS) {
  assert.ok(t.win, `${t.id}: no winget id`);
  assert.ok(t.mac, `${t.id}: no brew formula`);
  assert.ok(["required", "recommended", "optional"].includes(t.need), t.id);
}
const req = setup.TOOLS.filter((t) => t.need === "required").map((t) => t.id).sort();
assert.deepStrictEqual(req, ["git", "jq", "python"]);

// installer command: only the missing tools, silent winget flags, python-hcl2 after python
const missing = setup.TOOLS.filter((t) => ["python", "tflint"].includes(t.id));
const cmd = setup.installCommand(missing);
if (process.platform === "win32") {
  assert.match(cmd, /winget install -e --id Python\.Python\.3\.12 --silent --accept-package-agreements --accept-source-agreements/);
  assert.match(cmd, /TerraformLinters\.tflint/);
  assert.match(cmd, /pip install --user python-hcl2/);
  assert.doesNotMatch(cmd, /Docker\.DockerDesktop|Hashicorp\.Terraform/);
} else {
  assert.match(cmd, /tflint/);
}

// bundled agent/skill files get the real install path in place of the placeholder (idempotent)
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "ic-"));
fs.mkdirSync(path.join(tmp, "agents")); fs.mkdirSync(path.join(tmp, "skills", "terraform-playbook"), { recursive: true });
fs.writeFileSync(path.join(tmp, "agents", "a.agent.md"), `read ${setup.PLACEHOLDER}/contracts/RULES.md`);
fs.writeFileSync(path.join(tmp, "skills", "terraform-playbook", "SKILL.md"), `run ${setup.PLACEHOLDER}/scripts/tf-scan.sh`);
fs.writeFileSync(path.join(tmp, "skills", "terraform-playbook", "notes.txt"), setup.PLACEHOLDER);   // non-.md left alone
const outLines = []; global.__out = outLines;
assert.strictEqual(setup.fixBundledPaths(tmp), 2);
const fwd = tmp.replace(/\\/g, "/");
assert.strictEqual(fs.readFileSync(path.join(tmp, "agents", "a.agent.md"), "utf8"), `read ${fwd}/contracts/RULES.md`);
assert.strictEqual(fs.readFileSync(path.join(tmp, "skills", "terraform-playbook", "SKILL.md"), "utf8"), `run ${fwd}/scripts/tf-scan.sh`);
assert.strictEqual(setup.fixBundledPaths(tmp), 0, "second run changes nothing");

// which(): finds an executable on a given PATH and ignores missing ones
const bin = path.join(tmp, "bin"); fs.mkdirSync(bin);
const exe = path.join(bin, process.platform === "win32" ? "fake-tool.exe" : "fake-tool"); fs.writeFileSync(exe, ""); fs.chmodSync(exe, 0o755);
const norm = (p) => (process.platform === "win32" && p ? p.toLowerCase() : p);   // Windows paths are case-insensitive
assert.strictEqual(norm(setup.which("fake-tool", bin)), norm(exe));
assert.strictEqual(setup.which("no-such-tool-xyz", bin), null);

fs.rmSync(tmp, { recursive: true, force: true });
console.log(`setup OK: ${setup.TOOLS.length} tools, installer command, path fix-up, which()`);
