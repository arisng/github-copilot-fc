// Regression: the simulator inline module script must be syntactically valid.
// A single stray apostrophe inside a single-quoted string silently kills the
// whole inline module (SyntaxError at module parse time), so bind() never runs
// and the left-tab nav (Runs/Schema) stops working. This test re-compiles the
// extracted `<script type="module">` body on every run.
// Run: node test/syntax.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

test("inline simulator module script parses cleanly", () => {
  const appHtml = fs.readFileSync(path.join(__dirname, "..", "simulator", "app.html"), "utf8");
  const m = appHtml.match(/<script type="module">\s*([\s\S]*?)\s*<\/script>/);
  assert.ok(m, "inline module script present in app.html");
  const inline = m[1];

  // Strip the bare ESM import (it references /machine-simulator.mjs which the
  // page resolves from the server) and parse the remainder as a module.
  const body = inline.replace(/^\s*import\s*\{[\s\S]*?\}\s*from\s*"[^"]+";\s*/, "");
  assert.doesNotThrow(
      () => new vm.Script(body),
    "inline module must not contain a syntax error (a parse failure breaks all bind() listeners)",
  );
});