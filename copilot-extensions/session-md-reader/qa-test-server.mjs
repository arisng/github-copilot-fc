#!/usr/bin/env node
/**
 * QA Test Server — starts the Session MD Reader HTTP server for browser testing.
 *
 * Mocks the `@github/copilot-sdk/extension` module so the extension's HTTP server
 * can be started independently without the full Copilot CLI runtime.
 *
 * Usage:
 *   node qa-test-server.mjs
 *
 * The server prints its listening port to stdout:
 *   QA_SERVER_PORT=3456
 *
 * Then run the QA tests in another terminal:
 *   EXTENSION_PORT=3456 node qa-session-md-reader.mjs
 */

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import initSqlJs from "./node_modules/sql.js/dist/sql-wasm.js";

// --- Configuration ---
const homeDir = process.env.USERPROFILE || "C:\\Users\\ADMIN";
const SESSION_BASE = path.join(homeDir, ".copilot", "session-state");

// --- SQL.js cache ---
let _SQL = null;
async function getSQL() {
    if (!_SQL) _SQL = await initSqlJs();
    return _SQL;
}

// --- Detect sqlite3 CLI fallback ---
function findSqlite3() {
    try {
        const result = execSync("where sqlite3", { encoding: "utf-8", stdio: ["ignore", "pipe", "pipe"] });
        const lines = result.trim().split("\n").filter(l => l.trim());
        for (const line of lines) {
            const p = line.trim();
            if (p && !p.includes("Android")) return p;
        }
        return lines[0] || null;
    } catch { return null; }
}
const SQLITE3_CLI = findSqlite3();

// --- Utilities (duplicated from extension.mjs for standalone testing) ---
function escapeHtml(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function slugify(text) {
    return text.toLowerCase().replace(/[^\w\s-]/g, "").replace(/\s+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "") || "heading";
}

function readFile(filePath) {
    if (!fs.existsSync(filePath)) throw new Error("File not found");
    return fs.readFileSync(filePath, "utf-8");
}

// --- YAML Parser ---
function parseYaml(text) {
    const obj = {};
    let currentKey = null, inMultiline = false, multilinePrefix = "";
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (inMultiline) {
            if (line.startsWith(multilinePrefix) && line.trim()) {
                obj[currentKey] += "\n" + line.slice(multilinePrefix.length);
            } else {
                inMultiline = false;
            }
            continue;
        }
        const match = line.match(/^(\w[\w_-]*):\s*(.*)/);
        if (match) {
            currentKey = match[1];
            let currentValue = match[2];
            if (currentValue.trim() === "|-") {
                obj[currentKey] = "";
                inMultiline = true;
                multilinePrefix = "  ";
            } else {
                obj[currentKey] = currentValue.trim();
            }
        }
    }
    return obj;
}

// --- Read session info ---
function readSessionInfo(sessionUuid) {
    const yamlPath = path.join(SESSION_BASE, sessionUuid, "workspace.yaml");
    if (!fs.existsSync(yamlPath)) return null;
    try {
        const raw = readFile(yamlPath);
        const data = parseYaml(raw);
        const nameLines = (data.name || "").split("\n").filter(l => l.trim());
        const name = nameLines.length ? nameLines[0].trim() : null;
        return { name, repository: data.repository || null, branch: data.branch || null };
    } catch { return null; }
}

// --- Session DB query ---
async function querySessionDb(sessionUuid, sql) {
    const dbPath = path.join(SESSION_BASE, sessionUuid, "session.db");
    if (!fs.existsSync(dbPath)) return null;
    try {
        const SQL = await getSQL();
        const buf = fs.readFileSync(dbPath);
        const db = new SQL.Database(new Uint8Array(buf));
        const results = db.exec(sql);
        db.close();
        return results;
    } catch (e) {
        console.error("sql.js error:", e.message);
        if (SQLITE3_CLI) {
            try {
                const escapedSql = sql.replace(/"/g, '\\"');
                const out = execSync(`"${SQLITE3_CLI}" -json "${dbPath}" "${escapedSql}"`, { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] });
                return JSON.parse(out);
            } catch (e2) {
                console.error("sqlite3 CLI fallback error:", e2.message);
                return null;
            }
        }
        return null;
    }
}

// --- Fetch todos ---
async function readTodos(sessionUuid) {
    const todosRaw = await querySessionDb(sessionUuid, "SELECT id, title, description, status, created_at, updated_at FROM todos");
    if (!todosRaw || !todosRaw.length) return { todos: [], tree: [] };

    let todos = [];
    if (Array.isArray(todosRaw) && todosRaw[0]?.columns) {
        const cols = todosRaw[0].columns;
        const vals = todosRaw[0].values;
        todos = vals.map(row => { const obj = {}; cols.forEach((c, i) => { obj[c] = row[i]; }); return obj; });
    } else if (Array.isArray(todosRaw)) {
        todos = todosRaw;
    }

    const depsRaw = await querySessionDb(sessionUuid, "SELECT todo_id, depends_on FROM todo_deps");
    let deps = [];
    if (depsRaw && depsRaw.length) {
        if (Array.isArray(depsRaw) && depsRaw[0]?.columns) {
            const cols = depsRaw[0].columns;
            const vals = depsRaw[0].values;
            deps = vals.map(row => { const obj = {}; cols.forEach((c, i) => { obj[c] = row[i]; }); return obj; });
        } else if (Array.isArray(depsRaw)) {
            deps = depsRaw;
        }
    }

    const todoMap = {};
    for (const t of todos) todoMap[t.id] = { ...t, children: [], hasParents: false };
    for (const d of deps) {
        if (todoMap[d.todo_id] && todoMap[d.depends_on]) {
            todoMap[d.depends_on].children.push(d.todo_id);
            todoMap[d.todo_id].hasParents = true;
        }
    }

    const roots = todos.filter(t => !todoMap[t.id]?.hasParents).map(t => t.id);

    function buildTree(nodeId, visited = new Set()) {
        if (visited.has(nodeId)) return { id: nodeId, title: todoMap[nodeId]?.title || nodeId, status: todoMap[nodeId]?.status || "pending", children: [{ id: "CYCLE", title: "⚠ cycle detected", status: "blocked", children: [] }] };
        const node = todoMap[nodeId];
        if (!node) return null;
        visited.add(nodeId);
        const treeNode = { id: nodeId, title: node.title, status: node.status, children: [] };
        for (const childId of node.children) {
            const child = buildTree(childId, new Set(visited));
            if (child) treeNode.children.push(child);
        }
        return treeNode;
    }

    const tree = roots.map(id => buildTree(id)).filter(Boolean);
    return { todos, deps, tree };
}

// --- Build a dependency tree from todos + deps (shared by readTodos & fixtures) ---
function buildTodoTree(todos, deps) {
    const todoMap = {};
    for (const t of todos) todoMap[t.id] = { ...t, children: [], hasParents: false };
    for (const d of deps) {
        if (todoMap[d.todo_id] && todoMap[d.depends_on]) {
            todoMap[d.depends_on].children.push(d.todo_id);
            todoMap[d.todo_id].hasParents = true;
        }
    }
    const roots = todos.filter(t => !todoMap[t.id]?.hasParents).map(t => t.id);
    function buildTree(nodeId, visited = new Set()) {
        if (visited.has(nodeId)) return { id: nodeId, title: todoMap[nodeId]?.title || nodeId, status: todoMap[nodeId]?.status || "pending", children: [{ id: "CYCLE", title: "⚠ cycle detected", status: "blocked", children: [] }] };
        const node = todoMap[nodeId];
        if (!node) return null;
        visited.add(nodeId);
        const treeNode = { id: nodeId, title: node.title, status: node.status, children: [] };
        for (const childId of node.children) {
            const child = buildTree(childId, new Set(visited));
            if (child) treeNode.children.push(child);
        }
        return treeNode;
    }
    const tree = roots.map(id => buildTree(id)).filter(Boolean);
    return { todos, deps, tree };
}

// --- Synthetic fixtures for deterministic QA (independent of any real session) ---
function fixtureTodos(sessionUuid) {
    if (sessionUuid === "fixture-deep") {
        // Chain: root -> a -> b -> c -> d -> e (depth 5 below root).
        const ids = ["root", "a", "b", "c", "d", "e"];
        const todos = ids.map((id, i) => ({
            id,
            title: "Todo " + id,
            description: "desc " + id,
            status: i === 0 ? "done" : i === 1 ? "in_progress" : "pending",
            created_at: "2026-01-01T00:00:00.000Z",
            updated_at: "2026-01-01T00:00:00.000Z",
        }));
        const deps = [];
        for (let i = 1; i < ids.length; i++) deps.push({ todo_id: ids[i], depends_on: ids[i - 1] });
        return buildTodoTree(todos, deps);
    }
    if (sessionUuid === "fixture-progress") {
        // 5 todos, 3 done → 60%.
        const mk = (id, title, status) => ({
            id, title, description: "desc " + id, status,
            created_at: "2026-01-01T00:00:00.000Z",
            updated_at: "2026-01-01T00:00:00.000Z",
        });
        const todos = [
            mk("alpha-1", "Alpha one", "done"),
            mk("alpha-2", "Alpha two", "done"),
            mk("alpha-3", "Alpha three", "done"),
            mk("alpha-4", "Alpha four", "in_progress"),
            mk("alpha-5", "Alpha five", "pending"),
        ];
        const deps = [
            { todo_id: "alpha-2", depends_on: "alpha-1" },
            { todo_id: "alpha-3", depends_on: "alpha-2" },
        ];
        return buildTodoTree(todos, deps);
    }
    if (sessionUuid === "fixture-desc") {
        // Single todo with a long multi-line description → description area must scroll.
        const lines = [];
        for (let i = 1; i <= 40; i++) lines.push(`Line ${i}: context text for the description of the todo item to force vertical scrolling inside the fixed-height panel.`);
        const todos = [{
            id: "long-desc-1",
            title: "Todo with long description",
            description: lines.join("\n"),
            status: "in_progress",
            created_at: "2026-01-01T00:00:00.000Z",
            updated_at: "2026-01-02T00:00:00.000Z",
        }];
        return buildTodoTree(todos, []);
    }
    if (sessionUuid === "fixture-manytodos") {
        // ~60 flat todos → todo tree overflows the container so refresh-scroll is testable.
        const todos = [];
        for (let i = 1; i <= 60; i++) {
            todos.push({
                id: "m" + i,
                title: "Many todo item number " + i + " with a reasonably long title for overflow",
                description: "desc " + i,
                status: i % 3 === 0 ? "done" : i % 3 === 1 ? "in_progress" : "pending",
                created_at: "2026-01-01T00:00:00.000Z",
                updated_at: "2026-01-01T00:00:00.000Z",
            });
        }
        return buildTodoTree(todos, []);
    }
    return null;
}

const FIXTURE_LONG_NAME = "This is an extremely long session name that must be rendered in full without any truncation happening to it";
function fixtureSessionInfo(sessionUuid) {
    if (sessionUuid === "fixture-longname") {
        return {
            name: FIXTURE_LONG_NAME,
            repository: "org/repo",
            branch: "develop",
        };
    }
    if (sessionUuid === "fixture-files") {
        return {
            name: "Fixture session with many files and a long name for sidebar scrolling test",
            repository: "org/repo",
            branch: "main",
        };
    }
    if (sessionUuid === "fixture-frontmatter") {
        return {
            name: "Frontmatter fixture session",
            repository: "org/demo",
            branch: "main",
        };
    }
    if (sessionUuid === "fixture-nested") {
        return {
            name: "Nested fixture session",
            repository: "org/demo",
            branch: "main",
        };
    }
    if (sessionUuid === "fixture-allfiles") {
        return {
            name: "All files fixture session",
            repository: "org/demo",
            branch: "main",
        };
    }
    return null;
}

// --- Synthetic file-list fixture (deterministic sidebar scroll/collapse QA) ---
function fixtureFiles(sessionUuid) {
    if (sessionUuid === "fixture-files") {
        const files = [];
        files.push({ fullPath: "", relativePath: "plan.md", fileName: "plan.md", group: "root" });
        for (let i = 1; i <= 18; i++) {
            const name = `checkpoint-${String(i).padStart(3, "0")}.md`;
            files.push({ fullPath: "", relativePath: `checkpoints/${name}`, fileName: name, group: "checkpoints" });
        }
        for (let i = 1; i <= 6; i++) {
            const name = `research-topic-${i}.md`;
            files.push({ fullPath: "", relativePath: `research/${name}`, fileName: name, group: "research" });
        }
        return files;
    }
    if (sessionUuid === "fixture-frontmatter") {
        const files = [];
        files.push({ fullPath: "", relativePath: "plan.md", fileName: "plan.md", group: "root" });
        files.push({ fullPath: "", relativePath: "checkpoints/plain.md", fileName: "plain.md", group: "checkpoints" });
        return files;
    }
    if (sessionUuid === "fixture-nested") {
        const files = [];
        files.push({ fullPath: "", relativePath: "plan.md", fileName: "plan.md", group: "root" });
        files.push({ fullPath: "", relativePath: "checkpoints/index.md", fileName: "index.md", group: "checkpoints" });
        files.push({ fullPath: "", relativePath: "files/next-steps-plan.md", fileName: "next-steps-plan.md", group: "files" });
        files.push({ fullPath: "", relativePath: "files/pass-1/pass.md", fileName: "pass.md", group: "files\\pass-1" });
        files.push({ fullPath: "", relativePath: "files/pass-1/manifests/plan-rev5.md", fileName: "plan-rev5.md", group: "files\\pass-1\\manifests" });
        files.push({ fullPath: "", relativePath: "files/pass-1/qa/manual-test-scenarios.md", fileName: "manual-test-scenarios.md", group: "files\\pass-1\\qa" });
        files.push({ fullPath: "", relativePath: "files/pass-2/pass.md", fileName: "pass.md", group: "files\\pass-2" });
        files.push({ fullPath: "", relativePath: "files/pass-2/research/research-1.md", fileName: "research-1.md", group: "files\\pass-2\\research" });
        files.push({ fullPath: "", relativePath: "files/pass-2/receipts/review.md", fileName: "review.md", group: "files\\pass-2\\receipts" });
        files.push({ fullPath: "", relativePath: "files/pass-3/pass.md", fileName: "pass.md", group: "files\\pass-3" });
        return files;
    }
    if (sessionUuid === "fixture-allfiles") {
        // Mix of markdown + non-markdown files; includes session-internal files
        // that scanSessionFiles must filter out (events.jsonl, session.db, etc).
        const files = [];
        files.push({ fullPath: "", relativePath: "plan.md", fileName: "plan.md", group: "root", size: 120 });
        files.push({ fullPath: "", relativePath: "workspace.yaml", fileName: "workspace.yaml", group: "root", size: 84 });
        files.push({ fullPath: "", relativePath: "checkpoints/index.md", fileName: "index.md", group: "checkpoints", size: 90 });
        files.push({ fullPath: "", relativePath: "files/evidence/screenshot.png", fileName: "screenshot.png", group: "files\\evidence", size: 300 });
        files.push({ fullPath: "", relativePath: "files/evidence/data.json", fileName: "data.json", group: "files\\evidence", size: 60 });
        files.push({ fullPath: "", relativePath: "files/scripts/query.sql", fileName: "query.sql", group: "files\\scripts", size: 55 });
        files.push({ fullPath: "", relativePath: "files/artifacts/app.dll", fileName: "app.dll", group: "files\\artifacts", size: 4200 });
        // Session-internal files that the scanner must exclude:
        files.push({ fullPath: "", relativePath: "events.jsonl", fileName: "events.jsonl", group: "root", size: 500 });
        files.push({ fullPath: "", relativePath: "session.db", fileName: "session.db", group: "root", size: 400 });
        files.push({ fullPath: "", relativePath: "vscode.metadata.json", fileName: "vscode.metadata.json", group: "root", size: 80 });
        files.push({ fullPath: "", relativePath: "inuse.12345.lock", fileName: "inuse.12345.lock", group: "root", size: 6 });
        files.push({ fullPath: "", relativePath: "rewind-file-snapshots/backups/abc123", fileName: "abc123", group: "rewind-file-snapshots\\backups", size: 200 });
        return files;
    }
    return null;
}

// Deterministic fixture content for fixture-allfiles (typed preview QA)
function fixtureAllFilesContent(sessionUuid, filePath) {
    if (sessionUuid !== "fixture-allfiles") return null;
    const norm = filePath.replace(/\\/g, "/");
    if (norm === "plan.md") return "---\ncurrentPass: \"1\"\n---\n\n# All Files Plan\n\nMarkdown body.\n";
    if (norm === "workspace.yaml") return "workspace:\n  path: C:/demo\n  branch: main\n";
    if (norm === "checkpoints/index.md") return "# Checkpoint Index\n\nList.\n";
    if (norm === "files/evidence/screenshot.png") return "PNG";
    if (norm === "files/evidence/data.json") return '{\n  "name": "evidence",\n  "count": 3\n}\n';
    if (norm === "files/scripts/query.sql") return "SELECT * FROM evidence;\n";
    if (norm === "files/artifacts/app.dll") return "BINARY";
    return null;
}

function fixtureNestedMarkdown(sessionUuid, filePath) {
    if (sessionUuid !== "fixture-nested") return null;
    if (filePath === "plan.md" || filePath.endsWith("/plan.md") || filePath.endsWith("\\plan.md")) {
        return `---
track: sdlc-product
currentPass: "2"
passes:
  - number: 1
    planningStatus: ready
    implementationStatus: completed
    completedAt: null
  - number: 2
    planningStatus: ready
    implementationStatus: pending
    completedAt: null
  - number: 3
    planningStatus: ready
    implementationStatus: pending
    completedAt: null
---

# Nested Fixture Plan

Body after frontmatter.
`;
    }
    if (/pass-1/.test(filePath)) return "# Pass 1 content\n\nDetail for pass-1.\n";
    if (/pass-2/.test(filePath)) return "# Pass 2 content\n\nDetail for pass-2.\n";
    if (/pass-3/.test(filePath)) return "# Pass 3 content\n\nDetail for pass-3.\n";
    if (/research-1/.test(filePath)) return "# Research 1\n\nResearch note.\n";
    if (/next-steps/.test(filePath)) return "# Next Steps\n\nPlan notes.\n";
    if (/index\.md/.test(filePath)) return "# Checkpoint Index\n\nCheckpoint list.\n";
    return "# " + filePath + "\n\nSample content.\n";
}

function fixtureMarkdown(sessionUuid, filePath) {
    if (sessionUuid !== "fixture-frontmatter") return null;
    if (filePath === "plan.md" || filePath.endsWith("/plan.md")) {
        return `---
track: sdlc-product
schemaVersion: 1
registryVersion: "1.0.0"
sessionMode: enforced
worktree:
  path: "C:\\Users\\DuyAnh\\Workplace\\demo"
  branch: "feature/250715-agentblazor-slice0"
  repository: "https://github.com/example/demo.git"
createdAt: "2026-08-06T07:33:49+00:00"
passes:
  - number: 1
    track: sdlc-product
    planningStatus: ready
    implementationStatus: completed
    detailPath: files/pass-1/pass.md
    completedAt: null
  - number: 2
    track: sdlc-product
    planningStatus: ready
    implementationStatus: pending
    detailPath: files/pass-2/pass.md
    completedAt: null
githubIssues:
  - number: 418
    relationship: primary
    primary: true
  - number: 419
    relationship: related
    primary: false
---

# Plan: Demo Session

This is the plan body after frontmatter.

## Section

Some content here.
`;
    }
    if (filePath.endsWith("plain.md")) {
        return `# Plain File

No frontmatter here. Just markdown.

- item one
- item two
`;
    }
    return null;
}

// --- Frontmatter YAML parser (dependency-free, nested) ---
function parseYamlScalar(text) {
    const t = text.trim();
    if (t === "" || t === "null" || t === "~") return null;
    if (t === "true") return true;
    if (t === "false") return false;
    if (t.length >= 2 && ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'")))) {
        return t.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, "\\");
    }
    if (/^-?\d+(\.\d+)?$/.test(t)) return Number(t);
    return t;
}

function splitTopLevel(text) {
    const parts = [];
    let cur = "", inQ = null, depth = 0;
    for (const ch of text) {
        if (inQ) { cur += ch; if (ch === inQ) inQ = null; }
        else if (ch === '"' || ch === "'") { inQ = ch; cur += ch; }
        else if (ch === "{" || ch === "[") { depth++; cur += ch; }
        else if (ch === "}" || ch === "]") { depth--; cur += ch; }
        else if (ch === "," && depth === 0) { parts.push(cur.trim()); cur = ""; }
        else cur += ch;
    }
    if (cur.trim()) parts.push(cur.trim());
    return parts.filter(p => p !== "");
}

function parseInlineArray(text) {
    let s = text.trim();
    if (s.startsWith("[") && s.endsWith("]")) s = s.slice(1, -1);
    return splitTopLevel(s).map(parseYamlScalar);
}

function parseInlineObject(text) {
    let s = text.trim();
    if (s.startsWith("{") && s.endsWith("}")) s = s.slice(1, -1);
    const entries = [];
    for (const p of splitTopLevel(s)) {
        const m = p.match(/^([^:\s][^:]*):(?:\s*(.*))?$/);
        if (m) entries.push([m[1].trim(), { type: "scalar", value: parseYamlScalar((m[2] || "").trim()) }]);
    }
    return { type: "map", entries };
}

function parseYamlBlock(text) {
    const tokens = [];
    for (const line of text.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n")) {
        const trimmed = line.trim();
        if (trimmed === "" || trimmed.startsWith("#")) continue;
        const m = line.match(/^(\s*)(.*)$/);
        tokens.push({ indent: m[1].replace(/\t/g, "  ").length, content: m[2] });
    }
    let pos = 0;
    function peek() { return tokens[pos]; }

    function parseNestedValue(parentIndent) {
        const n = peek();
        if (!n) return { type: "scalar", value: null };
        if (n.content.startsWith("-")) {
            if (n.indent >= parentIndent) return parseSeq(n.indent);
            return { type: "scalar", value: null };
        }
        if (n.indent > parentIndent) return parseNode(n.indent);
        return { type: "scalar", value: null };
    }

    function parseNode(minIndent) {
        const t = peek();
        if (!t) return { type: "scalar", value: null };
        if (t.content.startsWith("-")) return parseSeq(minIndent);
        return parseMap(minIndent);
    }

    function parseScalarValue(rest) {
        const r = rest.trim();
        if (r === "" || r === "null" || r === "~") return parseNestedValue(0);
        if (r.startsWith("[")) return { type: "seq", items: parseInlineArray(r).map(v => ({ type: "scalar", value: v })) };
        if (r.startsWith("{")) return parseInlineObject(r);
        return { type: "scalar", value: parseYamlScalar(r) };
    }

    function parseMap(minIndent) {
        const entries = [];
        while (pos < tokens.length) {
            const t = tokens[pos];
            if (t.indent < minIndent) break;
            if (t.indent > minIndent) { pos++; continue; }
            const m = t.content.match(/^([^:\s][^:]*):(?:\s*(.*))?$/);
            if (!m) { pos++; continue; }
            const key = m[1].trim();
            const rest = (m[2] || "").trim();
            pos++;
            let value;
            if (rest === "" || rest === "null" || rest === "~") {
                value = parseNestedValue(minIndent);
            } else {
                value = parseScalarValue(rest);
            }
            entries.push([key, value]);
        }
        return { type: "map", entries };
    }

    function parseSeq(minIndent) {
        const items = [];
        while (pos < tokens.length) {
            const t = tokens[pos];
            if (t.indent < minIndent) break;
            if (t.indent > minIndent) { pos++; continue; }
            if (!t.content.startsWith("-")) break;
            const rest = t.content.slice(1).trim();
            pos++;
            if (rest === "" || rest === "null" || rest === "~") {
                items.push(parseNestedValue(minIndent));
            } else if (rest.startsWith("{")) {
                items.push(parseInlineObject(rest));
            } else if (rest.startsWith("[")) {
                items.push({ type: "seq", items: parseInlineArray(rest).map(v => ({ type: "scalar", value: v })) });
            } else if (/^[^:\s][^:]*:/.test(rest)) {
                const itemMap = { type: "map", entries: [] };
                const m = rest.match(/^([^:\s][^:]*):(?:\s*(.*))?$/);
                const k = m[1].trim();
                const r = (m[2] || "").trim();
                let v;
                if (r === "" || r === "null" || r === "~") v = parseNestedValue(minIndent);
                else if (r.startsWith("[")) v = { type: "seq", items: parseInlineArray(r).map(x => ({ type: "scalar", value: x })) };
                else if (r.startsWith("{")) v = parseInlineObject(r);
                else v = { type: "scalar", value: parseYamlScalar(r) };
                itemMap.entries.push([k, v]);
                while (pos < tokens.length) {
                    const n = tokens[pos];
                    if (n.indent <= minIndent) break;
                    if (n.content.startsWith("-") && n.indent <= minIndent + 1) break;
                    if (/^[^:\s][^:]*:/.test(n.content)) {
                        const mm = n.content.match(/^([^:\s][^:]*):(?:\s*(.*))?$/);
                        const kk = mm[1].trim();
                        const rr = (mm[2] || "").trim();
                        pos++;
                        let vv;
                        if (rr === "" || rr === "null" || rr === "~") vv = parseNestedValue(n.indent);
                        else if (rr.startsWith("[")) vv = { type: "seq", items: parseInlineArray(rr).map(x => ({ type: "scalar", value: x })) };
                        else if (rr.startsWith("{")) vv = parseInlineObject(rr);
                        else vv = { type: "scalar", value: parseYamlScalar(rr) };
                        itemMap.entries.push([kk, vv]);
                    } else break;
                }
                items.push(itemMap);
            } else {
                items.push({ type: "scalar", value: parseYamlScalar(rest) });
            }
        }
        return { type: "seq", items };
    }

    if (!tokens.length) return { type: "map", entries: [] };
    return tokens[0].content.startsWith("-") ? parseSeq(tokens[0].indent) : parseMap(tokens[0].indent);
}

function formatFmScalar(v) {
    if (v === null || v === undefined) return '<span class="fm-null">null</span>';
    if (typeof v === "boolean") return '<span class="fm-bool">' + v + "</span>";
    if (typeof v === "number") return '<span class="fm-num">' + v + "</span>";
    const s = String(v);
    if (/^https?:\/\//.test(s)) return '<span class="fm-url">' + escapeHtml(s) + "</span>";
    return escapeHtml(s);
}

function renderFmEntry(key, node) {
    if (node.type === "map") {
        let rows = "";
        for (const [k, v] of node.entries) rows += renderFmEntry(k, v);
        return '<details class="fm-group"><summary class="fm-group-summary"><span class="fm-chevron">\u25B8</span>' + escapeHtml(key) + '<span class="fm-count">' + node.entries.length + "</span></summary><div class=\"fm-group-body\">" + rows + "</div></details>\n";
    }
    if (node.type === "seq") {
        let rows = "";
        for (let i = 0; i < node.items.length; i++) rows += renderFmEntry("#" + (i + 1), node.items[i]);
        return '<details class="fm-group"><summary class="fm-group-summary"><span class="fm-chevron">\u25B8</span>' + escapeHtml(key) + '<span class="fm-count">' + node.items.length + "</span></summary><div class=\"fm-group-body\">" + rows + "</div></details>\n";
    }
    return '<div class="fm-row"><span class="fm-key">' + escapeHtml(key) + '</span><span class="fm-value">' + formatFmScalar(node.value) + "</span></div>\n";
}

function renderFrontmatterCard(fmNode) {
    const entries = fmNode.entries || [];
    if (!entries.length) return "";
    let body = "";
    for (const [k, v] of entries) body += renderFmEntry(k, v);
    return '<details class="fm-card"><summary class="fm-summary"><span class="fm-chevron">\u25B8</span><span class="fm-label">Metadata</span><span class="fm-count">' + entries.length + " key" + (entries.length !== 1 ? "s" : "") + '</span></summary><div class="fm-body">' + body + "</div></details>\n";
}

// --- Markdown rendering ---
function renderMarkdown(md) {
    const lines = md.split("\n");
    const parts = [];
    const toc = [];
    let startIndex = 0;

    // Detect leading YAML frontmatter (--- ... --- or +++ ... +++)
    const first = lines[0] ? lines[0].trim() : "";
    if (first === "---" || first === "+++") {
        for (let j = 1; j < lines.length; j++) {
            if (lines[j].trim() === first) {
                const card = renderFrontmatterCard(parseYamlBlock(lines.slice(1, j).join("\n")));
                if (card) {
                    parts.push(card);
                    parts.push("\n");
                    startIndex = j + 1;
                }
                break;
            }
        }
    }

    let inCode = false, codeLang = "", codeBuf = [];
    let inTable = false, tableHeaders = null, tableRows = [], tableSepPassed = false;
    let inList = false, listType = null, listItems = [];
    let inBlockquote = false, bqLines = [];

    function flushBlocks() { if (inTable) flushTable(); if (inList) flushList(); if (inBlockquote) flushBq(); }
    function flushTable() {
        if (!tableHeaders && !tableRows.length) return;
        let h = "<table>\n";
        if (tableHeaders) { h += "<thead>\n<tr>"; for (const c of tableHeaders) h += "<th>" + applyInline(c.trim()) + "</th>"; h += "</tr>\n</thead>\n"; }
        if (tableRows.length) { h += "<tbody>\n"; for (const row of tableRows) { h += "<tr>"; for (const c of row) h += "<td>" + applyInline(c.trim()) + "</td>"; h += "</tr>\n"; } h += "</tbody>\n"; }
        h += "</table>\n"; parts.push(h);
        tableHeaders = null; tableRows = []; inTable = false; tableSepPassed = false;
    }
    function flushList() {
        if (!listItems.length) return;
        const tag = listType === "ol" ? "ol" : "ul";
        parts.push("<" + tag + ">\n");
        for (const item of listItems) parts.push("<li>" + item + "</li>\n");
        parts.push("</" + tag + ">\n");
        listItems = []; inList = false; listType = null;
    }
    function flushBq() {
        if (!bqLines.length) return;
        parts.push("<blockquote>\n");
        for (const l of bqLines) parts.push("<p>" + applyInline(l) + "</p>\n");
        parts.push("</blockquote>\n");
        bqLines = []; inBlockquote = false;
    }
    function applyInline(text) {
        text = escapeHtml(text);
        text = text.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
        text = text.replace(/\*(.+?)\*/g, "<em>$1</em>");
        text = text.replace(/~~(.+?)~~/g, "<del>$1</del>");
        text = text.replace(/`([^`]+)`/g, "<code>$1</code>");
        text = text.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1" style="max-width:100%" loading="lazy">');
        text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
        return text;
    }

    for (let i = startIndex; i < lines.length; i++) {
        const raw = lines[i];
        if (raw.trimStart().startsWith("```")) {
            if (!inCode) { flushBlocks(); inCode = true; codeLang = raw.trim().slice(3).trim() || "plaintext"; codeBuf = []; continue; }
            if (codeLang === "mermaid") { parts.push('<div class="mermaid">' + codeBuf.join("\n") + '</div>\n'); }
            else { parts.push('<pre><code class="language-' + escapeHtml(codeLang) + '">' + escapeHtml(codeBuf.join("\n")) + '</code></pre>\n'); }
            inCode = false;
            continue;
        }
        if (inCode) { codeBuf.push(raw); continue; }
        const trimmed = raw.trim();
        if (trimmed === "") { flushBlocks(); parts.push("\n"); continue; }
        const hMatch = raw.match(/^(#{1,6})\s+(.+)/);
        if (hMatch) {
            flushBlocks();
            const level = hMatch[1].length;
            const textRaw = hMatch[2].trim();
            const textClean = textRaw.replace(/\*{1,2}|~~|`/g, "").trim();
            const id = slugify(textClean);
            toc.push({ level, text: textClean, id });
            parts.push("<h" + level + ' id="' + id + '">' + applyInline(textRaw) + "</h" + level + ">\n");
            continue;
        }
        if (/^\|.+\|$/.test(trimmed)) {
            const cells = trimmed.split("|").slice(1, -1);
            if (cells.length >= 2) {
                if (cells.every(c => /^-+\s*$/.test(c.trim()))) { if (!inTable) continue; tableSepPassed = true; continue; }
                if (!inTable || !tableSepPassed) { flushBlocks(); tableHeaders = cells; tableRows = []; inTable = true; tableSepPassed = false; continue; }
                tableRows.push(cells); continue;
            }
        }
        if (inTable) flushTable();
        if (/^(-{3,}|\*{3,}|_{3,})\s*$/.test(trimmed)) { flushBlocks(); parts.push("<hr>\n"); continue; }
        if (trimmed.startsWith("> ")) { if (!inBlockquote) { flushBlocks(); inBlockquote = true; bqLines = []; } bqLines.push(trimmed.slice(2)); continue; }
        if (inBlockquote) flushBq();
        const ulMatch = trimmed.match(/^[-*+]\s+(.+)/);
        if (ulMatch) {
            if (!inList || listType !== "ul") { flushBlocks(); inList = true; listType = "ul"; listItems = []; }
            const taskMatch = ulMatch[1].match(/^\[([ xX])\]\s+(.+)/);
            if (taskMatch) { const checked = taskMatch[1].toLowerCase() === "x" ? ' checked=""' : ""; listItems.push('<input type="checkbox" disabled' + checked + "> " + applyInline(taskMatch[2])); }
            else { listItems.push(applyInline(ulMatch[1])); }
            continue;
        }
        const olMatch = trimmed.match(/^\d+\.\s+(.+)/);
        if (olMatch) { if (!inList || listType !== "ol") { flushBlocks(); inList = true; listType = "ol"; listItems = []; } listItems.push(applyInline(olMatch[1])); continue; }
        if (inList) flushList();
        parts.push("<p>" + applyInline(raw) + "</p>\n");
    }
    flushBlocks();
    if (inCode) parts.push('<pre><code>' + escapeHtml(codeBuf.join("\n")) + '</code></pre>\n');
    return { html: parts.join(""), toc };
}

// --- File scanning ---
// --- Session-internal files/dirs excluded from the Files tab (Copilot plumbing) ---
const SESSION_INTERNAL_DIRS = new Set(["rewind-file-snapshots", ".git", "node_modules", ".copilot"]);
const SESSION_INTERNAL_ROOT_FILES = new Set(["events.jsonl", "session.db", "vscode.metadata.json"]);

// Image and text extension sets (shared with client icon logic)
const IMAGE_EXTS = new Set(["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "ico"]);
const TEXT_EXTS = new Set([
    "md", "markdown", "txt", "log", "json", "jsonl", "sql", "yaml", "yml", "toml", "ini", "cfg", "conf",
    "cs", "js", "jsx", "ts", "tsx", "py", "rb", "go", "java", "c", "cpp", "h", "hpp", "csproj", "props",
    "targets", "editorconfig", "diff", "patch", "xml", "html", "css", "scss", "less", "sh", "ps1", "bat",
    "cmd", "csv", "tsv", "env", "gitignore", "dockerfile", "makefile", "lock",
]);

// --- Scan all session files (markdown + every other extension) ---
function scanSessionFiles(sessionUuid) {
    const dir = path.join(SESSION_BASE, sessionUuid);
    const files = [];
    if (!fs.existsSync(dir)) return files;
    const walk = (currentDir, relPrefix) => {
        let entries;
        try { entries = fs.readdirSync(currentDir, { withFileTypes: true }); } catch { return; }
        for (const e of entries) {
            const full = path.join(currentDir, e.name);
            const rel = relPrefix ? path.join(relPrefix, e.name) : e.name;
            if (e.isDirectory()) {
                if (SESSION_INTERNAL_DIRS.has(e.name)) continue;
                walk(full, rel);
            } else if (e.isFile()) {
                if (relPrefix == null) {
                    if (SESSION_INTERNAL_ROOT_FILES.has(e.name)) continue;
                    if (/\.lock$/i.test(e.name)) continue;
                }
                let size = 0;
                try { size = fs.statSync(full).size; } catch {}
                files.push({ fullPath: full, relativePath: rel, fileName: e.name, group: relPrefix || "root", size });
            }
        }
    };
    walk(dir, null);
    return files;
}

// Classify a file by extension → "markdown" | "text" | "image" | "binary"
function classifyFile(filePath) {
    const name = filePath.split(/[\\/]/).pop() || "";
    const ext = (name.includes(".") ? name.split(".").pop() : name).toLowerCase();
    if (/\.md$/i.test(name)) return "markdown";
    if (IMAGE_EXTS.has(ext)) return "image";
    if (TEXT_EXTS.has(ext)) return "text";
    return "binary";
}

// Sniff a buffer for NUL bytes to distinguish text from binary (unknown extensions)
function fileKindByContent(buffer) {
    return buffer.includes(0) ? "binary" : "text";
}

// True when a relative path is Copilot session-internal (excluded from Files tab)
function isSessionInternalFile(rel) {
    const segs = rel.split(/[\\/]/);
    const root = segs[0] || "";
    if (SESSION_INTERNAL_DIRS.has(root)) return true;
    if (segs.length === 1) {
        if (SESSION_INTERNAL_ROOT_FILES.has(root)) return true;
        if (/\.lock$/i.test(root)) return true;
    }
    return false;
}

const MIME_BY_EXT = {
    png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif",
    svg: "image/svg+xml", webp: "image/webp", bmp: "image/bmp", ico: "image/x-icon",
    json: "application/json", txt: "text/plain", log: "text/plain", csv: "text/csv",
    md: "text/markdown", yaml: "text/yaml", yml: "text/yaml", xml: "application/xml",
};

// --- Read the current active pass from plan.md frontmatter (files tab auto-open) ---
function readActivePass(sessionUuid) {
    const planPath = path.join(SESSION_BASE, sessionUuid, "plan.md");
    if (!fs.existsSync(planPath)) return null;
    try {
        const raw = readFile(planPath);
        const lines = raw.split(/\r?\n/);
        const first = lines[0] ? lines[0].trim() : "";
        if (first !== "---" && first !== "+++") return null;
        for (let j = 1; j < lines.length; j++) {
            if (lines[j].trim() === first) {
                const node = parseYamlBlock(lines.slice(1, j).join("\n"));
                const find = (k) => {
                    for (const [key, val] of node.entries) {
                        if (key === k && val && val.type === "scalar" && val.value !== null) return String(val.value);
                    }
                    return null;
                };
                return find("currentPass") ?? find("activePass") ?? find("activePlanningPass");
            }
        }
        return null;
    } catch {
        return null;
    }
}

function fixtureActivePass(sessionUuid) {
    if (sessionUuid === "fixture-nested") return "2";
    return null;
}

// --- Create the HTTP server ---
import { serveHtml } from "./qa-html-template.mjs";

const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, "http://127.0.0.1");
    const instanceId = url.searchParams.get("instance") || "qa-test";

    // SSE endpoint (minimal — just responds)
    if (url.pathname === "/events") {
        res.writeHead(200, {
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            Connection: "keep-alive",
        });
        // Send initial keepalive
        res.write(": connected\n\n");
        return;
    }

    // API: list files
    if (url.pathname === "/api/files") {
        const sessionUuid = url.searchParams.get("sessionUuid");
        if (!sessionUuid) { res.writeHead(400); res.end(JSON.stringify({ error: "Missing sessionUuid" })); return; }
        try {
            const fixture = fixtureFiles(sessionUuid);
            const scanned = fixture || scanSessionFiles(sessionUuid);
            const files = scanned.filter(f => !isSessionInternalFile(f.relativePath));
            const activePass = fixtureActivePass(sessionUuid) ?? readActivePass(sessionUuid);
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ files, activePass }));
        } catch (e) { res.writeHead(500); res.end(JSON.stringify({ error: e.message })); }
        return;
    }

    // API: get session info
    if (url.pathname === "/api/session") {
        const sessionUuid = url.searchParams.get("sessionUuid");
        if (!sessionUuid) { res.writeHead(400); res.end(JSON.stringify({ error: "Missing sessionUuid" })); return; }
        try {
            let info = readSessionInfo(sessionUuid);
            const fixture = fixtureSessionInfo(sessionUuid);
            if (fixture) info = fixture;
            const shortId = sessionUuid.substring(0, 8) + "…" + sessionUuid.slice(-4);
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ sessionUuid, shortId, ...info }));
        } catch (e) { res.writeHead(500); res.end(JSON.stringify({ error: e.message })); }
        return;
    }

    // API: get file content (typed by extension)
    if (url.pathname === "/api/file") {
        const sessionUuid = url.searchParams.get("sessionUuid");
        const filePath = url.searchParams.get("path");
        if (!sessionUuid || !filePath) { res.writeHead(400); res.end(JSON.stringify({ error: "Missing sessionUuid or path" })); return; }
        try {
            // fixture-allfiles typed content
            const allRaw = fixtureAllFilesContent(sessionUuid, filePath);
            if (allRaw !== null) {
                const kind = classifyFile(filePath);
                const size = fixtureFiles(sessionUuid).find(f => (f.relativePath.replace(/\\/g, "/")) === filePath.replace(/\\/g, "/"))?.size || allRaw.length;
                if (kind === "markdown") {
                    const { html, toc } = renderMarkdown(allRaw);
                    res.writeHead(200, { "Content-Type": "application/json" });
                    res.end(JSON.stringify({ kind, html, toc, raw: allRaw, filePath, size }));
                } else if (kind === "image" || kind === "binary") {
                    res.writeHead(200, { "Content-Type": "application/json" });
                    res.end(JSON.stringify({ kind, filePath, size }));
                } else {
                    res.writeHead(200, { "Content-Type": "application/json" });
                    res.end(JSON.stringify({ kind, raw: allRaw, filePath, size }));
                }
                return;
            }
            if (sessionUuid === "fixture-files") {
                const raw = "# " + filePath + "\n\nSample content for " + filePath + ".\n";
                const { html, toc } = renderMarkdown(raw);
                res.writeHead(200, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ kind: "markdown", html, toc, raw, filePath }));
                return;
            }
            const fixtureRaw = fixtureMarkdown(sessionUuid, filePath);
            if (fixtureRaw !== null) {
                const { html, toc } = renderMarkdown(fixtureRaw);
                res.writeHead(200, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ kind: "markdown", html, toc, raw: fixtureRaw, filePath }));
                return;
            }
            const nestedRaw = fixtureNestedMarkdown(sessionUuid, filePath);
            if (nestedRaw !== null) {
                const { html, toc } = renderMarkdown(nestedRaw);
                res.writeHead(200, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ kind: "markdown", html, toc, raw: nestedRaw, filePath }));
                return;
            }
            const fullPath = path.join(SESSION_BASE, sessionUuid, filePath);
            const resolved = path.resolve(fullPath);
            const base = path.resolve(path.join(SESSION_BASE, sessionUuid));
            if (!resolved.startsWith(base)) throw new Error("Invalid path");
            const size = fs.statSync(resolved).size;
            const kind = classifyFile(filePath);
            if (kind === "markdown") {
                const raw = readFile(resolved);
                const { html, toc } = renderMarkdown(raw);
                res.writeHead(200, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ kind, html, toc, raw, filePath, size }));
            } else if (kind === "text") {
                const raw = readFile(resolved);
                res.writeHead(200, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ kind, raw, filePath, size }));
            } else {
                res.writeHead(200, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ kind, filePath, size }));
            }
        } catch (e) { res.writeHead(500); res.end(JSON.stringify({ error: e.message })); }
        return;
    }

    // API: stream raw file bytes (images / binary) with proper Content-Type
    if (url.pathname === "/api/raw") {
        const sessionUuid = url.searchParams.get("sessionUuid");
        const filePath = url.searchParams.get("path");
        if (!sessionUuid || !filePath) { res.writeHead(400); res.end(JSON.stringify({ error: "Missing sessionUuid or path" })); return; }
        try {
            // fixture-allfiles: return a tiny valid 1x1 PNG for image paths
            if (sessionUuid === "fixture-allfiles") {
                const norm = filePath.replace(/\\/g, "/");
                if (norm === "files/evidence/screenshot.png") {
                    // 1x1 transparent PNG
                    const b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==";
                    const buf = Buffer.from(b64, "base64");
                    res.writeHead(200, { "Content-Type": "image/png", "Content-Length": buf.length });
                    res.end(buf);
                    return;
                }
                res.writeHead(404, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ error: "Not found" }));
                return;
            }
            const fullPath = path.join(SESSION_BASE, sessionUuid, filePath);
            const resolved = path.resolve(fullPath);
            const base = path.resolve(path.join(SESSION_BASE, sessionUuid));
            if (!resolved.startsWith(base)) throw new Error("Invalid path");
            const buf = fs.readFileSync(resolved);
            const ext = (path.extname(filePath) || "").replace(".", "").toLowerCase();
            const mime = MIME_BY_EXT[ext] || "application/octet-stream";
            res.writeHead(200, { "Content-Type": mime, "Content-Length": buf.length });
            res.end(buf);
        } catch (e) { res.writeHead(500); res.end(JSON.stringify({ error: e.message })); }
        return;
    }

    // API: get todos
    if (url.pathname === "/api/todos") {
        const sessionUuid = url.searchParams.get("sessionUuid");
        if (!sessionUuid) { res.writeHead(400); res.end(JSON.stringify({ error: "Missing sessionUuid" })); return; }
        try {
            const fixture = fixtureTodos(sessionUuid);
            const data = fixture || await readTodos(sessionUuid);
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify(data));
        } catch (e) { res.writeHead(500); res.end(JSON.stringify({ error: e.message })); }
        return;
    }

    // Serve HTML UI
    const pageSessionUuid = url.searchParams.get("sessionUuid") || "";
    let maxTodoDepth = 3;
    const qDepth = parseInt(url.searchParams.get("maxTodoDepth"), 10);
    if (!isNaN(qDepth)) maxTodoDepth = Math.max(0, Math.min(10, qDepth));
    res.writeHead(200, { "Content-Type": "text/html", "Cache-Control": "no-store, no-cache, must-revalidate" });
    res.end(serveHtml(instanceId, pageSessionUuid, maxTodoDepth));
});

// Start and print port
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;
// Print port for the test script to pick up
console.log(`QA_SERVER_PORT=${port}`);
console.error(`QA Test Server listening on http://127.0.0.1:${port}`);
