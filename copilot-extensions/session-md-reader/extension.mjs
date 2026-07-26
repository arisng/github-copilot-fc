// Extension: session-md-reader
// Browse and render markdown files from a Copilot CLI session directory
// Adds a "Session Markdown Reader" canvas with collapsible TOC

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import { createCanvas, joinSession } from "@github/copilot-sdk/extension";

const homeDir = process.env.USERPROFILE || "C:\\Users\\ADMIN";
const SESSION_BASE = path.join(homeDir, ".copilot", "session-state");

// --- Detect sqlite3 CLI ---
function findSqlite3() {
    try {
        const result = execSync("where sqlite3", { encoding: "utf-8", stdio: ["ignore", "pipe", "pipe"] });
        const lines = result.trim().split("\n").filter(l => l.trim());
        for (const line of lines) {
            const p = line.trim();
            if (p && !p.includes("Android")) { return p; } // prefer non-Android sqlite3
        }
        return lines[0] || null;
    } catch { return null; }
}
const SQLITE3_CLI = findSqlite3();

// --- State Management ---
const instances = new Map();

function getInstance(instanceId) {
    let inst = instances.get(instanceId);
    if (!inst) {
        inst = { state: {}, sseClients: new Set(), cleanup: [] };
        instances.set(instanceId, inst);
    }
    return inst;
}

function broadcast(entry, event, data) {
    for (const res of entry.sseClients) {
        res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    }
}

// --- Markdown Utilities ---
function escapeHtml(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function slugify(text) {
    return text.toLowerCase().replace(/[^\w\s-]/g, "").replace(/\s+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "") || "heading";
}

function renderMarkdown(md) {
    const lines = md.split("\n");
    const parts = [];
    const toc = [];
    let inCode = false, codeLang = "", codeBuf = [];

    // Block state
    let inTable = false, tableHeaders = null, tableRows = [], tableSepPassed = false;
    let inList = false, listType = null, listItems = [];
    let inBlockquote = false, bqLines = [];

    function flushBlocks() {
        if (inTable) { flushTable(); }
        if (inList) { flushList(); }
        if (inBlockquote) { flushBq(); }
    }

    function flushTable() {
        if (!tableHeaders && !tableRows.length) return;
        let h = "<table>\n";
        if (tableHeaders) {
            h += "<thead>\n<tr>";
            for (const c of tableHeaders) h += "<th>" + applyInline(c.trim()) + "</th>";
            h += "</tr>\n</thead>\n";
        }
        if (tableRows.length) {
            h += "<tbody>\n";
            for (const row of tableRows) {
                h += "<tr>";
                for (const c of row) h += "<td>" + applyInline(c.trim()) + "</td>";
                h += "</tr>\n";
            }
            h += "</tbody>\n";
        }
        h += "</table>\n";
        parts.push(h);
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

        // ── Fenced code blocks ──
        if (raw.trimStart().startsWith("```")) {
            if (!inCode) {
                flushBlocks();
                inCode = true;
                codeLang = raw.trim().slice(3).trim() || "plaintext";
                codeBuf = [];
                continue;
            }
            if (codeLang === "mermaid") {
                parts.push('<div class="mermaid">' + codeBuf.join("\n") + '</div>\n');
            } else {
                parts.push('<pre><code class="language-' + escapeHtml(codeLang) + '">' + escapeHtml(codeBuf.join("\n")) + '</code></pre>\n');
            }
            inCode = false;
            continue;
        }
        if (inCode) { codeBuf.push(raw); continue; }

        const trimmed = raw.trim();

        // ── Empty line ──
        if (trimmed === "") { flushBlocks(); parts.push("\n"); continue; }

        // ── Headings ──
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

        // ── Tables ──
        if (/^\|.+\|$/.test(trimmed)) {
            const cells = trimmed.split("|").slice(1, -1);
            if (cells.length >= 2) {
                // Separator row?
                if (cells.every(c => /^-+\s*$/.test(c.trim()))) {
                    if (!inTable) { /* orphan sep → ignore */ continue; }
                    tableSepPassed = true;
                    continue;
                }
                if (!inTable || !tableSepPassed) {
                    flushBlocks();
                    tableHeaders = cells;
                    tableRows = [];
                    inTable = true;
                    tableSepPassed = false;
                    continue;
                }
                tableRows.push(cells);
                continue;
            }
        }
        if (inTable) { flushTable(); }

        // ── Horizontal rule ──
        if (/^(-{3,}|\*{3,}|_{3,})\s*$/.test(trimmed)) { flushBlocks(); parts.push("<hr>\n"); continue; }

        // ── Blockquote ──
        if (trimmed.startsWith("> ")) {
            if (!inBlockquote) { flushBlocks(); inBlockquote = true; bqLines = []; }
            bqLines.push(trimmed.slice(2));
            continue;
        }
        if (inBlockquote) { flushBq(); }

        // ── Unordered list ──
        const ulMatch = trimmed.match(/^[-*+]\s+(.+)/);
        if (ulMatch) {
            if (!inList || listType !== "ul") { flushBlocks(); inList = true; listType = "ul"; listItems = []; }
            const taskMatch = ulMatch[1].match(/^\[([ xX])\]\s+(.+)/);
            if (taskMatch) {
                const checked = taskMatch[1].toLowerCase() === "x" ? ' checked=""' : "";
                listItems.push('<input type="checkbox" disabled' + checked + "> " + applyInline(taskMatch[2]));
            } else {
                listItems.push(applyInline(ulMatch[1]));
            }
            continue;
        }

        // ── Ordered list ──
        const olMatch = trimmed.match(/^\d+\.\s+(.+)/);
        if (olMatch) {
            if (!inList || listType !== "ol") { flushBlocks(); inList = true; listType = "ol"; listItems = []; }
            listItems.push(applyInline(olMatch[1]));
            continue;
        }
        if (inList) { flushList(); }

        // ── Paragraph ──
        parts.push("<p>" + applyInline(raw) + "</p>\n");
    }

    // Close any open blocks
    flushBlocks();
    if (inCode) parts.push('<pre><code>' + escapeHtml(codeBuf.join("\n")) + '</code></pre>\n');

    return { html: parts.join(""), toc };
}

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
            if (e.isDirectory()) {
                // Skip .copilot session internal files like events.jsonl, session.db etc
                // but recurse into checkpoints, research, files
                walk(full, rel);
            } else if (e.isFile() && /\.md$/i.test(e.name)) {
                const group = relPrefix || "root";
                files.push({ fullPath: full, relativePath: rel, fileName: e.name, group });
            }
        }
    };
    walk(dir, null);
    return files;
}

function readFile(filePath) {
    if (!fs.existsSync(filePath)) throw new Error("File not found");
    return fs.readFileSync(filePath, "utf-8");
}

// --- YAML Parser (simple, no deps) ---
function parseYaml(text) {
    const obj = {};
    let currentKey = null, currentValue = null, inMultiline = false, multilinePrefix = "";
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (inMultiline) {
            if (line.startsWith(multilinePrefix)) {
                obj[currentKey] += "\n" + line.slice(multilinePrefix.length);
            } else {
                inMultiline = false;
            }
            continue;
        }
        const match = line.match(/^(\w[\w_-]*):\s*(.*)/);
        if (match) {
            currentKey = match[1];
            currentValue = match[2].trim();
            if (currentValue === "|-") {
                obj[currentKey] = "";
                inMultiline = true;
                multilinePrefix = "  ";
            } else if (currentValue.startsWith("|-")) {
                obj[currentKey] = "";
                inMultiline = true;
                const indent = currentValue.slice(2).length;
                multilinePrefix = " ".repeat(indent + 2) || "  ";
            } else {
                obj[currentKey] = currentValue;
            }
        }
    }
    return obj;
}

// --- Read session info from workspace.yaml ---
function readSessionInfo(sessionUuid) {
    const yamlPath = path.join(SESSION_BASE, sessionUuid, "workspace.yaml");
    if (!fs.existsSync(yamlPath)) return null;
    try {
        const raw = readFile(yamlPath);
        const data = parseYaml(raw);
        const nameLines = (data.name || "").split("\n").filter(l => l.trim());
        const name = nameLines.length ? nameLines[0].trim() : null;
        return {
            name: name || null,
            repository: data.repository || null,
            branch: data.branch || null,
        };
    } catch { return null; }
}

// --- Query session.db via sql.js ---
async function loadSqlJs() {
    const extDir = new URL(".", import.meta.url);
    const sqlJsUrl = new URL("node_modules/sql.js/dist/sql-wasm.js", extDir);
    const initSqlJs = (await import(sqlJsUrl.href)).default;
    return initSqlJs();
}

async function querySessionDb(sessionUuid, sql) {
    const dbPath = path.join(SESSION_BASE, sessionUuid, "session.db");
    if (!fs.existsSync(dbPath)) return null;
    try {
        const SQL = await loadSqlJs();
        const buf = fs.readFileSync(dbPath);
        const db = new SQL.Database(new Uint8Array(buf));
        const results = db.exec(sql);
        db.close();
        return results;
    } catch (e) {
        console.error("sql.js error:", e.message);
        // Fallback: try sqlite3 CLI
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

// --- Fetch todos with dependency tree ---
async function readTodos(sessionUuid) {
    const todosRaw = await querySessionDb(sessionUuid, "SELECT id, title, description, status, created_at, updated_at FROM todos");
    if (!todosRaw || !todosRaw.length) return { todos: [], tree: [] };

    let todos = [];
    if (Array.isArray(todosRaw) && todosRaw[0]?.columns) {
        // sql.js exec format
        const cols = todosRaw[0].columns;
        const vals = todosRaw[0].values;
        todos = vals.map(row => {
            const obj = {};
            cols.forEach((c, i) => { obj[c] = row[i]; });
            return obj;
        });
    } else if (Array.isArray(todosRaw)) {
        // JSON format from sqlite3 CLI
        todos = todosRaw;
    }

    const depsRaw = await querySessionDb(sessionUuid, "SELECT todo_id, depends_on FROM todo_deps");
    let deps = [];
    if (depsRaw && depsRaw.length) {
        if (Array.isArray(depsRaw) && depsRaw[0]?.columns) {
            const cols = depsRaw[0].columns;
            const vals = depsRaw[0].values;
            deps = vals.map(row => {
                const obj = {};
                cols.forEach((c, i) => { obj[c] = row[i]; });
                return obj;
            });
        } else if (Array.isArray(depsRaw)) {
            deps = depsRaw;
        }
    }

    // Build adjacency map for tree
    const todoMap = {};
    for (const t of todos) todoMap[t.id] = { ...t, children: [], hasParents: false };

    for (const d of deps) {
        if (todoMap[d.todo_id] && todoMap[d.depends_on]) {
            todoMap[d.depends_on].children.push(d.todo_id);
            todoMap[d.todo_id].hasParents = true;
        }
    }

    // Find roots (no parents)
    const roots = todos.filter(t => !todoMap[t.id]?.hasParents).map(t => t.id);

    // Build tree structure with cycle detection
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

// --- HTML UI (served as the canvas page) ---
function serveHtml(instanceId, initialSessionUuid) {
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Session Markdown Reader</title>
<style>
  :root {
    --bg: #1a1b22;
    --sidebar-bg: #22232c;
    --surface: #2a2b36;
    --surface-hover: #343546;
    --border: #3a3b48;
    --text: #e4e4e7;
    --text-muted: #88889a;
    --accent: #7c8aff;
    --accent-dim: #5a68cc;
    --success: #4ade80;
    --warning: #fbbf24;
    --code-bg: #16171e;
    --sidebar-width: 300px;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { height: 100%; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif; background: var(--bg); color: var(--text); font-size: 14px; line-height: 1.6; }
  ::-webkit-scrollbar { width: 6px; }
  ::-webkit-scrollbar-track { background: transparent; }
  ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }
  ::-webkit-scrollbar-thumb:hover { background: var(--text-muted); }

  .layout { display: flex; height: 100vh; overflow: hidden; }

  /* Sidebar */
  .sidebar { width: var(--sidebar-width); min-width: var(--sidebar-width); background: var(--sidebar-bg); border-right: 1px solid var(--border); display: flex; flex-direction: column; overflow: hidden; position: relative; }
  .sidebar-header { padding: 14px 16px; border-bottom: 1px solid var(--border); display: flex; align-items: center; gap: 8px; }
  .sidebar-header h2 { font-size: 13px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; color: var(--text-muted); }
  .sidebar-header .session-id { font-size: 11px; color: var(--accent-dim); font-family: monospace; max-width: 180px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .sidebar-tabs { display: flex; border-bottom: 1px solid var(--border); }
  .sidebar-tab { flex: 1; padding: 8px; text-align: center; font-size: 12px; font-weight: 500; cursor: pointer; border: none; background: none; color: var(--text-muted); transition: all 0.2s; }
  .sidebar-tab:hover { color: var(--text); background: var(--surface); }
  .sidebar-tab.active { color: var(--accent); border-bottom: 2px solid var(--accent); background: var(--surface); }
  .sidebar-content { flex: 1; overflow: hidden; display: flex; flex-direction: column; padding: 8px 0; }

  /* File group */
  .file-group { margin-bottom: 4px; }
  .file-group-header { display: flex; align-items: center; gap: 6px; padding: 6px 14px; font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; color: var(--text-muted); cursor: pointer; user-select: none; }
  .file-group-header:hover { color: var(--text); }
  .file-group-header svg { width: 12px; height: 12px; flex-shrink: 0; transition: transform 0.2s; }
  .file-group-header.collapsed svg { transform: rotate(-90deg); }
  .file-item { display: flex; align-items: center; gap: 8px; padding: 5px 14px 5px 28px; cursor: pointer; font-size: 13px; color: var(--text-muted); transition: all 0.15s; border-left: 2px solid transparent; }
  .file-item:hover { color: var(--text); background: var(--surface); }
  .file-item.active { color: var(--accent); background: var(--surface); border-left-color: var(--accent); }
  .file-item .icon { opacity: 0.6; font-size: 14px; width: 16px; text-align: center; }
  .file-item .name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  /* TOC tree */
  .toc-item { display: flex; align-items: center; gap: 4px; padding: 3px 14px; cursor: pointer; font-size: 12px; color: var(--text-muted); transition: all 0.15s; border-left: 2px solid transparent; }
  .toc-item:hover { color: var(--text); background: var(--surface); }
  .toc-item.active { color: var(--accent); border-left-color: var(--accent); background: var(--surface); }
  .toc-empty { padding: 20px 16px; text-align: center; color: var(--text-muted); font-size: 12px; }

  /* Main content */
  .main { flex: 1; overflow-y: auto; padding: 32px 40px; max-width: 100%; }
  .main h1 { font-size: 1.8em; font-weight: 700; margin: 0 0 20px; padding-bottom: 10px; border-bottom: 1px solid var(--border); color: var(--text); }
  .main h2 { font-size: 1.4em; font-weight: 600; margin: 28px 0 12px; color: var(--text); }
  .main h3 { font-size: 1.2em; font-weight: 600; margin: 22px 0 10px; color: var(--text); }
  .main h4 { font-size: 1.05em; font-weight: 600; margin: 18px 0 8px; color: var(--text); }
  .main h5, .main h6 { font-size: 0.95em; font-weight: 600; margin: 14px 0 6px; color: var(--text-muted); }
  .main p { margin: 0 0 12px; }
  .main a { color: var(--accent); text-decoration: none; }
  .main a:hover { text-decoration: underline; }
  .main code { background: var(--code-bg); padding: 2px 6px; border-radius: 3px; font-size: 0.9em; font-family: 'JetBrains Mono', 'Fira Code', monospace; }
  .main pre { background: var(--code-bg); border-radius: 6px; padding: 16px; margin: 12px 0; overflow-x: auto; border: 1px solid var(--border); }
  .main pre code { background: none; padding: 0; border-radius: 0; font-size: 0.85em; line-height: 1.5; }
  .main table { border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 0.9em; }
  .main th, .main td { border: 1px solid var(--border); padding: 8px 12px; text-align: left; }
  .main th { background: var(--surface); font-weight: 600; color: var(--text); }
  .main td { background: var(--bg); }
  .main tr:nth-child(even) td { background: var(--sidebar-bg); }
  .main blockquote { margin: 12px 0; padding: 8px 16px; border-left: 3px solid var(--accent-dim); background: var(--surface); border-radius: 0 4px 4px 0; }
  .main blockquote p { margin: 4px 0; color: var(--text-muted); }
  .main ul, .main ol { margin: 0 0 12px; padding-left: 24px; }
  .main li { margin: 4px 0; }
  .main li input[type="checkbox"] { margin-right: 6px; accent-color: var(--accent); pointer-events: none; }
  .main del { color: var(--text-muted); text-decoration: line-through; }
  .main img { max-width: 100%; border-radius: 4px; margin: 8px 0; }
  .main hr { border: none; border-top: 1px solid var(--border); margin: 24px 0; }
  .main strong { font-weight: 600; color: var(--text); }
  .main em { font-style: italic; }
  .main h1, .main h2, .main h3, .main h4, .main h5, .main h6 { scroll-margin-top: 16px; }

  .loading { display: flex; align-items: center; justify-content: center; height: 100%; flex-direction: column; gap: 16px; color: var(--text-muted); }
  .loading .spinner { width: 32px; height: 32px; border: 3px solid var(--border); border-top-color: var(--accent); border-radius: 50%; animation: spin 0.8s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }

  .no-selection { display: flex; align-items: center; justify-content: center; height: 100%; flex-direction: column; gap: 8px; color: var(--text-muted); font-size: 14px; }
  .no-selection svg { width: 48px; height: 48px; opacity: 0.3; margin-bottom: 8px; }

  /* Welcome */
  .welcome { display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; text-align: center; padding: 40px; }
  .welcome h1 { font-size: 1.6em; margin-bottom: 8px; border: none; color: var(--text); }
  .welcome p { color: var(--text-muted); max-width: 400px; }
  .welcome .files-count { margin-top: 20px; padding: 10px 20px; background: var(--surface); border-radius: 8px; font-size: 13px; color: var(--accent); }

  /* Active file indicator */
  .active-file-info { display: flex; align-items: center; gap: 8px; padding: 8px 16px; background: var(--surface); border-bottom: 1px solid var(--border); font-size: 12px; color: var(--text-muted); min-height: 36px; }
  .active-file-info .sep { color: var(--border); }
  .active-file-info .path { font-family: monospace; font-size: 11px; }
  .active-file-info .hcount { margin-left: auto; white-space: nowrap; }

  /* ── Sidebar collapse ── */
  .sidebar { transition: width 0.25s ease, min-width 0.25s ease; overflow: hidden; }
  .sidebar.collapsed { width: 48px; min-width: 48px; }
  .sidebar.collapsed .sidebar-header { padding: 10px 8px; justify-content: center; }
  .sidebar.collapsed .sidebar-header h2,
  .sidebar.collapsed .sidebar-header .session-id,
  .sidebar.collapsed .sidebar-header div { display: none; }
  .sidebar.collapsed .sidebar-header svg { margin: 0; }
  .sidebar.collapsed .sidebar-tab { font-size: 0; padding: 8px 4px; }
  .sidebar.collapsed .sidebar-tab::after { content: attr(data-icon); font-size: 16px; }
  .sidebar.collapsed .file-group,
  .sidebar.collapsed .toc-item,
  .sidebar.collapsed .active-file-info,
  .sidebar.collapsed .todo-tree-container,
  .sidebar.collapsed .todo-details-panel { display: none; }
  .sidebar.collapsed .sidebar-content { overflow: hidden; }

  /* ── Collapse toggle (floating in main) ── */
  .collapse-toggle {
    position: fixed;
    bottom: 16px;
    left: calc(var(--sidebar-width, 300px) + 16px);
    z-index: 100;
    width: 34px; height: 34px;
    display: flex; align-items: center; justify-content: center;
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 8px; cursor: pointer;
    color: var(--text-muted); transition: left 0.25s ease, background 0.2s;
  }
  .collapse-toggle:hover { background: var(--surface-hover); color: var(--accent); }
  .sidebar.collapsed ~ .main .collapse-toggle { left: 64px; }
  .sidebar.collapsed .collapse-toggle svg { transform: scaleX(-1); }

  /* ── Sidebar resizer ── */
  .sidebar-resizer {
    position: absolute; right: -4px; top: 0; bottom: 0;
    width: 8px; cursor: col-resize; z-index: 50;
    background: transparent; transition: background 0.15s;
  }
  .sidebar-resizer:hover, .sidebar-resizer.active {
    background: var(--accent); opacity: 0.35;
  }
  .sidebar.collapsed .sidebar-resizer { cursor: default; }
  .sidebar.collapsed .sidebar-resizer:hover { background: transparent; opacity: 0; }
  .sidebar-resizing { user-select: none; pointer-events: none; }
  .sidebar-resizing .sidebar-content { pointer-events: none; }

  /* ── Mermaid dark theme ── */
  .main .mermaid {
    background: #1e1f2e; border-radius: 8px; padding: 16px; margin: 12px 0;
    overflow-x: auto; border: 1px solid var(--border);
  }

  /* ── Todo tree styles ── */
  .todo-tree-container {
    padding: 4px 0; flex: 1; overflow-y: auto;
    display: flex; flex-direction: column;
  }
  .todo-tree-container .empty-state {
    padding: 20px 16px; text-align: center; color: var(--text-muted); font-size: 12px;
  }
  .todo-tree-container .empty-state svg { width: 32px; height: 32px; opacity: 0.3; margin-bottom: 8px; }

  /* ── details/summary tree ── */
  .todo-tree-node { --depth: 0; }
  /* Summary acts as the clickable node header */
  summary.todo-node-content {
    position: relative;
    display: flex; align-items: flex-start; gap: 8px;
    padding: 6px 10px; cursor: pointer; border-radius: 4px;
    transition: background 0.15s;
    margin-left: calc(24px + var(--depth, 0) * 20px);
    list-style: none;
  }
  summary.todo-node-content::-webkit-details-marker { display: none; }
  details.todo-tree-node > summary.todo-node-content { list-style: none; }
  summary.todo-node-content:hover { background: var(--surface); }
  summary.todo-node-content.selected { background: var(--surface); outline: 1px solid var(--accent); }

  /* Chevron indicator: rotates 90deg when details is open */
  .chevron {
    font-size: 10px; color: var(--text-muted);
    flex-shrink: 0; margin-top: 4px;
    transition: transform 0.2s;
  }
  details[open] > summary > .chevron { transform: rotate(90deg); }

  /* Details element removes default padding/margin */
  details.todo-tree-node { display: block; }

  /* ── Tree connection lines (depth-based, adapted for details/summary) ── */

  /* Vertical trunk: inside children area */
  .todo-node-children { position: relative; }
  .todo-node-children::before {
    content: ''; position: absolute;
    left: calc(12px + var(--depth, 0) * 20px);
    top: 0; bottom: 0;
    width: 1.5px;
    background: var(--border);
  }
  /* Last child trunk: only top half */
  .todo-tree-node:last-child > .todo-node-children::before {
    height: 50%; bottom: auto;
  }

  /* Horizontal branch: from parent trunk to content start */
  .todo-tree-node > summary.todo-node-content::before {
    content: ''; position: absolute;
    top: 50%;
    left: -32px;
    width: 32px;
    height: 1.5px;
    background: var(--border);
  }

  /* Status dot */
  .todo-status-dot {
    width: 10px; height: 10px; border-radius: 50%;
    flex-shrink: 0; margin-top: 5px;
    background: var(--status-color, #88889a);
  }
  .todo-title {
    flex: 1; word-break: break-word; white-space: normal;
    line-height: 1.4; font-size: 12px; color: var(--text);
    min-width: 0;
  }
  .todo-status-label {
    font-size: 9px; color: var(--status-color, #88889a);
    text-transform: uppercase; letter-spacing: 0.3px;
    white-space: nowrap; margin-top: 3px; flex-shrink: 0;
  }

  /* Details panel - fixed 350px height, always at bottom */
  .todo-details-panel {
    display: none;
    flex-shrink: 0;
    background: var(--sidebar-bg);
    border-top: 1px solid var(--border);
    padding: 12px; height: 350px; max-height: 350px; overflow-y: auto;
    font-size: 11px; line-height: 1.5;
  }
  .todo-details-panel.open { display: block; }
  .todo-details-header {
    display: flex; align-items: center; justify-content: space-between;
    margin-bottom: 8px; padding-bottom: 6px;
    border-bottom: 1px solid var(--border);
  }
  .todo-details-title {
    font-size: 12px; font-weight: 600; color: var(--text);
    word-break: break-word; flex: 1;
  }
  .todo-details-close {
    background: none; border: none; color: var(--text-muted);
    cursor: pointer; font-size: 16px; padding: 2px 6px;
    border-radius: 3px; flex-shrink: 0;
  }
  .todo-details-close:hover { background: var(--surface); color: var(--text); }
  .todo-details-field {
    padding: 3px 0; color: var(--text-muted);
  }
  .todo-details-field .label { color: var(--text-muted); font-weight: 500; }
  .todo-details-field .value { color: var(--text); word-break: break-word; }
  .todo-details-description {
    padding: 6px 8px; margin: 4px 0;
    background: var(--surface); border-radius: 4px;
    font-size: 10px; color: var(--text-muted); line-height: 1.5;
    max-height: 80px; overflow-y: auto;
    word-break: break-word; white-space: pre-wrap;
  }
  .todo-details-dep {
    display: inline-block; padding: 1px 6px; margin: 1px 2px;
    background: var(--surface); border-radius: 4px; color: var(--text-muted);
    font-size: 10px;
  }

  /* ── Shortcuts help ── */
  .shortcuts-hint {
    position: fixed; bottom: 12px; right: 16px;
    font-size: 11px; color: var(--text-muted); opacity: 0.5;
    cursor: default; user-select: none; z-index: 10;
  }
  .shortcuts-hint:hover { opacity: 1; }
  .shortcuts-hint kbd {
    display: inline-block; padding: 1px 4px; font-size: 10px;
    font-family: monospace; background: var(--surface); border-radius: 3px;
    border: 1px solid var(--border); color: var(--text-muted);
  }
</style>
</head>
<body>
<div class="layout">
  <!-- Sidebar -->
  <div class="sidebar" id="sidebar">
    <div class="sidebar-header">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--accent)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/></svg>
      <div>
        <h2 id="sidebarTitle">Session Files</h2>
        <div class="session-id" id="sessionLabel">Loading...</div>
      </div>
    </div>
    <div class="sidebar-tabs">
      <button class="sidebar-tab active" data-tab="files" data-icon="&#x1F4C4;" onclick="switchTab('files')">Files</button>
      <button class="sidebar-tab" data-tab="toc" data-icon="&#x1F4CB;" onclick="switchTab('toc')">TOC</button>
      <button class="sidebar-tab" data-tab="todos" data-icon="&#x1F4CA;" onclick="switchTab('todos')">Todos</button>
    </div>
    <div class="active-file-info" id="activeFileInfo">
      <span class="sep">Select a file to view</span>
    </div>
    <div class="sidebar-content" id="sidebarContent"></div>
    <div class="sidebar-resizer" id="sidebarResizer"></div>
  </div>

  <!-- Main Content -->
  <div class="main" id="mainContent">
    <div class="welcome" id="welcomeView">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--text-muted)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" style="opacity:0.3"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/></svg>
      <h1 id="welcomeTitle">Session Markdown Reader</h1>
      <p id="welcomeDesc">Select a markdown file from the sidebar to browse its content. The TOC tab shows auto-generated headings.</p>
      <div class="files-count" id="fileCountBadge">Scanning files...</div>
      <p style="margin-top:20px;font-size:12px;color:var(--text-muted);opacity:0.7">
        <kbd style="background:var(--surface);padding:1px 5px;border-radius:3px;border:1px solid var(--border)">Ctrl+B</kbd> sidebar &middot;
        <kbd style="background:var(--surface);padding:1px 5px;border-radius:3px;border:1px solid var(--border)">Ctrl+1&ndash;3</kbd> tabs &middot;
        <kbd style="background:var(--surface);padding:1px 5px;border-radius:3px;border:1px solid var(--border)">Ctrl+=/-/0</kbd> zoom
      </p>
    </div>
    <div class="loading" id="loadingView" style="display:none">
      <div class="spinner"></div>
      <span>Loading file...</span>
    </div>
    <div id="renderedContent" style="display:none"></div>
    <button class="collapse-toggle" id="collapseToggle" onclick="toggleSidebar()" title="Toggle sidebar (Ctrl+B)">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>
    </button>
  </div>

  <div class="shortcuts-hint">
    <kbd>Ctrl+B</kbd> <kbd>Ctrl+1&ndash;3</kbd> <kbd>Ctrl+=</kbd>
  </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>

<script>
const INSTANCE = "${instanceId}";
let SESSION_UUID = "${initialSessionUuid}";
let allFiles = [];
let currentFilePath = null;
let currentToc = [];
let activeHeadingId = null;
let sidebarCollapsed = false;
let zoomLevel = 1.0;
let todosData = null;

// --- DOM refs ---
const sidebarEl = document.getElementById("sidebar");
const sidebarContent = document.getElementById("sidebarContent");
const mainContent = document.getElementById("mainContent");
const welcomeView = document.getElementById("welcomeView");
const loadingView = document.getElementById("loadingView");
const renderedContent = document.getElementById("renderedContent");
const sessionLabel = document.getElementById("sessionLabel");
const fileCountBadge = document.getElementById("fileCountBadge");
const activeFileInfo = document.getElementById("activeFileInfo");
const sidebarTitle = document.getElementById("sidebarTitle");
const welcomeTitle = document.getElementById("welcomeTitle");
const welcomeDesc = document.getElementById("welcomeDesc");

// --- SSE ---
const evtSource = new EventSource("/events?instance=" + INSTANCE);
evtSource.addEventListener("refresh", (e) => {
    const data = JSON.parse(e.data);
    if (data.sessionUuid) SESSION_UUID = data.sessionUuid;
    loadFiles();
});

// --- Session Name ---
async function loadSessionInfo() {
    if (!SESSION_UUID) return;
    try {
        const res = await fetch("/api/session?sessionUuid=" + encodeURIComponent(SESSION_UUID));
        if (!res.ok) return;
        const data = await res.json();
        if (data.name) {
            const shortName = data.name.length > 50 ? data.name.substring(0, 47) + "\u2026" : data.name;
            sessionLabel.textContent = shortName;
            sidebarTitle.textContent = shortName;
            document.title = "MD: " + shortName;
            welcomeTitle.textContent = shortName;
        } else if (data.shortId) {
            sessionLabel.textContent = data.shortId;
            sidebarTitle.textContent = data.shortId;
            document.title = "MD: " + data.shortId;
        }
        if (data.repository) {
            const repoShort = data.repository.split("/").pop() || data.repository;
            welcomeDesc.textContent = repoShort + (data.branch ? " (" + data.branch + ")" : "") + " \u2014 select a file to view";
        }
    } catch {}
}

// --- Sidebar Collapse ---
function toggleSidebar() {
    sidebarCollapsed = !sidebarCollapsed;
    sidebarEl.classList.toggle("collapsed", sidebarCollapsed);
    if (!sidebarCollapsed) {
        // Restore last width when expanding
        const lastWidth = parseFloat(localStorage.getItem("md-reader-sidebar-width") || "300");
        document.documentElement.style.setProperty("--sidebar-width", Math.max(200, lastWidth) + "px");
    }
}

// --- Sidebar drag resize ---
let isResizing = false;
function initSidebarResizer() {
    const resizer = document.getElementById("sidebarResizer");
    if (!resizer) return;
    resizer.addEventListener("mousedown", (e) => {
        e.preventDefault();
        // If collapsed, expand first
        if (sidebarEl.classList.contains("collapsed")) {
            sidebarCollapsed = false;
            sidebarEl.classList.remove("collapsed");
            const lastWidth = parseFloat(localStorage.getItem("md-reader-sidebar-width") || "300");
            document.documentElement.style.setProperty("--sidebar-width", Math.max(200, lastWidth) + "px");
        }
        isResizing = true;
        resizer.classList.add("active");
        document.body.classList.add("sidebar-resizing");
    });
    document.addEventListener("mousemove", (e) => {
        if (!isResizing) return;
        const newWidth = Math.max(200, Math.min(600, e.clientX));
        document.documentElement.style.setProperty("--sidebar-width", newWidth + "px");
    });
    document.addEventListener("mouseup", () => {
        if (!isResizing) return;
        isResizing = false;
        const resizer = document.getElementById("sidebarResizer");
        if (resizer) resizer.classList.remove("active");
        document.body.classList.remove("sidebar-resizing");
        // Get current width and persist
        const w = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--sidebar-width")) || 300;
        try { localStorage.setItem("md-reader-sidebar-width", w); } catch {}
    });
}

// --- Tab switching ---
let currentTab = "files";
function switchTab(tab) {
    currentTab = tab;
    document.querySelectorAll(".sidebar-tab").forEach(t => t.classList.toggle("active", t.dataset.tab === tab));
    renderSidebar();
    if (tab === "todos" && !todosData) loadTodos();
}

// --- Zoom ---
function zoomIn() { zoomLevel = Math.min(2.0, zoomLevel + 0.1); applyZoom(); }
function zoomOut() { zoomLevel = Math.max(0.5, zoomLevel - 0.1); applyZoom(); }
function zoomReset() { zoomLevel = 1.0; applyZoom(); }
function applyZoom() {
    document.body.style.zoom = zoomLevel;
    try { localStorage.setItem("md-reader-zoom", zoomLevel); } catch {}
}

// --- Keyboard Shortcuts ---
document.addEventListener("keydown", (e) => {
    const ctrl = e.ctrlKey || e.metaKey;
    if (!ctrl) return;
    switch (e.key) {
        case "b": case "B": e.preventDefault(); toggleSidebar(); break;
        case "1": e.preventDefault(); switchTab("files"); break;
        case "2": e.preventDefault(); switchTab("toc"); break;
        case "3": e.preventDefault(); switchTab("todos"); loadTodos(); break;
        case "=": case "+": e.preventDefault(); zoomIn(); break;
        case "-": case "_": e.preventDefault(); zoomOut(); break;
        case "0": e.preventDefault(); zoomReset(); break;
    }
});

// --- Load file list ---
async function loadFiles() {
    if (!SESSION_UUID) {
        sessionLabel.textContent = "No session UUID";
        fileCountBadge.textContent = "No session selected";
        return;
    }
    sessionLabel.textContent = SESSION_UUID.substring(0, 12) + "\u2026";
    try {
        const res = await fetch("/api/files?sessionUuid=" + encodeURIComponent(SESSION_UUID));
        const data = await res.json();
        allFiles = data.files || [];
        fileCountBadge.textContent = allFiles.length + " markdown file" + (allFiles.length !== 1 ? "s" : "") + " found";
        renderSidebar();
    } catch (e) {
        fileCountBadge.textContent = "Error loading files";
        sidebarContent.innerHTML = '<div style="padding:20px;color:var(--warning);text-align:center">Failed to load files.<br>Check session UUID.</div>';
    }
}

// --- Load Todos ---
async function loadTodos() {
    if (!SESSION_UUID) return;
    if (todosData) { renderTodosTree(); return; }
    try {
        const res = await fetch("/api/todos?sessionUuid=" + encodeURIComponent(SESSION_UUID));
        if (!res.ok) { todosData = { tree: [] }; renderTodosTree(); return; }
        const data = await res.json();
        todosData = data;
        renderTodosTree();
    } catch {
        todosData = { tree: [] };
        renderTodosTree();
    }
}

// --- Render sidebar (files, TOC, or todos) ---
function renderSidebar() {
    if (currentTab === "files") {
        renderFileList();
    } else if (currentTab === "toc") {
        renderTocTree();
    } else if (currentTab === "todos") {
        renderTodosTree();
    }
}

function renderFileList() {
    if (!allFiles.length) {
        sidebarContent.innerHTML = '<div class="toc-empty">No markdown files found</div>';
        return;
    }

    // Group files
    const groups = {};
    for (const f of allFiles) {
        const g = f.group === "root" ? "root" : f.group;
        if (!groups[g]) groups[g] = [];
        groups[g].push(f);
    }

    // Sort: root first, then alphabetically
    const groupOrder = ["root", "checkpoints", "research", "files"];
    const sortedGroups = Object.keys(groups).sort((a, b) => {
        const ai = groupOrder.indexOf(a);
        const bi = groupOrder.indexOf(b);
        return (ai === -1 ? 99 : ai) - (bi === -1 ? 99 : bi) || a.localeCompare(b);
    });

    let html = "";
    for (const group of sortedGroups) {
        const fileList = groups[group];
        const groupLabel = group === "root" ? "Root" : group;
        const isActive = groupCollapsed[group] !== false;
        html += '<div class="file-group">';
        html += '<div class="file-group-header' + (!isActive ? ' collapsed' : '') + '" onclick="toggleGroup(\\'' + group + '\\')">';
        html += '<svg viewBox="0 0 20 20" fill="currentColor"><path d="M6 4l8 6-8 6z"/></svg>';
        html += groupLabel + ' <span style="font-weight:400;margin-left:4px;opacity:0.6">(' + fileList.length + ')</span>';
        html += '</div>';
        for (const f of fileList) {
            const active = currentFilePath === f.relativePath ? ' active' : '';
            const icon = f.group === "checkpoints" ? "\u{1F4CB}" : f.fileName === "plan.md" ? "\u{1F4D1}" : "\u{1F4C4}";
            html += '<div class="file-item' + active + '" onclick="loadFile(\\'' + f.relativePath.replace(/\\\\/g, '\\\\\\\\') + '\\')" data-path="' + f.relativePath + '">';
            html += '<span class="icon">' + icon + '</span>';
            html += '<span class="name">' + f.fileName + '</span>';
            html += '</div>';
        }
        html += '</div>';
    }
    sidebarContent.innerHTML = html;
}

// Simple group collapse state
const groupCollapsed = {};
function toggleGroup(name) {
    groupCollapsed[name] = groupCollapsed[name] === false ? true : false;
    renderFileList();
}

function renderTocTree() {
    if (!currentToc.length) {
        sidebarContent.innerHTML = '<div class="toc-empty">No headings found in current file</div>';
        return;
    }

    let html = '';
    for (const h of currentToc) {
        const indent = (h.level - 1) * 16;
        const isActive = activeHeadingId === h.id ? ' active' : '';
        html += '<div class="toc-item' + isActive + '" style="padding-left:' + (14 + indent) + 'px" onclick="scrollToHeading(\\'' + h.id + '\\')">';
        html += '<span style="font-size:10px;opacity:0.5;min-width:16px">H' + h.level + '</span>';
        html += escapeHtml(h.text);
        html += '</div>';
    }
    sidebarContent.innerHTML = html;
}

// --- Render Todos Tree (SVG) ---
function renderTodosTree() {
    const tree = todosData?.tree || [];
    if (!tree.length) {
        sidebarContent.innerHTML = '<div class="todo-tree-container"><div class="empty-state">'
            + '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>'
            + '<br>No todos found</div></div>';
        return;
    }

    const statusColors = { pending: "#88889a", in_progress: "#7c8aff", done: "#4ade80", blocked: "#f87171" };
    const statusLabels = { pending: "Pending", in_progress: "In Progress", done: "Done", blocked: "Blocked" };

    // Build HTML tree recursively using details/summary
    function buildNodeHtml(node, depth) {
        const color = statusColors[node.status] || statusColors.pending;
        const label = statusLabels[node.status] || node.status;
        const title = escapeHtml(node.title || node.id);
        const children = node.children || [];
        const hasChildren = children.length > 0 && children[0]?.id !== "CYCLE";

        let html = '<details class="todo-tree-node" style="--depth:' + depth + '" data-id="' + escapeHtml(node.id) + '">';
        html += '<summary class="todo-node-content" style="margin-left:' + (24 + depth * 20) + 'px" onclick="onTodoNodeClick(this, \\'' + escapeHtml(node.id) + '\\')">';
        html += '<span class="chevron"' + (hasChildren ? '' : ' style="visibility:hidden"') + '>▶</span>';
        html += '<span class="todo-status-dot" style="--status-color:' + color + '"></span>';
        html += '<span class="todo-title">' + title + '</span>';
        html += '<span class="todo-status-label" style="--status-color:' + color + '">' + label + '</span>';
        html += '</summary>';
        if (hasChildren) {
            html += '<div class="todo-node-children">';
            for (const child of children) {
                html += buildNodeHtml(child, depth + 1);
            }
            html += '</div>';
        }
        html += '</details>';
        return html;
    }

    let html = '<div class="todo-tree-container">';
    for (const root of tree) {
        html += buildNodeHtml(root, 0);
    }
    html += '</div>';

    // Details panel (hidden by default)
    html += '<div class="todo-details-panel" id="todoDetailsPanel">';
    html += '<div class="todo-details-header">';
    html += '<span class="todo-details-title" id="todoDetailTitle"></span>';
    html += '<button class="todo-details-close" onclick="closeTodoDetails()">&times;</button>';
    html += '</div>';
    html += '<div id="todoDetailBody">';
    html += '<div class="todo-details-field"><span class="label">ID: </span><span class="value" id="todoDetailId"></span></div>';
    html += '<div class="todo-details-field"><span class="label">Status: </span><span class="value" id="todoDetailStatus"></span></div>';
    html += '<div class="todo-details-field"><span class="label">Description:</span></div>';
    html += '<div class="todo-details-description" id="todoDetailDesc"></div>';
    html += '<div class="todo-details-field"><span class="label">Created: </span><span class="value" id="todoDetailCreated"></span></div>';
    html += '<div class="todo-details-field"><span class="label">Updated: </span><span class="value" id="todoDetailUpdated"></span></div>';
    html += '<div class="todo-details-field" id="todoDetailDepsContainer" style="display:none"><span class="label">Dependencies: </span><span id="todoDetailDeps"></span></div>';
    html += '</div></div>';

    sidebarContent.innerHTML = html;
}

// --- Todo node click handler ---
function onTodoNodeClick(element, todoId) {
    // Deselect all
    document.querySelectorAll(".todo-node-content").forEach(el => el.classList.remove("selected"));
    element.classList.add("selected");

    // Find todo data
    const todo = todosData?.todos?.find(t => t.id === todoId);
    if (!todo) return;

    // Find dependencies
    const deps = todosData?.deps?.filter(d => d.todo_id === todoId) || [];
    const depNames = deps.map(d => {
        const dep = todosData?.todos?.find(t => t.id === d.depends_on);
        return dep ? dep.title || dep.id : d.depends_on;
    });

    const statusColors = { pending: "#88889a", in_progress: "#7c8aff", done: "#4ade80", blocked: "#f87171" };
    const statusLabels = { pending: "Pending", in_progress: "In Progress", done: "Done", blocked: "Blocked" };
    const color = statusColors[todo.status] || statusColors.pending;
    const label = statusLabels[todo.status] || todo.status;

    // Populate details panel
    document.getElementById("todoDetailTitle").textContent = todo.title || todo.id;
    document.getElementById("todoDetailId").textContent = todo.id;
    document.getElementById("todoDetailStatus").innerHTML = '<span style="color:' + color + '">●</span> ' + label;
    document.getElementById("todoDetailDesc").textContent = todo.description || "(no description)";
    document.getElementById("todoDetailCreated").textContent = todo.created_at || "N/A";
    document.getElementById("todoDetailUpdated").textContent = todo.updated_at || "N/A";

    const depsContainer = document.getElementById("todoDetailDepsContainer");
    const depsEl = document.getElementById("todoDetailDeps");
    if (depNames.length > 0) {
        depsContainer.style.display = "block";
        depsEl.innerHTML = depNames.map(n => '<span class="todo-details-dep">' + escapeHtml(n) + '</span>').join(" ");
    } else {
        depsContainer.style.display = "none";
    }

    document.getElementById("todoDetailsPanel").classList.add("open");
}

function closeTodoDetails() {
    document.querySelectorAll(".todo-node-content").forEach(el => el.classList.remove("selected"));
    document.getElementById("todoDetailsPanel").classList.remove("open");
}

// --- Mermaid init ---
function runMermaid() {
    if (typeof mermaid !== "undefined") {
        mermaid.initialize({
            startOnLoad: false,
            theme: "dark",
            themeVariables: {
                background: "#1e1f2e",
                primaryColor: "#7c8aff",
                primaryTextColor: "#e4e4e7",
                primaryBorderColor: "#5a68cc",
                lineColor: "#3a3b48",
                secondaryColor: "#2a2b36",
                tertiaryColor: "#22232c",
            }
        });
        try { mermaid.run({ nodes: document.querySelectorAll(".mermaid") }); } catch {}
    }
}

// --- Load a file ---
async function loadFile(relativePath) {
    currentFilePath = relativePath;
    welcomeView.style.display = "none";
    renderedContent.style.display = "none";
    loadingView.style.display = "flex";

    try {
        const res = await fetch("/api/file?sessionUuid=" + encodeURIComponent(SESSION_UUID) + "&path=" + encodeURIComponent(relativePath));
        if (!res.ok) throw new Error("Failed to load");
        const data = await res.json();
        currentToc = data.toc || [];
        renderedContent.innerHTML = data.html;
        renderedContent.style.display = "block";
        loadingView.style.display = "none";

        // Update active file info
        activeFileInfo.innerHTML = '<span class="path">' + escapeHtml(relativePath) + '</span><span class="sep">|</span><span class="hcount">' + currentToc.length + ' heading' + (currentToc.length !== 1 ? "s" : "") + '</span>';

        // Run Mermaid on new content
        runMermaid();

        // Re-render sidebar to show active state
        renderSidebar();
        if (currentTab === "toc") renderTocTree();
        mainContent.scrollTop = 0;
    } catch (e) {
        renderedContent.style.display = "none";
        loadingView.style.display = "none";
        welcomeView.style.display = "flex";
        welcomeView.querySelector("p").textContent = "Error loading: " + e.message;
    }
}

// --- Scroll to heading ---
function scrollToHeading(id) {
    const el = document.getElementById(id);
    if (el) {
        el.scrollIntoView({ behavior: "smooth", block: "start" });
        // Highlight active heading in TOC
        activeHeadingId = id;
        if (currentTab === "toc") renderTocTree();
    }
}

// --- Intersection Observer for active heading ---
const headingObserver = new IntersectionObserver((entries) => {
    for (const entry of entries) {
        if (entry.isIntersecting) {
            activeHeadingId = entry.target.id;
            if (currentTab === "toc") renderTocTree();
            break;
        }
    }
}, { root: document.querySelector(".main"), threshold: 0, rootMargin: "-20px 0px -80% 0px" });

function observeHeadings() {
    document.querySelectorAll("#renderedContent h1, #renderedContent h2, #renderedContent h3, #renderedContent h4, #renderedContent h5, #renderedContent h6").forEach(el => headingObserver.observe(el));
}

// Watch for content changes to re-run heading observer
const contentObserver = new MutationObserver(() => {
    // Disconnect old observations
    headingObserver.disconnect();
    observeHeadings();
});
contentObserver.observe(renderedContent, { childList: true, subtree: true });

// --- Utility ---
function escapeHtml(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;");
}

// --- Init ---
// Restore saved sidebar width
try {
    const savedWidth = parseFloat(localStorage.getItem("md-reader-sidebar-width"));
    if (savedWidth >= 200 && savedWidth <= 600) {
        document.documentElement.style.setProperty("--sidebar-width", savedWidth + "px");
    }
} catch {}
// Init sidebar resizer
initSidebarResizer();

// Restore zoom
try {
    const savedZoom = parseFloat(localStorage.getItem("md-reader-zoom"));
    if (savedZoom >= 0.5 && savedZoom <= 2.0) { zoomLevel = savedZoom; applyZoom(); }
} catch {}

if (SESSION_UUID) {
    loadFiles();
    loadSessionInfo();
} else {
    sessionLabel.textContent = "No session UUID";
    fileCountBadge.textContent = "Provide sessionUuid to open";
}
</script>
</body>
</html>`;
}

// --- HTTP Server ---
const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, "http://127.0.0.1");
    const instanceId = url.searchParams.get("instance") || "default";
    const entry = getInstance(instanceId);

    // SSE
    if (url.pathname === "/events") {
        res.writeHead(200, {
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            Connection: "keep-alive",
        });
        entry.sseClients.add(res);
        res.on("close", () => entry.sseClients.delete(res));
        return;
    }

    // API: list markdown files
    if (url.pathname === "/api/files") {
        const sessionUuid = url.searchParams.get("sessionUuid");
        if (!sessionUuid) { res.writeHead(400); res.end(JSON.stringify({ error: "Missing sessionUuid" })); return; }
        try {
            const files = scanMarkdownFiles(sessionUuid);
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ files }));
        } catch (e) {
            res.writeHead(500, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: e.message }));
        }
        return;
    }

    // API: get file content & render
    if (url.pathname === "/api/file") {
        const sessionUuid = url.searchParams.get("sessionUuid");
        const filePath = url.searchParams.get("path");
        if (!sessionUuid || !filePath) { res.writeHead(400); res.end(JSON.stringify({ error: "Missing sessionUuid or path" })); return; }
        try {
            const fullPath = path.join(SESSION_BASE, sessionUuid, filePath);
            // Prevent directory traversal
            const resolved = path.resolve(fullPath);
            const base = path.resolve(path.join(SESSION_BASE, sessionUuid));
            if (!resolved.startsWith(base)) throw new Error("Invalid path");
            const raw = readFile(resolved);
            const { html, toc } = renderMarkdown(raw);
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ html, toc, raw, filePath }));
        } catch (e) {
            res.writeHead(500, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: e.message }));
        }
        return;
    }

    // API: get session info
    if (url.pathname === "/api/session") {
        const sessionUuid = url.searchParams.get("sessionUuid");
        if (!sessionUuid) { res.writeHead(400); res.end(JSON.stringify({ error: "Missing sessionUuid" })); return; }
        try {
            const info = readSessionInfo(sessionUuid);
            const shortId = sessionUuid.substring(0, 8) + "\u2026" + sessionUuid.slice(-4);
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ sessionUuid, shortId, ...info }));
        } catch (e) {
            res.writeHead(500, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: e.message }));
        }
        return;
    }

    // API: get todos with dependency tree
    if (url.pathname === "/api/todos") {
        const sessionUuid = url.searchParams.get("sessionUuid");
        if (!sessionUuid) { res.writeHead(400); res.end(JSON.stringify({ error: "Missing sessionUuid" })); return; }
        try {
            const data = await readTodos(sessionUuid);
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify(data));
        } catch (e) {
            res.writeHead(500, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: e.message }));
        }
        return;
    }

    // Serve HTML UI
    const pageSessionUuid = url.searchParams.get("sessionUuid") || "";
    res.writeHead(200, { "Content-Type": "text/html" });
    res.end(serveHtml(instanceId, pageSessionUuid));
});

await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;

// --- Canvas Definition ---
const canvas = createCanvas({
    id: "session-md-reader",
    displayName: "Session Markdown Reader",
    description: "Browse and render all markdown files in a Copilot CLI session directory. Features: collapsible sidebar, Mermaid diagram rendering, keyboard shortcuts, zoom controls, and todo dependency tree visualization.",
    inputSchema: {
        type: "object",
        properties: {
            sessionUuid: {
                type: "string",
                description: "The session UUID folder name under ~/.copilot/session-state/ (e.g., 7ce52346-ce17-4454-b440-716a6d93aa49). If omitted, the reader opens without a session.",
            },
        },
    },
    actions: [
        {
            name: "refresh_files",
            description: "Re-scan the session directory for markdown files and reload the current selection.",
            inputSchema: {
                type: "object",
                properties: {
                    sessionUuid: { type: "string", description: "The session UUID" },
                },
            },
            handler: async ({ instanceId, input }) => {
                const entry = getInstance(instanceId);
                broadcast(entry, "refresh", { sessionUuid: input?.sessionUuid || entry.state.sessionUuid });
                return { ok: true };
            },
        },
    ],
    open: async (ctx) => {
        const entry = getInstance(ctx.instanceId);
        entry.state.sessionUuid = ctx.input?.sessionUuid || "";
        // Try to get a readable session name for the title
        let displayName = "Session MD Reader";
        if (entry.state.sessionUuid) {
            try {
                const info = readSessionInfo(entry.state.sessionUuid);
                if (info?.name) {
                    const shortName = info.name.length > 40 ? info.name.substring(0, 37) + "\u2026" : info.name;
                    displayName = "MD: " + shortName;
                } else {
                    displayName = "MD: " + entry.state.sessionUuid.substring(0, 8) + "\u2026" + entry.state.sessionUuid.slice(-4);
                }
            } catch {
                displayName = "MD: " + entry.state.sessionUuid.substring(0, 8) + "\u2026" + entry.state.sessionUuid.slice(-4);
            }
        }
        return {
            url: `http://127.0.0.1:${port}?instance=${ctx.instanceId}&sessionUuid=${encodeURIComponent(entry.state.sessionUuid)}`,
            title: displayName,
            status: "Ready",
        };
    },
    onClose: async (ctx) => {
        const entry = instances.get(ctx.instanceId);
        if (entry) {
            entry.cleanup.forEach((fn) => fn());
            instances.delete(ctx.instanceId);
        }
    },
});

const session = await joinSession({
    canvases: [canvas],
    commands: [
        {
            name: "session-md-viewer",
            description: "Open the Session Markdown Reader canvas. Usage: /session-md-viewer [<session-uuid>] — defaults to current session if omitted.",
            handler: async (ctx) => {
                const uuid = (ctx.args.trim() || ctx.sessionId || "").trim();
                if (!uuid) {
                    await session.log("Could not determine session UUID. Usage: /md <session-uuid>", { level: "warning" });
                    return;
                }
                await session.send({
                    prompt: `Open the Session Markdown Reader canvas for session ${uuid}. Use the "session-md-reader" canvas with the open_canvas tool, passing sessionUuid "${uuid}". Do NOT explain in chat — just open the canvas.`,
                    displayPrompt: uuid === ctx.sessionId
                        ? "Opening Markdown Reader for current session\u2026"
                        : `Opening Markdown Reader for session ${uuid.substring(0, 12)}\u2026`,
                });
            },
        },
    ],
    requestCanvasRenderer: true,
});
