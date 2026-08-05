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
    return null;
}

// --- Synthetic file-list fixture (deterministic sidebar scroll/collapse QA) ---
function fixtureFiles(sessionUuid) {
    if (sessionUuid !== "fixture-files") return null;
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

// --- Markdown rendering ---
function renderMarkdown(md) {
    const lines = md.split("\n");
    const parts = [];
    const toc = [];
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

    for (let i = 0; i < lines.length; i++) {
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
function scanMarkdownFiles(sessionUuid) {
    const dir = path.join(SESSION_BASE, sessionUuid);
    const files = [];
    if (!fs.existsSync(dir)) return files;
    const walk = (currentDir, relPrefix) => {
        let entries;
        try { entries = fs.readdirSync(currentDir, { withFileTypes: true }); } catch { return; }
        for (const e of entries) {
            const full = path.join(currentDir, e.name);
            const rel = relPrefix ? path.join(relPrefix, e.name) : e.name;
            if (e.isDirectory()) walk(full, rel);
            else if (e.isFile() && /\.md$/i.test(e.name)) files.push({ fullPath: full, relativePath: rel, fileName: e.name, group: relPrefix || "root" });
        }
    };
    walk(dir, null);
    return files;
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
            const files = fixture || scanMarkdownFiles(sessionUuid);
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ files }));
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

    // API: get file content
    if (url.pathname === "/api/file") {
        const sessionUuid = url.searchParams.get("sessionUuid");
        const filePath = url.searchParams.get("path");
        if (!sessionUuid || !filePath) { res.writeHead(400); res.end(JSON.stringify({ error: "Missing sessionUuid or path" })); return; }
        try {
            if (sessionUuid === "fixture-files") {
                const raw = "# " + filePath + "\n\nSample content for " + filePath + ".\n";
                const { html, toc } = renderMarkdown(raw);
                res.writeHead(200, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ html, toc, raw, filePath }));
                return;
            }
            const fullPath = path.join(SESSION_BASE, sessionUuid, filePath);
            const resolved = path.resolve(fullPath);
            const base = path.resolve(path.join(SESSION_BASE, sessionUuid));
            if (!resolved.startsWith(base)) throw new Error("Invalid path");
            const raw = readFile(resolved);
            const { html, toc } = renderMarkdown(raw);
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ html, toc, raw, filePath }));
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
