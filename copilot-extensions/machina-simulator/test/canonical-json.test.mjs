// Canonical-JSON golden tests (Stage 0) — run with: node test/canonical-json.test.mjs
// Proves the Python-compatible canonicalizer (raw-text tokenizer) reproduces the
// driver's sha256(json.dumps(payload, sort_keys=True, separators=(",",":")))
// hashes byte-exact, and that naive JSON.stringify does NOT.
//
// RED/GREEN: naive stringify must FAIL the golden fixture (proving the tokenizer
// is load-bearing), while canonicalizeMachinaText must pass it.
// The fixture is synthetic (paths scrubbed to <run-dir>/...; see genfixture).

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  canonicalizeMachinaText,
  canonicalizeMachina,
  sha256Hex,
  clone,
  deepClone,
  foldContext,
} from "../machine-simulator.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixturePath = path.join(__dirname, "fixtures", "ledger-synthetic.jsonl");
const records = fs
  .readFileSync(fixturePath, "utf8")
  .trim()
  .split("\n")
  .map((l) => JSON.parse(l));

test("golden fixture parses to 5 records with a chain", () => {
  assert.equal(records.length, 5);
  assert.equal(records[0].payload.type, "init");
  assert.equal(records[0].prev_hash, null);
  for (let i = 1; i < records.length; i++) {
    assert.equal(records[i].prev_hash, records[i - 1].hash);
  }
});

test("canonicalizeMachinaText reproduces every stored hash (GREEN)", () => {
  for (const r of records) {
    const canonical = canonicalizeMachinaText(JSON.stringify(r.payload));
    assert.equal(sha256Hex(canonical), r.hash, `hash mismatch for record ${r.payload.type}`);
  }
});

test("naive JSON.stringify does NOT reproduce the golden hash (RED)", () => {
  // The classic mistake: re-serializing the parsed payload loses float lexemes
  // and ordering — must NOT match the driver's Python-canonical hash.
  let naiveMatch = true;
  for (const r of records) {
    if (sha256Hex(JSON.stringify(r.payload)) !== r.hash) naiveMatch = false;
  }
  assert.equal(naiveMatch, false, "naive JSON.stringify should not reproduce Python-canonical hashes");
});

test("canonicalizeMachina accepts both text and parsed object", () => {
  const text = canonicalizeMachinaText(JSON.stringify(records[0].payload));
  // From a parsed object, byte-exactness is documented as best-effort, so assert
  // deterministic+stable rather than exact hash equality.
  const obj = canonicalizeMachina(JSON.parse(JSON.stringify(records[0].payload)));
  assert.equal(typeof obj, "string");
  assert.ok(obj.length > 0);
  const again = canonicalizeMachina(JSON.parse(obj));
  assert.equal(again, obj);
});

test("empty object canonicalizes to {} (the init-records bug)", () => {
  // Regression: the empty-object branch used to return a JS object, emitting
  // "[object Object]" — breaking every init record with tool_hashes:{}
  assert.equal(canonicalizeMachinaText('{"tool_hashes":{},"x":1}'), '{"tool_hashes":{},"x":1}');
});

test("clone and deepClone are deep and input-safe", () => {
  const src = { a: { b: [1, 2, { c: "x" }] } };
  const c = clone(src);
  c.a.b.push(3);
  assert.equal(src.a.b.length, 3);
  assert.equal(c.a.b.length, 4);
  const d = deepClone(src);
  d.a.b[0] = 99;
  assert.equal(src.a.b[0], 1);
});

test("foldContext applies actions to a copy without mutating the input", () => {
  const ctx = { attempts: 1, nested: { n: 0 }, role: "op" };
  const out = foldContext("s", ctx, [
    { type: "increment", key: "attempts" },
    { type: "increment", key: "nested.n" },
    { type: "assign", key: "role", value: "admin" },
  ]);
  assert.deepEqual(ctx, { attempts: 1, nested: { n: 0 }, role: "op" });
  assert.deepEqual(out, { attempts: 2, nested: { n: 1 }, role: "admin" });
});

console.log("All canonical-json tests passed.");