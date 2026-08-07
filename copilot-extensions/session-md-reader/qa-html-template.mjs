export function serveHtml(instanceId, initialSessionUuid, maxTodoDepth = 3) {
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
  .sidebar-header h2 { font-size: 13px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; color: var(--text-muted); word-break: break-word; }
  .sidebar-header .session-uuid { font-size: 10px; color: var(--text-muted); font-family: monospace; word-break: break-all; margin-top: 2px; }
  .sidebar-tabs { display: flex; border-bottom: 1px solid var(--border); }
  .sidebar-tab { flex: 1; padding: 8px; text-align: center; font-size: 12px; font-weight: 500; cursor: pointer; border: none; background: none; color: var(--text-muted); transition: all 0.2s; }
  .sidebar-tab:hover { color: var(--text); background: var(--surface); }
  .sidebar-tab.active { color: var(--accent); border-bottom: 2px solid var(--accent); background: var(--surface); }
  .sidebar-content { flex: 1; overflow: hidden; display: flex; flex-direction: column; padding: 8px 0; }
  .sidebar-scroll { flex: 1; overflow-y: auto; min-height: 0; }

  /* File tree toolbar */
  .file-tree-toolbar {
    display: flex; align-items: center; gap: 6px;
    padding: 4px 12px; flex-shrink: 0;
  }
  .file-toggle-all {
    display: flex; align-items: center; gap: 5px;
    padding: 4px 10px; border: 1px solid var(--border);
    border-radius: 5px; cursor: pointer; font-size: 10px;
    background: var(--surface); color: var(--text-muted); flex-shrink: 0;
    transition: background 0.15s;
  }
  .file-toggle-all:hover { background: var(--surface-hover); color: var(--accent); }
  .file-toggle-all .icon { font-size: 12px; }

  /* Nested folder tree */
  .file-folder-header {
    display: flex; align-items: center; gap: 6px;
    padding: 5px 14px 5px 10px; font-size: 12px; font-weight: 600;
    letter-spacing: 0.3px; color: var(--text-muted); cursor: pointer; user-select: none;
  }
  .file-folder-header:hover { color: var(--text); }
  .file-folder-arrow { width: 11px; height: 11px; flex-shrink: 0; transition: transform 0.2s; }
  .file-folder-header.collapsed .file-folder-arrow { transform: rotate(-90deg); }
  .file-folder-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .file-folder-count {
    margin-left: auto; font-size: 10px; color: var(--text-muted); font-weight: 400;
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 10px; padding: 0 7px; flex-shrink: 0;
  }
  .file-folder-children {
    position: relative;
    margin-left: 11px; padding-left: 8px;
    border-left: 1px solid var(--border);
  }
  .file-item { display: flex; align-items: center; gap: 8px; padding: 5px 14px 5px 24px; cursor: pointer; font-size: 13px; color: var(--text-muted); transition: all 0.15s; border-left: 2px solid transparent; }
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

  /* ── Frontmatter metadata card ── */
  .fm-card {
    margin: 4px 0 20px;
    border: 1px solid var(--border);
    border-left: 3px solid var(--accent-dim);
    border-radius: 6px;
    background: var(--sidebar-bg);
    overflow: hidden;
  }
  .fm-card[open] { margin-bottom: 24px; }
  .fm-summary {
    display: flex; align-items: center; gap: 8px;
    padding: 8px 12px; cursor: pointer; list-style: none;
    user-select: none; font-size: 12px;
  }
  .fm-summary::-webkit-details-marker { display: none; }
  .fm-summary:hover { background: var(--surface); }
  .fm-label { font-weight: 600; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.5px; font-size: 11px; }
  .fm-count {
    margin-left: auto; font-size: 10px; color: var(--text-muted);
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 10px; padding: 1px 8px; flex-shrink: 0;
  }
  .fm-chevron { font-size: 10px; color: var(--text-muted); transition: transform 0.2s; flex-shrink: 0; }
  .fm-card[open] > .fm-summary > .fm-chevron,
  .fm-group[open] > .fm-group-summary > .fm-chevron { transform: rotate(90deg); }
  .fm-body {
    padding: 4px 12px 10px;
    border-top: 1px solid var(--border);
    background: color-mix(in srgb, var(--bg) 60%, transparent);
  }
  .fm-row {
    display: flex; gap: 12px; padding: 3px 0;
    font-size: 12.5px; line-height: 1.5; align-items: baseline;
    border-bottom: 1px dashed color-mix(in srgb, var(--border) 50%, transparent);
  }
  .fm-row:last-child { border-bottom: none; }
  .fm-key {
    flex: 0 0 180px; color: var(--accent); font-family: 'JetBrains Mono', 'Fira Code', monospace;
    font-size: 11.5px; word-break: break-word; min-width: 0;
  }
  .fm-value { flex: 1; color: var(--text); word-break: break-word; min-width: 0; }
  .fm-null { color: var(--text-muted); font-style: italic; }
  .fm-bool { color: #7ee787; font-family: monospace; }
  .fm-num { color: #79c0ff; font-family: monospace; }
  .fm-url { color: var(--accent); text-decoration: underline; word-break: break-all; }
  .fm-group { display: block; margin-top: 4px; }
  .fm-group-summary {
    display: flex; align-items: center; gap: 6px;
    padding: 5px 8px; cursor: pointer; list-style: none;
    font-size: 12px; color: var(--text); border-radius: 4px;
    font-family: 'JetBrains Mono', 'Fira Code', monospace;
  }
  .fm-group-summary::-webkit-details-marker { display: none; }
  .fm-group-summary:hover { background: var(--surface); }
  .fm-group-summary .fm-count { margin-left: auto; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif; }
  .fm-group-body {
    padding: 2px 4px 6px 14px;
    border-left: 1px solid color-mix(in srgb, var(--accent-dim) 35%, transparent);
    margin-left: 6px;
  }

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
  .sidebar.collapsed .sidebar-header div { display: none; }
  .sidebar.collapsed .sidebar-header svg { margin: 0; }
  .sidebar.collapsed .sidebar-tabs { flex-direction: column; border-bottom: none; }
  .sidebar.collapsed .sidebar-tab { font-size: 0; padding: 8px 4px; flex: none; }
  .sidebar.collapsed .sidebar-tab::after { content: attr(data-icon); font-size: 16px; }
  .sidebar.collapsed .sidebar-tab.active { border-bottom: none; border-left: 2px solid var(--accent); }
  .sidebar.collapsed .file-tree-toolbar,
  .sidebar.collapsed .file-folder,
  .sidebar.collapsed .file-item,
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

  /* ── Non-markdown previews (code / image / binary) ── */
  .main .code-view {
    background: var(--surface); border: 1px solid var(--border); border-radius: 8px;
    padding: 14px; margin: 12px 0; overflow: auto; max-height: 70vh;
    font-family: var(--mono, ui-monospace, SFMono-Regular, Consolas, monospace);
    font-size: 12px; line-height: 1.6; color: var(--text); white-space: pre; word-break: normal;
  }
  .main .code-view code { font-family: inherit; }
  .main .image-view { padding: 12px 0; }
  .main .image-view img {
    max-width: 100%; height: auto; border-radius: 8px;
    border: 1px solid var(--border); background: #0d0d12; display: block;
  }
  .main .binary-notice {
    margin: 12px 0; padding: 28px 20px; text-align: center;
    border: 1px dashed var(--border); border-radius: 8px; color: var(--text-muted);
  }
  .main .binary-notice p { margin: 4px 0; }
  .main .binary-notice .meta { font-size: 12px; opacity: 0.7; word-break: break-all; }

  /* ── Todo tree styles ── */
  .todo-tree-container {
    padding: 4px 0; flex: 1; overflow-y: auto;
    display: flex; flex-direction: column;
  }
  .todo-tree-container .empty-state {
    padding: 20px 16px; text-align: center; color: var(--text-muted); font-size: 12px;
  }
  .todo-tree-container .empty-state svg { width: 32px; height: 32px; opacity: 0.3; margin-bottom: 8px; }

  /* Toggle all button */
  .todo-tree-toolbar {
    display: flex; align-items: center; gap: 6px;
    padding: 4px 12px; flex-shrink: 0;
  }
  .todo-toggle-all {
    display: flex; align-items: center; gap: 5px;
    padding: 4px 10px; border: 1px solid var(--border);
    border-radius: 5px; cursor: pointer; font-size: 10px;
    background: var(--surface); color: var(--text-muted); flex-shrink: 0;
    transition: background 0.15s;
  }
  .todo-toggle-all:hover { background: var(--surface-hover); color: var(--accent); }
  .todo-toggle-all .icon { font-size: 12px; }

  /* ── Progress bar ── */
  .todo-progress-bar {
    display: flex; align-items: center; gap: 8px;
    padding: 2px 12px 6px; flex-shrink: 0;
  }
  .todo-progress-track {
    flex: 1; height: 6px; border-radius: 3px;
    background: var(--surface); border: 1px solid var(--border);
    overflow: hidden; min-width: 0;
  }
  .todo-progress-fill {
    height: 100%; background: var(--success); border-radius: 3px;
    transition: width 0.3s ease;
  }
  .todo-progress-label {
    font-size: 10px; color: var(--text-muted); white-space: nowrap;
    font-family: monospace; flex-shrink: 0;
  }

  /* Nodes flattened below the configured max depth are dimmed */
  .todo-tree-node[data-flattened="true"] > summary .todo-title { color: var(--text-muted); }

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
    flex-direction: column;
    background: var(--sidebar-bg);
    border-top: 1px solid var(--border);
    padding: 12px; height: 350px; max-height: 350px;
    overflow: hidden;
    font-size: 11px; line-height: 1.5;
  }
  .todo-details-panel.open { display: flex; flex-direction: column; }
  .todo-details-header {
    flex-shrink: 0;
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
  #todoDetailBody {
    flex: 1; min-height: 0;
    display: flex; flex-direction: column;
    overflow: hidden;
  }
  .todo-details-metadata {
    flex-shrink: 0;
    display: flex; flex-direction: column;
  }
  .todo-details-field {
    display: flex; align-items: baseline; gap: 4px;
    padding: 3px 0; color: var(--text-muted);
  }
  .todo-details-field .label { color: var(--text-muted); font-weight: 500; flex-shrink: 0; }
  .todo-details-field .value { color: var(--text); word-break: break-word; }
  .todo-details-description {
    flex: 1; min-height: 0;
    display: flex; flex-direction: column;
    margin-top: 8px; padding: 8px;
    background: var(--surface); border-radius: 4px;
  }
  .todo-details-description #todoDetailDesc {
    flex: 1; min-height: 0; overflow-y: auto;
    font-size: 10px; color: var(--text-muted); line-height: 1.5;
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

  /* ── Pass badge ── */
  .todo-pass-badge {
    display: inline-block; padding: 1px 6px; font-size: 9px;
    font-family: monospace; color: var(--accent);
    background: color-mix(in srgb, var(--accent) 15%, transparent);
    border: 1px solid color-mix(in srgb, var(--accent) 30%, transparent);
    border-radius: 8px; flex-shrink: 0; margin-top: 2px;
    line-height: 1.4; white-space: nowrap;
  }

  /* ── Pass filter bar ── */
  .todo-filter-bar {
    display: flex; align-items: center; gap: 4px;
    padding: 0 12px 4px; flex-wrap: wrap; flex-shrink: 0;
  }
  .todo-filter-btn {
    padding: 2px 8px; font-size: 9px; font-family: monospace;
    border: 1px solid var(--border); border-radius: 8px;
    cursor: pointer; background: transparent; color: var(--text-muted);
    transition: all 0.15s;
  }
  .todo-filter-btn:hover { background: var(--surface-hover); color: var(--text); }
  .todo-filter-btn.active {
    background: var(--accent); color: #fff; border-color: var(--accent);
  }
  .todo-tree-node.hidden-by-filter { display: none; }

  /* ── Tab refresh button ── */
  .sidebar-tab { position: relative; }
  .tab-refresh-btn {
    position: absolute; right: 3px; top: 50%; transform: translateY(-50%);
    width: 14px; height: 14px; display: flex; align-items: center; justify-content: center;
    border-radius: 50%; border: none; cursor: pointer;
    font-size: 11px; opacity: 0; transition: opacity 0.15s;
    background: var(--surface-hover); color: var(--text-muted);
    line-height: 1; padding: 0;
  }
  .sidebar-tab:hover .tab-refresh-btn { opacity: 0.65; }
  .tab-refresh-btn:hover { opacity: 1 !important; color: var(--accent); }
  .tab-refresh-btn.loading { animation: tab-spin 0.6s linear infinite; }
  @keyframes tab-spin { to { transform: translateY(-50%) rotate(360deg); } }
  .sidebar.collapsed .tab-refresh-btn { display: none; }
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
        <div class="session-uuid" id="sessionUuidLabel"></div>
      </div>
    </div>
    <div class="sidebar-tabs">
      <button class="sidebar-tab active" data-tab="files" data-icon="&#x1F4C4;" onclick="switchTab('files')"><span class="tab-label">Files</span><span class="tab-refresh-btn" onclick="event.stopPropagation();refreshTab('files')">&#x21bb;</span></button>
      <button class="sidebar-tab" data-tab="toc" data-icon="&#x1F4CB;" onclick="switchTab('toc')"><span class="tab-label">TOC</span><span class="tab-refresh-btn" onclick="event.stopPropagation();refreshTab('toc')">&#x21bb;</span></button>
      <button class="sidebar-tab" data-tab="todos" data-icon="&#x1F4CA;" onclick="switchTab('todos')"><span class="tab-label">Todos</span><span class="tab-refresh-btn" onclick="event.stopPropagation();refreshTab('todos')">&#x21bb;</span></button>
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
      <p id="welcomeDesc">Select a file from the sidebar to browse its content. Markdown files get rich rendering with Mermaid diagrams; other files show a code, image, or binary preview. The TOC tab shows auto-generated headings for markdown.</p>
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
const MAX_TODO_DEPTH = ${maxTodoDepth};
let allFiles = [];
let currentFilePath = null;
let currentToc = [];
let activeHeadingId = null;
let sidebarCollapsed = false;
let zoomLevel = 1.0;
let todosData = null;
let activePass = null;

// Extension sets for per-file icons (image / text)
const CLIENT_IMAGE_EXTS = new Set(["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "ico"]);
const CLIENT_TEXT_EXTS = new Set([
    "md", "markdown", "txt", "log", "json", "jsonl", "sql", "yaml", "yml", "toml", "ini", "cfg", "conf",
    "cs", "js", "jsx", "ts", "tsx", "py", "rb", "go", "java", "c", "cpp", "h", "hpp", "csproj", "props",
    "targets", "editorconfig", "diff", "patch", "xml", "html", "css", "scss", "less", "sh", "ps1", "bat",
    "cmd", "csv", "tsv", "env", "gitignore", "dockerfile", "makefile", "lock",
]);

// Collapse state for the nested folder tree (keyed by normalized path)
const folderCollapsed = {};
// Per-tab scroll memory so switching tabs / re-rendering keeps position
const tabScroll = { files: 0, toc: 0, todos: 0 };

// Replace sidebar content while preserving the scroller's scroll position.
// scrollSel: CSS selector of the element that actually scrolls inside #sidebarContent.
function setSidebarContent(html, scrollSel) {
    const scroller = scrollSel ? sidebarContent.querySelector(scrollSel) : null;
    const prevTop = scroller ? scroller.scrollTop : 0;
    sidebarContent.innerHTML = html;
    const newScroller = scrollSel ? sidebarContent.querySelector(scrollSel) : null;
    if (newScroller && prevTop) newScroller.scrollTop = prevTop;
}

function captureTabScroll(tab) {
    const sel = tab === "todos" ? ".todo-tree-container" : ".sidebar-scroll";
    const el = sidebarContent.querySelector(sel);
    if (el) tabScroll[tab] = el.scrollTop;
}

function restoreTabScroll(tab) {
    const sel = tab === "todos" ? ".todo-tree-container" : ".sidebar-scroll";
    const el = sidebarContent.querySelector(sel);
    if (el && tabScroll[tab]) el.scrollTop = tabScroll[tab];
}

// --- DOM refs ---
const sidebarEl = document.getElementById("sidebar");
const sidebarContent = document.getElementById("sidebarContent");
const mainContent = document.getElementById("mainContent");
const welcomeView = document.getElementById("welcomeView");
const loadingView = document.getElementById("loadingView");
const renderedContent = document.getElementById("renderedContent");
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
            sidebarTitle.textContent = data.name;
            document.title = "MD: " + data.name;
            welcomeTitle.textContent = data.name;
        } else if (data.shortId) {
            sidebarTitle.textContent = data.shortId;
            document.title = "MD: " + data.shortId;
        }
        const uuidEl = document.getElementById("sessionUuidLabel");
        if (uuidEl) uuidEl.textContent = SESSION_UUID;
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
let currentFilterPass = "all";
function switchTab(tab) {
    if (tab === currentTab) return;
    captureTabScroll(currentTab);
    currentTab = tab;
    document.querySelectorAll(".sidebar-tab").forEach(t => t.classList.toggle("active", t.dataset.tab === tab));
    renderSidebar();
    restoreTabScroll(tab);
    if (tab === "todos" && !todosData) loadTodos();
}

// --- Inline tab refresh ---
async function refreshTab(tab) {
    currentTab = tab;
    document.querySelectorAll(".sidebar-tab").forEach(t => t.classList.toggle("active", t.dataset.tab === tab));
    const btn = document.querySelector('.sidebar-tab[data-tab="' + tab + '"] .tab-refresh-btn');
    if (btn) btn.classList.add("loading");
    try {
        if (tab === "files") {
            await loadFiles();
        } else if (tab === "toc") {
            if (currentFilePath) await loadFile(currentFilePath);
        } else if (tab === "todos") {
            await loadTodosForce();
        }
    } catch (e) {
        console.error("Refresh error:", e);
    }
    if (btn) btn.classList.remove("loading");
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
        sidebarTitle.textContent = "No session UUID";
        fileCountBadge.textContent = "No session selected";
        return;
    }
    const uuidEl = document.getElementById("sessionUuidLabel");
    if (uuidEl) uuidEl.textContent = SESSION_UUID;
    try {
        const res = await fetch("/api/files?sessionUuid=" + encodeURIComponent(SESSION_UUID));
        const data = await res.json();
        allFiles = data.files || [];
        activePass = data.activePass != null ? String(data.activePass) : null;
        fileCountBadge.textContent = allFiles.length + " file" + (allFiles.length !== 1 ? "s" : "") + " found";
        renderSidebar();
    } catch (e) {
        fileCountBadge.textContent = "Error loading files";
        setSidebarContent('<div style="padding:20px;color:var(--warning);text-align:center">Failed to load files.<br>Check session UUID.</div>', null);
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

// --- Force reload todos (ignore cache) ---
async function loadTodosForce() {
    if (!SESSION_UUID) return;
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
        setSidebarContent('<div class="toc-empty">No files found</div>', ".sidebar-scroll");
        return;
    }

    const tree = buildFileTree(allFiles);
    ensureFolderState(tree);

    // Toolbar: collapse/expand all folders
    const anyCollapsed = Object.values(folderCollapsed).some(v => v === true);
    const allLabel = anyCollapsed ? "Expand All" : "Collapse All";
    let html = '<div class="file-tree-toolbar"><button class="file-toggle-all" onclick="toggleAllFolders()"><span class="icon">&#x229E;</span><span id="fileToggleAllLabel">' + allLabel + '</span></button></div>';
    html += '<div class="sidebar-scroll">';
    html += renderFileNode(tree, 0);
    html += '</div>';
    setSidebarContent(html, ".sidebar-scroll");
}

// Build a nested tree of folders + files from relative paths.
function buildFileTree(files) {
    const root = { name: "", path: "", dirs: new Map(), files: [] };
    for (const f of files) {
        const segs = f.relativePath.split(/[\\\\/]/);
        let node = root;
        for (let i = 0; i < segs.length - 1; i++) {
            const seg = segs[i];
            if (!node.dirs.has(seg)) node.dirs.set(seg, { name: seg, path: segs.slice(0, i + 1).join("/"), dirs: new Map(), files: [] });
            node = node.dirs.get(seg);
        }
        node.files.push(f);
    }
    return root;
}

function countNodeFiles(node) {
    let n = node.files.length;
    for (const d of node.dirs.values()) n += countNodeFiles(d);
    return n;
}

// On first render, default every folder collapsed except the active pass
// folder and its ancestors (which stay open so the active pass is visible).
function ensureFolderState(tree) {
    if (Object.keys(folderCollapsed).length) return;
    const collect = (node, out) => {
        for (const d of node.dirs.values()) { out.push(d); collect(d, out); }
    };
    const allDirs = [];
    collect(tree, allDirs);
    // Find folders whose last path segment is pass-<activePass>
    const openSet = new Set();
    if (activePass) {
        const targetSeg = "pass-" + activePass;
        for (const d of allDirs) {
            const segs = d.path.split("/");
            if (segs[segs.length - 1] === targetSeg) {
                for (let i = 1; i <= segs.length; i++) openSet.add(segs.slice(0, i).join("/"));
            }
        }
    }
    for (const d of allDirs) {
        folderCollapsed[d.path] = openSet.has(d.path) ? false : true;
    }
}

function renderFileNode(node, depth) {
    let html = "";
    // Folders first (sorted), then files (sorted)
    const dirs = [...node.dirs.values()].sort((a, b) => a.name.localeCompare(b.name));
    for (const dir of dirs) {
        const collapsed = folderCollapsed[dir.path] === true;
        const total = countNodeFiles(dir);
        html += '<div class="file-folder" data-folder="' + escapeHtml(dir.path) + '">';
        html += '<div class="file-folder-header' + (collapsed ? ' collapsed' : ' open') + '" data-folder="' + escapeHtml(dir.path) + '">';
        html += '<svg class="file-folder-arrow" viewBox="0 0 20 20" fill="currentColor"><path d="M6 4l8 6-8 6z"/></svg>';
        html += '<span class="file-folder-name">' + escapeHtml(dir.name) + '</span>';
        html += '<span class="file-folder-count">' + total + '</span>';
        html += '</div>';
        if (!collapsed) {
            html += '<div class="file-folder-children">' + renderFileNode(dir, depth + 1) + '</div>';
        }
        html += '</div>';
    }
    const files = node.files.slice().sort((a, b) => a.fileName.localeCompare(b.fileName));
    for (const f of files) {
        const active = currentFilePath === f.relativePath ? ' active' : '';
        const firstSeg = f.relativePath.split(/[\\\\/]/)[0];
        let icon;
        if (firstSeg === "checkpoints") icon = "\u{1F4CB}";
        else if (f.fileName === "plan.md") icon = "\u{1F4D1}";
        else {
            const ext = (f.fileName.includes(".") ? f.fileName.split(".").pop() : f.fileName).toLowerCase();
            if (CLIENT_IMAGE_EXTS.has(ext)) icon = "\u{1F5BC}";
            else if (/\.md$/i.test(f.fileName) || CLIENT_TEXT_EXTS.has(ext)) icon = "\u{1F4C4}";
            else icon = "\u{1F4CE}";
        }
        html += '<div class="file-item' + active + '" onclick="loadFile(\\'' + f.relativePath.replace(/\\\\/g, '\\\\\\\\') + '\\')" data-path="' + escapeHtml(f.relativePath) + '">';
        html += '<span class="icon">' + icon + '</span>';
        html += '<span class="name">' + escapeHtml(f.fileName) + '</span>';
        html += '</div>';
    }
    return html;
}

// --- Folder collapse state + toggle-all (delegated clicks avoid inline-onclick escaping bugs) ---
function toggleFolder(path) {
    folderCollapsed[path] = folderCollapsed[path] === true ? false : true;
    renderFileList();
}

function toggleAllFolders() {
    // Label promises: if any folder is collapsed, clicking EXPANDS all; else collapses all.
    const anyCollapsed = Object.values(folderCollapsed).some(v => v === true);
    for (const k of Object.keys(folderCollapsed)) {
        folderCollapsed[k] = anyCollapsed ? false : true;
    }
    renderFileList();
}

// Delegated click handler for folder headers (uses data-folder, safe for backslash paths)
sidebarContent.addEventListener("click", (e) => {
    const header = e.target.closest ? e.target.closest(".file-folder-header") : null;
    if (header) {
        e.preventDefault();
        e.stopPropagation();
        const path = header.getAttribute("data-folder");
        if (path) toggleFolder(path);
    }
});

function renderTocTree() {
    if (!currentToc.length) {
        setSidebarContent('<div class="toc-empty">No headings found in current file</div>', ".sidebar-scroll");
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
    setSidebarContent('<div class="sidebar-scroll">' + html + '</div>', ".sidebar-scroll");
}

// --- Render Todos Tree (SVG) ---
function renderTodosTree() {
    const tree = todosData?.tree || [];
    if (!tree.length) {
        setSidebarContent('<div class="todo-tree-container"><div class="empty-state">'
            + '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>'
            + '<br>No todos found</div></div>', ".todo-tree-container");
        return;
    }

    const statusColors = { pending: "#88889a", in_progress: "#7c8aff", done: "#4ade80", blocked: "#f87171" };
    const statusLabels = { pending: "Pending", in_progress: "In Progress", done: "Done", blocked: "Blocked" };

    // Build HTML tree recursively
    function buildNodeHtml(node, depth) {
        const color = statusColors[node.status] || statusColors.pending;
        const label = statusLabels[node.status] || node.status;
        const title = escapeHtml(node.title || node.id);
        const children = node.children || [];
        const hasChildren = children.length > 0 && children[0]?.id !== "CYCLE";
        const passId = extractPassId(node.id);
        // Clamp visual depth to the configured max — deeper nodes are flattened
        // at the deepest visible level (DB data stays unchanged).
        const visDepth = Math.min(depth, MAX_TODO_DEPTH);
        const flattened = depth > MAX_TODO_DEPTH ? ' data-flattened="true"' : "";

        let html = '<details open class="todo-tree-node" style="--depth:' + visDepth + '" data-id="' + escapeHtml(node.id) + '" data-passid="' + escapeHtml(passId) + '"' + flattened + '>';
        html += '<summary class="todo-node-content" style="margin-left:' + (24 + visDepth * 20) + 'px" onclick="onTodoNodeClick(event, this, \\'' + escapeHtml(node.id) + '\\')">';
        html += '<span class="chevron"' + (hasChildren ? '' : ' style="visibility:hidden"') + '>▶</span>';
        html += '<span class="todo-status-dot" style="--status-color:' + color + '"></span>';
        html += '<span class="todo-title">' + title + '</span>';
        html += '<span class="todo-pass-badge">' + escapeHtml(passId) + '</span>';
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

    // Collect unique pass IDs
    const passIds = new Set();
    for (const t of todosData?.todos || []) {
        const pid = extractPassId(t.id);
        if (pid) passIds.add(pid);
    }
    const uniquePassIds = [...passIds].sort();

    let html = '<div class="todo-tree-toolbar"><button class="todo-toggle-all" onclick="toggleAllTodos()"><span class="icon">⊞</span><span id="toggleAllLabel">Collapse All</span></button></div>';

    // Progress bar: completion of all sql todos
    const allTodos = todosData?.todos || [];
    const doneCount = allTodos.filter(t => t.status === "done").length;
    if (allTodos.length > 0) {
        const pct = Math.round((doneCount / allTodos.length) * 100);
        html += '<div class="todo-progress-bar">'
            + '<div class="todo-progress-track"><div class="todo-progress-fill" style="width:' + pct + '%"></div></div>'
            + '<span class="todo-progress-label">' + doneCount + '/' + allTodos.length + ' done &middot; ' + pct + '%</span>'
            + '</div>';
    }

    html += '<div class="todo-filter-bar" id="todoFilterBar">';
    html += '<button class="todo-filter-btn active" data-pass="all" onclick="filterTodosByPass(\\'all\\')">All</button>';
    for (const pid of uniquePassIds) {
        html += '<button class="todo-filter-btn" data-pass="' + escapeHtml(pid) + '" onclick="filterTodosByPass(\\'' + escapeHtml(pid) + '\\')">' + escapeHtml(pid) + '</button>';
    }
    html += '</div>';
    html += '<div class="todo-tree-container">';
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
    html += '<div class="todo-details-metadata">';
    html += '<div class="todo-details-field"><span class="label">ID: </span><span class="value" id="todoDetailId"></span></div>';
    html += '<div class="todo-details-field"><span class="label">Status: </span><span class="value" id="todoDetailStatus"></span></div>';
    html += '<div class="todo-details-field"><span class="label">Created: </span><span class="value" id="todoDetailCreated"></span></div>';
    html += '<div class="todo-details-field"><span class="label">Updated: </span><span class="value" id="todoDetailUpdated"></span></div>';
    html += '<div class="todo-details-field" id="todoDetailDepsContainer" style="display:none"><span class="label">Dependencies: </span><span id="todoDetailDeps"></span></div>';
    html += '</div>';
    html += '<div class="todo-details-description"><div id="todoDetailDesc"></div></div>';
    html += '</div></div>';

    setSidebarContent(html, ".todo-tree-container");
    // Re-apply current filter if set
    if (currentFilterPass && currentFilterPass !== "all") {
        filterTodosByPass(currentFilterPass);
    }
}

// --- Pass ID extraction ---
function extractPassId(todoId) {
    if (!todoId || typeof todoId !== "string") return "";
    const idx = todoId.indexOf("-");
    return idx > 0 ? todoId.substring(0, idx) : "";
}

// --- Filter todos by pass ID ---
function filterTodosByPass(passId) {
    currentFilterPass = passId;
    // Update button states
    document.querySelectorAll(".todo-filter-btn").forEach(btn => btn.classList.remove("active"));
    const activeBtn = document.querySelector('.todo-filter-btn[data-pass="' + passId + '"]');
    if (activeBtn) activeBtn.classList.add("active");

    // Show/hide nodes
    document.querySelectorAll(".todo-tree-node").forEach(node => {
        const nodePass = node.getAttribute("data-passid") || "";
        if (passId === "all" || nodePass === passId) {
            node.classList.remove("hidden-by-filter");
        } else {
            node.classList.add("hidden-by-filter");
        }
    });
}

// --- Toggle all todos (collapse/expand) ---
function toggleAllTodos() {
    const details = document.querySelectorAll(".todo-tree-node");
    const anyOpen = Array.from(details).some(d => d.open);
    const label = document.getElementById("toggleAllLabel");
    for (const d of details) {
        d.open = !anyOpen;
    }
    label.textContent = anyOpen ? "Expand All" : "Collapse All";
}

// --- Todo node click handler ---
function onTodoNodeClick(event, element, todoId) {
    // Clicking the chevron toggles the nested items (native details/summary
    // behavior) — it must NOT open the details panel or change selection.
    if (event && event.target && event.target.closest && event.target.closest(".chevron")) {
        return;
    }
    // Any other click on the row must NOT toggle collapse/expand — only the
    // chevron does. Suppress the native details/summary toggle (the panel is
    // opened below). Keyboard activation (Enter/Space on a focused summary)
    // still toggles natively, which is intentionally left unchanged.
    if (event && event.preventDefault) {
        event.preventDefault();
    }
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
        depsContainer.style.display = "flex";
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
        currentToc = [];
        let typeLabel = "";

        if (data.kind === "markdown") {
            currentToc = data.toc || [];
            renderedContent.innerHTML = data.html;
            typeLabel = "markdown";
            runMermaid();
        } else if (data.kind === "text") {
            renderedContent.innerHTML = '<pre class="code-view"><code>' + escapeHtml(data.raw || "") + '</code></pre>';
            typeLabel = "text";
        } else if (data.kind === "image") {
            const rawUrl = "/api/raw?sessionUuid=" + encodeURIComponent(SESSION_UUID) + "&path=" + encodeURIComponent(relativePath);
            renderedContent.innerHTML = '<div class="image-view"><img src="' + rawUrl + '" alt="' + escapeHtml(relativePath) + '"></div>';
            typeLabel = "image";
        } else {
            const kb = data.size ? Math.max(1, Math.round(data.size / 1024)) : 0;
            renderedContent.innerHTML = '<div class="binary-notice"><p>Cannot preview binary file</p><p class="meta">' + escapeHtml(relativePath) + ' &middot; ' + kb + ' KB</p></div>';
            typeLabel = "binary";
        }

        renderedContent.style.display = "block";
        loadingView.style.display = "none";

        // Update active file info (headings only meaningful for markdown)
        if (data.kind === "markdown") {
            activeFileInfo.innerHTML = '<span class="path">' + escapeHtml(relativePath) + '</span><span class="sep">|</span><span class="hcount">' + currentToc.length + ' heading' + (currentToc.length !== 1 ? "s" : "") + '</span>';
        } else {
            const kb = data.size ? Math.max(1, Math.round(data.size / 1024)) : 0;
            activeFileInfo.innerHTML = '<span class="path">' + escapeHtml(relativePath) + '</span><span class="sep">|</span><span class="hcount">' + typeLabel + ' &middot; ' + kb + ' KB</span>';
        }

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
    sidebarTitle.textContent = "No session UUID";
    fileCountBadge.textContent = "Provide sessionUuid to open";
}
</script>
</body>
</html>`;
}
