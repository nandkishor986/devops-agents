// Pure parsing helpers (no vscode import) — unit-tested with plain node.
"use strict";
const fs = require("fs");
const path = require("path");

const RULE = /^(TF|K8S|DKR|FIN)-(SEC|REL|COST|MNT|COR|PERF|OPS)-\d{3}$/;

/** Map rule ID → default severity from contracts/RULES.md table rows: | ID | SEV | Rule | */
function loadRuleSeverities(rulesMd) {
  const map = {};
  if (!fs.existsSync(rulesMd)) return map;
  for (const line of fs.readFileSync(rulesMd, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\|\s*((?:TF|K8S|DKR|FIN)-[A-Z]+-\d{3})\s*\|\s*(CRITICAL|HIGH|MEDIUM|LOW|INFO)\s*\|\s*(.*?)\s*\|\s*$/);
    if (m) map[m[1]] = { sev: m[2], title: m[3] };
  }
  return map;
}

/**
 * Turn scanner output into findings {id, file, line (0-based), message}.
 * ctx.baseDir  — dir the scan ran in (relative paths resolve against it)
 * ctx.dockerfile — absolute Dockerfile path for docker-audit / docker-verify output
 */
function parseFindings(output, ctx = {}) {
  const base = ctx.baseDir || process.cwd();
  const out = [];
  const abs = (p) => (path.isAbsolute(p) ? p : path.resolve(base, p.replace(/^\.\//, "")));
  for (const raw of String(output).split(/\r?\n/)) {
    const line = raw.trimEnd();
    let m;
    // docker-verify: DIAG CODE evidence  → Dockerfile (HEALTHCHECK line for HC_*)
    if ((m = line.match(/^DIAG ([A-Z0-9_]+)\s*(.*)$/)) && ctx.dockerfile) {
      out.push({ id: `DIAG ${m[1]}`, file: ctx.dockerfile, line: lineOf(ctx.dockerfile, m[1].startsWith("HC_") ? /^\s*HEALTHCHECK/i : m[1] === "BIND_LOCALHOST" ? /127\.0\.0\.1|localhost/ : /^\s*(CMD|ENTRYPOINT)/i), message: `${m[1]} ${m[2]}`.trim(), sev: "HIGH" });
      continue;
    }
    const parts = line.split(/\s+/);
    if (!RULE.test(parts[0] || "")) continue;
    const id = parts[0];
    const rest = line.slice(id.length).trim();
    // RULE path:line:content   (grep-style; path may be absolute or ./relative)
    if ((m = rest.match(/^(\(.*?\)\s+)?((?:[A-Za-z]:)?[^\s:]+\.[A-Za-z0-9]+):(\d+):\s*(.*)$/))) {
      out.push({ id, file: abs(m[2]), line: Math.max(0, +m[3] - 1), message: `${m[1] || ""}${m[4]}`.trim() });
    // RULE path: message        (AST inspector)
    } else if ((m = rest.match(/^((?:[A-Za-z]:)?[^\s:]+\.(?:tf|tfvars|ya?ml|json|hcl)):\s+(.*)$/))) {
      out.push({ id, file: abs(m[1]), line: 0, message: m[2] });
    // RULE line:content          (docker-audit on one Dockerfile)
    } else if ((m = rest.match(/^(\d+):(.*)$/)) && ctx.dockerfile) {
      out.push({ id, file: ctx.dockerfile, line: Math.max(0, +m[1] - 1), message: m[2].trim() });
    // RULE message: /path        (k8s "no resources block: file")
    } else if ((m = rest.match(/^(.*?):\s+((?:[A-Za-z]:)?[\/\\.][^\s]+)$/)) && fs.existsSync(abs(m[2]))) {
      out.push({ id, file: abs(m[2]), line: 0, message: m[1] });
    // RULE message (no location) → attach to the scanned target if it is a file
    } else {
      out.push({ id, file: ctx.dockerfile || null, line: 0, message: rest });
    }
  }
  return out;
}

function lineOf(file, re) {
  try {
    const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
    const i = lines.findIndex((l) => re.test(l));
    return i < 0 ? 0 : i;
  } catch { return 0; }
}

module.exports = { parseFindings, loadRuleSeverities, RULE };
