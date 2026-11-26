// node test/parse.test.js — no vscode needed
const assert = require("assert"), fs = require("fs"), os = require("os"), path = require("path");
const { parseFindings, loadRuleSeverities } = require("../src/parse");
const d = fs.mkdtempSync(path.join(os.tmpdir(), "pa-"));
fs.writeFileSync(path.join(d, "main.tf"), "x\n"); fs.mkdirSync(path.join(d, "k8s")); fs.writeFileSync(path.join(d, "k8s", "a.yaml"), "x\n");
const df = path.join(d, "Dockerfile"); fs.writeFileSync(df, "FROM x\nUSER 1\nHEALTHCHECK CMD [\"curl\"]\nCMD [\"httpd\",\"-p\",\"127.0.0.1:8080\"]\n");
const tf = parseFindings("TF-SEC-003 ./main.tf:18:  public_network_access_enabled = true\nTF-COR-004 main.tf: variable env has no type\nTF-REL-001 (module no ref) ./main.tf:12:module x\nTF-REL-001 no required_providers block found\n## heading\nSKIP x", { baseDir: d });
assert.deepStrictEqual(tf.map(f => [f.id, path.basename(f.file || "-"), f.line]), [["TF-SEC-003","main.tf",17],["TF-COR-004","main.tf",0],["TF-REL-001","main.tf",11],["TF-REL-001","-",0]]);
const k = parseFindings(`K8S-SEC-001 ${d}/k8s/a.yaml:10:  privileged: true\nK8S-REL-001 no resources block: ${d}/k8s/a.yaml`, { baseDir: d });
assert.deepStrictEqual(k.map(f => [f.id, f.line, f.message]), [["K8S-SEC-001", 9, "privileged: true"], ["K8S-REL-001", 0, "no resources block"]]);
const dk = parseFindings("DKR-SEC-003 1:FROM node:latest\nDKR-SEC-008 no .dockerignore in /x\nDIAG HC_CMD_MISSING -1|curl not found\nDIAG BIND_LOCALHOST listen=127.0.0.1:8080", { dockerfile: df });
assert.deepStrictEqual(dk.map(f => [f.id, f.line]), [["DKR-SEC-003", 0], ["DKR-SEC-008", 0], ["DIAG HC_CMD_MISSING", 2], ["DIAG BIND_LOCALHOST", 3]]);
const local = path.join(__dirname, "..", "contracts", "RULES.md");
const sev = loadRuleSeverities(fs.existsSync(local) ? local : path.join(__dirname, "..", "..", "..", "contracts", "RULES.md"));
assert.strictEqual(sev["TF-SEC-001"].sev, "CRITICAL"); assert.strictEqual(sev["FIN-COST-001"].sev, "HIGH"); assert.ok(Object.keys(sev).length >= 80);
console.log(`parse tests OK (${Object.keys(sev).length} rules loaded)`);
