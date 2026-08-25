// QA harness — verifies the tool-handler output contract without the CLI runtime.
// Replicates the serialization logic in extension.mjs to confirm each tool handler
// produces well-formed, meaningful results for the sample machine.
// Run: node test/qa-handlers.mjs

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  SPEC_REGISTRY,
  autoFillMachine,
  buildSpecJsonSchema,
  buildSpecMarkdown,
  detectSpecVersion,
  getSpec,
  runCompliance,
} from "../engine.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const sample = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "simulator", "samples", "machina-order.json"), "utf-8"),
);

function parseMachine(arg) {
  if (arg == null) throw new Error("Missing required argument \"machine\".");
  if (typeof arg === "object") return arg;
  if (typeof arg === "string") {
    try {
      return JSON.parse(arg);
    } catch (e) {
      throw new Error("machine is not valid JSON: " + e.message);
    }
  }
  throw new Error("machine must be an object or a JSON string.");
}

function cleanFindings(f) {
  return f.map(({ id, category, severity, weight, pass, detail, remediation, autofill }) => ({
    id, category, severity, weight, pass, detail, remediation, autofill,
  }));
}

const failures = [];
function check(name, cond, extra) {
  if (cond) console.log("  ok  " + name);
  else {
    failures.push(name);
    console.log("  FAIL " + name + (extra ? " :: " + extra : ""));
  }
}

console.log("machina_validate handler (machine as JSON string):");
{
  const args = { machine: JSON.stringify(sample) };
  const m = parseMachine(args.machine);
  const det = detectSpecVersion(m);
  const compliance = runCompliance(m, args && args.targetVersion);
  const out = JSON.stringify(
    { score: compliance.score, grade: compliance.grade, specVersion: compliance.specVersion, declared: compliance.declared, assumedLatest: det.assumed, byCategory: compliance.byCategory, blocking: compliance.blocking.map((b) => b.id), findings: cleanFindings(compliance.findings) },
    null,
    2,
  );
  const parsed = JSON.parse(out); // must parse
  check("returns parseable JSON", !!parsed);
  check("has numeric score", typeof parsed.score === "number");
  check("has findings array", Array.isArray(parsed.findings));
  check("has blocking ids array", Array.isArray(parsed.blocking));
  check("blocking empty for sample", parsed.blocking.length === 0);
  check("sample score 89", parsed.score === 89, "got " + parsed.score);
}

console.log("machina_validate handler (machine as object):");
{
  const args = { machine: sample };
  const m = parseMachine(args.machine);
  const compliance = runCompliance(m, args && args.targetVersion);
  const out = JSON.parse(JSON.stringify({ score: compliance.score, grade: compliance.grade, findings: cleanFindings(compliance.findings) }));
  check("object input works", out.score === 89);
}

console.log("machina_validate invalid JSON error handling:");
{
  let threw = false;
  try {
    parseMachine("{ not valid json ");
  } catch (e) {
    threw = /not valid JSON/.test(String(e.message));
  }
  check("throws descriptive error", threw);
}

console.log("machina_autofill handler:");
{
  const args = { machine: JSON.stringify(sample) };
  const m = parseMachine(args.machine);
  const result = autoFillMachine(m, { targetVersion: args && args.targetVersion });
  const out = JSON.parse(JSON.stringify({ applied: result.applied, scoreBefore: result.scoreBefore, scoreAfter: result.scoreAfter, machine: result.machine }));
  check("applied includes spec-version", out.applied.includes("spec-version"), JSON.stringify(out.applied));
  check("scoreBefore 89", out.scoreBefore === 89);
  check("score improves or holds", out.scoreAfter >= out.scoreBefore, out.scoreBefore + "->" + out.scoreAfter);
  check("patched machine declares spec_version", !!out.machine.spec_version);
  // Input not mutated
  check("input object not mutated", sample.spec_version === undefined);
}

console.log("machina_autofill on a bare minimal machine:");
{
  const bare = { id: "demo", initial: "a", states: { a: { on: { GO: { target: "b" } } }, b: {} } };
  const result = autoFillMachine(bare);
  check("applied many auto gaps", result.applied.length >= 5, JSON.stringify(result.applied));
  check("version stamped 1.0.0", result.machine.version === "1.0.0");
  check("scenarios derived", Array.isArray(result.machine.scenarios) && result.machine.scenarios.length === 1);
  check("coverage block added", !!result.machine.coverage);
  check("implicit final typed", result.machine.states.b.type === "final");
  check("descriptions added", !!result.machine.states.b.description);
}

console.log("machina_spec handler (json-schema):");
{
  const args = { version: "2.0.0", format: "json-schema" };
  const spec = getSpec(args.version);
  const out = args.format === "markdown" ? buildSpecMarkdown(spec) : JSON.stringify(buildSpecJsonSchema(spec), null, 2);
  const parsed = JSON.parse(out);
  check("v2 schema parses", !!parsed);
  check("has properties.states", !!parsed.properties && !!parsed.properties.states);
  check("has $defs", !!parsed.$defs);
}

console.log("machina_spec handler (markdown):");
{
  const args = { format: "markdown" };
  const spec = getSpec(args.version);
  const out = buildSpecMarkdown(spec);
  check("markdown is string", typeof out === "string");
  check("markdown has table", out.includes("| Field | Type | Meaning |"));
  check("latest default is v2", spec.version === "2.0.0");
}

console.log("tool name uniqueness:");
{
  const names = ["machina_validate", "machina_autofill", "machina_spec"];
  check("no duplicate tool names", new Set(names).size === names.length);
  check("names do not collide with canvas verbs", !names.some((n) => n.startsWith("canvas.")));
}

console.log("SPEC_REGISTRY enum exposes both versions:");
{
  const enums = SPEC_REGISTRY.map((s) => s.version);
  check("enum has 2.0.0 and 1.0.0", enums.includes("2.0.0") && enums.includes("1.0.0"), JSON.stringify(enums));
}

if (failures.length) {
  console.error("\nQA FAILURES: " + failures.length);
  process.exit(1);
}
console.log("\nAll handler QA checks passed.");
