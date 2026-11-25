#!/usr/bin/env python3
"""Export a Copilot CLI session transcript to HTML: user request + agent response only.

Deliberately drops everything the user asked to omit:
  * thinking        -> assistant.message.data.reasoningText / reasoningBlocks
  * tool calls      -> assistant.message.data.toolRequests, tool.execution_* events
  * system plumbing -> hooks, usage records, permissions, transformedContent
                       (transformedContent embeds <system_reminder>/<workspace_info>)
  * sub-agent threads launched via the task tool (opt back in with --include-sub-agents)

Data sources (--source auto|events|db):
  events  %USERPROFILE%\\.copilot\\session-state\\<id>\\events.jsonl
          Raw event stream. Works for live and recent sessions; carries timestamps,
          per-turn tool counts and interim narration. Preferred.
  db      %USERPROFILE%\\.copilot\\session-store.db -> turns table
          Already-curated (user_message, assistant_response) pairs for older/pruned
          sessions whose event files are gone. Keeps only the final response per turn
          and may contain NULL responses (35% of rows on this machine).

Filtering rules were validated against 60 recent sessions (439 user messages,
8652 assistant messages) before this script existed; see README note in the header
of the HTML output.

Data root: $COPILOT_HOME if set, else %USERPROFILE%\\.copilot (the standard
Copilot home layout).

Usage:
  python scripts/export-copilot-transcript.py --list
  python scripts/export-copilot-transcript.py                          # newest session
  python scripts/export-copilot-transcript.py --session <id> --open
  python scripts/export-copilot-transcript.py --session <id> --final-only
  python scripts/export-copilot-transcript.py --session <id> --source db

Vendored into the daily-report skill; Export-SessionTranscripts.ps1 drives it.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sqlite3
import subprocess
import sys
from datetime import datetime
from pathlib import Path

COPILOT_ROOT = (
    Path(os.environ["COPILOT_HOME"])
    if os.environ.get("COPILOT_HOME")
    else Path(os.environ.get("USERPROFILE", str(Path.home()))) / ".copilot"
)
STATE_DIR = COPILOT_ROOT / "session-state"
STORE_DB = COPILOT_ROOT / "session-store.db"


# --------------------------------------------------------------------------- #
# Extraction: events.jsonl
# --------------------------------------------------------------------------- #

def resolve_session_dir(session: str | None) -> Path | None:
    """Resolve --session to a session folder. None -> newest folder with events."""
    if session:
        p = Path(session)
        if p.is_file() and p.name == "events.jsonl":
            return p.parent
        if p.is_dir() and (p / "events.jsonl").exists():
            return p
        cand = STATE_DIR / session
        if (cand / "events.jsonl").exists():
            return cand
        return None
    newest, newest_mtime = None, -1.0
    if STATE_DIR.is_dir():
        for d in STATE_DIR.iterdir():
            f = d / "events.jsonl"
            if d.is_dir() and f.is_file():
                m = f.stat().st_mtime
                if m > newest_mtime:
                    newest, newest_mtime = d, m
    return newest


def _attachment_names(data: dict) -> list[str]:
    names = []
    for a in data.get("attachments") or []:
        if isinstance(a, str):
            names.append(a)
        elif isinstance(a, dict):
            for key in ("displayName", "name", "fileName", "filename", "path", "uri"):
                if a.get(key):
                    names.append(str(a[key]))
                    break
    return names


def _duration_ms(start: str | None, end: str | None) -> int | None:
    try:
        a = datetime.fromisoformat(str(start).replace("Z", "+00:00"))
        b = datetime.fromisoformat(str(end).replace("Z", "+00:00"))
        ms = int((b - a).total_seconds() * 1000)
        return ms if ms >= 0 else None
    except (ValueError, TypeError):
        return None


def extract_from_events(
    session_dir: Path, include_sub_agents: bool, final_only: bool
) -> dict:
    """Pull human turns out of the raw event stream.

    Grouping key is interactionId: a user.message and every assistant.message step
    that answers it share the same interactionId (verified: 0 unmatched assistant
    messages across a 60-session sample).
    """
    path = session_dir / "events.jsonl"
    meta: dict = {"source": "events", "session_id": session_dir.name}
    turns: list[dict] = []
    by_interaction: dict[str, dict] = {}
    seen_message_ids: set[str] = set()
    stats = {
        "tool_calls_hidden": 0,
        "reasoning_chars_hidden": 0,
        "tool_only_steps_dropped": 0,
        "sub_agent_msgs_excluded": 0,
        "parse_errors": 0,
    }

    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                stats["parse_errors"] += 1
                continue
            etype = ev.get("type")
            data = ev.get("data") or {}
            ts = ev.get("timestamp")

            # Every event that belongs to a known interaction extends that turn's
            # wall-clock duration (assistant.message, tool.execution_complete,
            # assistant.turn_start all carry interactionId; the file is append-ordered).
            iid = data.get("interactionId")
            if iid and iid in by_interaction and ts:
                by_interaction[iid]["last_ts"] = ts
                tid = data.get("turnId")
                if tid is not None and tid != "" and etype == "tool.execution_complete":
                    by_interaction[iid]["step_ids"].add(str(tid))  # step seen only via its tool run

            if etype == "session.start":
                ctx = data.get("context") or {}
                meta.update(
                    model=data.get("selectedModel"),
                    started=data.get("startTime"),
                    cwd=ctx.get("cwd"),
                    repository=ctx.get("repository"),
                    branch=ctx.get("branch"),
                )
                continue

            if etype == "user.message":
                source = str(data.get("source") or "")
                if source.startswith("agent-") and not include_sub_agents:
                    stats["sub_agent_msgs_excluded"] += 1
                    continue
                iid = data.get("interactionId")
                if not iid or iid in by_interaction:
                    continue
                turn = {
                    "ts": ts,
                    "first_ts": ts,
                    "last_ts": ts,
                    "user": (data.get("content") or "").strip(),
                    "attachments": _attachment_names(data),
                    "assistant": [],
                    "tools": 0,
                    "reasoning": 0,
                    "step_ids": set(),
                    "extra_steps": 0,
                }
                turns.append(turn)
                by_interaction[iid] = turn
                continue

            if etype == "assistant.message":
                mid = data.get("messageId")
                if mid:
                    if mid in seen_message_ids:
                        continue  # streaming replay guard
                    seen_message_ids.add(mid)
                if data.get("parentToolCallId") and not include_sub_agents:
                    stats["sub_agent_msgs_excluded"] += 1
                    continue
                tools = data.get("toolRequests") or []
                reasoning = data.get("reasoningText") or ""
                turn = by_interaction.get(data.get("interactionId"))
                if turn is None:
                    continue  # orphan / sub-agent step: not part of a human turn
                tid = data.get("turnId")
                if tid is None or tid == "":
                    turn["extra_steps"] += 1  # no step id: count the message itself
                else:
                    turn["step_ids"].add(str(tid))  # one id per model step (chunk-safe)
                turn["tools"] += len(tools)
                turn["reasoning"] += len(reasoning)
                stats["tool_calls_hidden"] += len(tools)
                stats["reasoning_chars_hidden"] += len(reasoning)
                content = (data.get("content") or "").strip()
                if content:
                    turn["assistant"].append(content)
                elif tools or reasoning:
                    stats["tool_only_steps_dropped"] += 1

    for t in turns:
        t["steps"] = len(t.pop("step_ids")) + t.pop("extra_steps")
        t["duration_ms"] = _duration_ms(t.pop("first_ts"), t.pop("last_ts"))

    if final_only:
        for t in turns:
            t["assistant"] = t["assistant"][-1:]
    turns = [t for t in turns if t["user"] or t["attachments"] or t["assistant"]]
    meta["turns"] = turns
    meta["stats"] = stats
    return meta


# --------------------------------------------------------------------------- #
# Extraction: session-store.db fallback
# --------------------------------------------------------------------------- #

def extract_from_db(session_id: str, final_only: bool) -> dict:
    if not STORE_DB.exists():
        raise SystemExit(f"error: session store not found: {STORE_DB}")
    con = sqlite3.connect(f"file:{STORE_DB}?mode=ro", uri=True)
    try:
        rows = con.execute(
            """
            SELECT t.turn_index, t.user_message, t.assistant_response, t.timestamp,
                   s.summary, s.cwd, s.repository, s.branch, s.created_at
            FROM turns t LEFT JOIN sessions s ON s.id = t.session_id
            WHERE t.session_id = ? ORDER BY t.turn_index
            """,
            (session_id,),
        ).fetchall()
        if not rows:
            raise SystemExit(f"error: no turns for session {session_id} in {STORE_DB}")
        summary, cwd, repository, branch, created_at = rows[0][4:9]
    finally:
        con.close()

    turns = []
    for _, user_msg, assistant_msg, ts, *_ in rows:
        assistant = [assistant_msg] if assistant_msg else []
        if final_only:
            assistant = assistant[-1:]
        turns.append(
            {
                "ts": ts,
                "user": (user_msg or "").strip(),
                "attachments": [],
                "assistant": assistant,
                "tools": 0,
                "reasoning": 0,
                # The curated store keeps only the final response: agent step count
                # and duration are unknowable here, so they are reported as n/a.
                "steps": None,
                "duration_ms": None,
            }
        )
    return {
        "source": "db",
        "session_id": session_id,
        "model": None,
        "started": created_at,
        "cwd": cwd,
        "repository": repository,
        "branch": branch,
        "turns": turns,
        "stats": {
            "tool_calls_hidden": 0,
            "reasoning_chars_hidden": 0,
            "tool_only_steps_dropped": 0,
            "sub_agent_msgs_excluded": 0,
            "parse_errors": 0,
        },
    }


# --------------------------------------------------------------------------- #
# Markdown (subset) -> HTML
# --------------------------------------------------------------------------- #

_LINK_RE = re.compile(r"\[([^\]\n]+)\]\(([^)\s]+)\)")
_SAFE_URL_RE = re.compile(r"^(https?|mailto):", re.I)


def _inline(raw: str) -> str:
    """Escape then render a safe markdown subset: code, bold, italic, del, links."""
    text = html.escape(raw, quote=False)
    spans: list[str] = []

    def _code(m: re.Match) -> str:
        spans.append(f"<code>{m.group(1)}</code>")
        return f"\x00{len(spans) - 1}\x00"

    text = re.sub(r"`([^`\n]+)`", _code, text)
    text = re.sub(r"\*\*([^*\n]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?!\w)", r"<em>\1</em>", text)
    text = re.sub(r"~~([^~\n]+)~~", r"<del>\1</del>", text)

    def _link(m: re.Match) -> str:
        label, url = m.group(1), m.group(2)
        if _SAFE_URL_RE.match(url):
            return f'<a href="{url}" rel="noreferrer">{label}</a>'
        return f"<span class='path'>{label}</span>"  # local paths: text only

    text = _LINK_RE.sub(_link, text)
    for i, span in enumerate(spans):
        text = text.replace(f"\x00{i}\x00", span)
    return text


_TABLE_SEP_RE = re.compile(r"^\s*\|(\s*:?-{2,}:?\s*\|)+\s*$")


def _is_table_sep(line: str) -> bool:
    return bool(_TABLE_SEP_RE.match(line))


def _table_cells(line: str) -> list[str]:
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.replace("\\|", "|").strip() for c in re.split(r"(?<!\\)\|", line)]


def md_to_html(text: str) -> str:
    """Block-level renderer: fences, headings, hr, quotes, lists, tables, paragraphs."""
    lines = text.split("\n")
    out: list[str] = []
    i, n = 0, len(lines)

    while i < n:
        line = lines[i]

        if line.strip().startswith("```"):
            lang = line.strip()[3:].strip()
            buf, i = [], i + 1
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1  # closing fence (or EOF)
            cls = f' class="lang-{html.escape(lang)}"' if lang else ""
            out.append(f"<pre><code{cls}>{html.escape(chr(10).join(buf))}</code></pre>")
            continue

        if not line.strip():
            i += 1
            continue

        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            lvl = min(len(m.group(1)) + 1, 6)  # demote: chat text, not a doc title
            out.append(f"<h{lvl}>{_inline(m.group(2))}</h{lvl}>")
            i += 1
            continue

        if re.match(r"^\s*(-{3,}|\*{3,}|_{3,})\s*$", line):
            out.append("<hr>")
            i += 1
            continue

        if line.lstrip().startswith(">"):
            buf = []
            while i < n and lines[i].lstrip().startswith(">"):
                buf.append(lines[i].lstrip()[1:].lstrip())
                i += 1
            out.append(f"<blockquote>{_inline(chr(10).join(buf))}</blockquote>")
            continue

        if line.lstrip().startswith("|") and i + 1 < n and _is_table_sep(lines[i + 1]):
            header = _table_cells(line)
            i += 2
            body = []
            while i < n and lines[i].lstrip().startswith("|"):
                body.append(_table_cells(lines[i]))
                i += 1
            th = "".join(f"<th>{_inline(c)}</th>" for c in header)
            trs = "".join(
                "<tr>" + "".join(f"<td>{_inline(c)}</td>" for c in row) + "</tr>"
                for row in body
            )
            out.append(f"<table><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table>")
            continue

        if re.match(r"^\s*[-*+]\s+", line):
            items = []
            while i < n and re.match(r"^\s*[-*+]\s+", lines[i]):
                items.append(re.sub(r"^\s*[-*+]\s+", "", lines[i]))
                i += 1
            out.append("<ul>" + "".join(f"<li>{_inline(x)}</li>" for x in items) + "</ul>")
            continue

        if re.match(r"^\s*\d+\.\s+", line):
            items = []
            while i < n and re.match(r"^\s*\d+\.\s+", lines[i]):
                items.append(re.sub(r"^\s*\d+\.\s+", "", lines[i]))
                i += 1
            out.append("<ol>" + "".join(f"<li>{_inline(x)}</li>" for x in items) + "</ol>")
            continue

        buf = []
        while i < n and lines[i].strip() and not re.match(
            r"^(#{1,6}\s|\s*[-*+]\s|\s*\d+\.\s|\s*>|\s*```)", lines[i]
        ):
            if lines[i].lstrip().startswith("|") and i + 1 < n and _is_table_sep(lines[i + 1]):
                break
            buf.append(lines[i])
            i += 1
        if buf:
            out.append(f"<p>{_inline(chr(10).join(buf)).replace(chr(10), '<br>')}</p>")
        else:  # safety: never spin on an unmatched line
            out.append(f"<p>{_inline(line)}</p>")
            i += 1

    return "\n".join(out)


# --------------------------------------------------------------------------- #
# HTML assembly
# --------------------------------------------------------------------------- #

CSS = """
:root {
  color-scheme: light dark;
  --bg: #f4f5f7;            /* transcript background */
  --focus: #e3edfd;         /* focus color (mini-map hover surface) */
  --panel-border: #d8dbe0;
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #16181c; --focus: #1d2c46; --panel-border: #33383f; }
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 0 1rem 4rem;
  font: 15px/1.55 system-ui, -apple-system, "Segoe UI", sans-serif;
  background: #f4f5f7; color: #1c1f23;
}
/* keep the collapsed mini-map column from covering text on narrow viewports
   (above this width the centered 940px column already clears the dots) */
@media (max-width: 1060px) { body.has-minimap { padding-left: 3.4rem; } }
@media (prefers-color-scheme: dark) {
  body { background: #16181c; color: #e6e8ea; }
  .bubble.agent { background: #1f2329; border-color: #33383f; color: #e6e8ea; }
  .bubble.user { background: #24344d; border-color: #35507c; color: #e9eefb; }
  header, footer { border-color: #33383f !important; }
  pre, table, code { border-color: #33383f !important; }
  .body th, .body td { border-color: #444a52; }
  .body blockquote { color: #b9c0c9; border-left-color: #44536a; }
  .body a { color: #8ab0ff; }
  .sid { color: #9aa3ad; background: rgba(255,255,255,.05); border-color: rgba(255,255,255,.16); }
  .sid:hover { background: rgba(255,255,255,.12); color: #d7dbe0; }
  .chip { color: #c6cbd2; background: rgba(255,255,255,.05); border-color: rgba(255,255,255,.13); }
  .metric { background: rgba(255,255,255,.04); border-color: rgba(255,255,255,.12); }
  .more summary { color: #9aa3ad; border-color: rgba(255,255,255,.3); }
  .more summary:hover { background: rgba(255,255,255,.08); }
  .more-body { color: #9aa3ad; background: rgba(255,255,255,.04); border-color: rgba(255,255,255,.12); }
}
header {
  max-width: 940px; margin: 0 auto; padding: 1.15rem 0 .9rem;
  border-bottom: 2px solid #d8dbe0;
}
.head-top { display: flex; align-items: baseline; justify-content: space-between; gap: 1rem; }
h1 {
  font-size: 1.22rem; margin: 0; line-height: 1.3; min-width: 0;
  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical;
  overflow: hidden;
}
.sid {
  flex: 0 0 auto; display: inline-flex; align-items: center; gap: .5em;
  font-family: ui-monospace, Consolas, monospace; font-size: .76rem;
  color: #5b6470; background: rgba(127,127,127,.1);
  border: 1px solid rgba(127,127,127,.22); border-radius: 999px;
  padding: .22rem .65rem; cursor: pointer;
}
.sid:hover { background: rgba(127,127,127,.2); color: #3d444d; }
.sid .sid-act { font-size: .64rem; text-transform: uppercase; letter-spacing: .05em; opacity: .65; }
.sid.copied { color: #1f7a3d; border-color: rgba(31,122,61,.45); }
.sid.failed { color: #b3261e; border-color: rgba(179,38,30,.45); }
.chips { display: flex; flex-wrap: wrap; gap: .4rem; margin-top: .6rem; }
.chip {
  display: inline-flex; align-items: center; gap: .45em; max-width: 100%;
  font-size: .76rem; color: #3d444d;
  background: rgba(127,127,127,.09); border: 1px solid rgba(127,127,127,.18);
  border-radius: 999px; padding: .18rem .65rem; overflow: hidden;
}
.chip .k {
  font-size: .62rem; font-weight: 700; text-transform: uppercase;
  letter-spacing: .06em; opacity: .55; flex: 0 0 auto;
}
.chip .v { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.chip code { background: none; padding: 0; font-size: .74rem; }
.metrics { display: flex; flex-wrap: wrap; gap: .45rem; margin-top: .7rem; align-items: stretch; }
.metric {
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  min-width: 5.4rem; padding: .35rem .75rem;
  background: rgba(127,127,127,.07); border: 1px solid rgba(127,127,127,.16);
  border-radius: 10px;
}
.metric b { font-size: 1.02rem; font-weight: 650; font-variant-numeric: tabular-nums; line-height: 1.2; }
.metric span {
  font-size: .62rem; text-transform: uppercase; letter-spacing: .05em;
  color: #7a828d; margin-top: .1rem;
}
.more { display: flex; flex-direction: column; }
.more[open] { flex: 1 0 100%; }
.more summary {
  list-style: none; cursor: pointer; align-self: center;
  font-size: .7rem; text-transform: uppercase; letter-spacing: .05em; color: #7a828d;
  border: 1px dashed rgba(127,127,127,.35); border-radius: 999px; padding: .35rem .8rem;
}
.more summary::-webkit-details-marker { display: none; }
.more summary::after { content: " ▸"; }
.more[open] summary::after { content: " ▾"; }
.more summary:hover { background: rgba(127,127,127,.1); }
.more-body {
  margin-top: .45rem; font-size: .74rem; color: #5b6470;
  background: rgba(127,127,127,.06); border: 1px solid rgba(127,127,127,.14);
  border-radius: 8px; padding: .45rem .75rem;
}
main { max-width: 940px; margin: 0 auto; }
.turn { margin-top: 1.6rem; }
.turn-head { font-size: .72rem; text-transform: uppercase; letter-spacing: .06em; color: #7a828d; margin-bottom: .4rem; }
.bubble {
  border: 1px solid #d8dbe0; border-radius: 12px; padding: .8rem 1rem; margin-bottom: .6rem;
  background: #fff; color: #1c1f23; box-shadow: 0 1px 2px rgba(0,0,0,.04);
  overflow-wrap: anywhere;
}
.bubble.user {
  background: #e7effc; border-color: #c3d6f5; color: #16233b; margin-left: 3rem;
  /* the active user request pins to the top of the viewport while its turn
     would otherwise scroll it off — and RELEASES as soon as the next turn's
     request becomes visible in the same viewport (JS adds .releasing/.released) */
  position: sticky; top: 0; z-index: 4;
  transition: opacity .14s ease;
}
.bubble.user.releasing { opacity: 0; }      /* fading out, still pinned */
.bubble.user.released { position: static; } /* unpinned (its flow spot is off-screen) */
.bubble.agent { margin-right: 3rem; }
@media (max-width: 640px) { .bubble.user, .bubble.agent { margin: 0 0 .6rem; } }
.who { font-size: .72rem; font-weight: 600; text-transform: uppercase; letter-spacing: .05em; opacity: .65; margin-bottom: .35rem; }
.body > :first-child { margin-top: 0; } .body > :last-child { margin-bottom: 0; }
.body p { margin: .5rem 0; }
.body ul, .body ol { margin: .5rem 0; padding-left: 1.4rem; }
.body li { margin: .2rem 0; }
.body pre {
  background: #0f1115; color: #e6edf3; padding: .7rem .9rem; border-radius: 8px;
  overflow-x: auto; font: 13px/1.45 ui-monospace, Consolas, monospace; margin: .6rem 0;
}
.body code { font: 13px ui-monospace, Consolas, monospace; background: rgba(127,127,127,.16); padding: 0 .3em; border-radius: 4px; }
.body pre code { background: none; padding: 0; }
.body blockquote { margin: .6rem 0; padding: .2rem .9rem; border-left: 3px solid #b7c3d4; color: #4a525c; }
.body table { border-collapse: collapse; margin: .7rem 0; font-size: .9em; width: 100%; }
.body th, .body td { border: 1px solid #cfd4da; padding: .35rem .55rem; text-align: left; vertical-align: top; }
.body th { background: rgba(127,127,127,.1); }
.body a { color: #2457c5; }
.body .path { font: 13px ui-monospace, Consolas, monospace; opacity: .85; }
.body h2, .body h3, .body h4 { margin: .9rem 0 .35rem; font-size: 1.02em; }
.body hr { border: none; border-top: 1px solid #d8dbe0; margin: .9rem 0; }
.tools { font-size: .72rem; color: #8a919b; margin-top: .35rem; }
.empty { font-style: italic; opacity: .6; }
footer { max-width: 940px; margin: 2.5rem auto 0; padding-top: .8rem; border-top: 1px solid #d8dbe0; font-size: .72rem; color: #7a828d; }

/* ---- intermediate-step collapse ---- */
.steps-toggle {
  display: inline-flex; align-items: center; gap: .3rem;
  font-family: inherit; font-size: .73rem; font-weight: 600;
  color: #4a525c; background: rgba(127,127,127,.12);
  border: 1px solid rgba(127,127,127,.28); border-radius: 999px;
  padding: .2rem .7rem; cursor: pointer; margin-bottom: .55rem;
}
.steps-toggle:hover { background: rgba(127,127,127,.26); }
.steps {
  border-left: 2px solid rgba(127,127,127,.35); padding-left: .75rem;
  margin: .2rem 0 .7rem; opacity: .88;
}
.steps[hidden] { display: none; }

/* ---- sticky active user request: implemented natively as
   `position: sticky` on .bubble.user (see above) — no proxy element, no JS,
   no compositor-layer dependency; it pins only when the request would
   otherwise scroll off the top and releases at its turn-section boundary ---- */

/* ---- mini-map (user requests) ----
   symbol states (exactly one active at a time):
     inactive : small  + gray
     focused  : large  + gray   (same color as inactive, size of active)
     active   : large  + accent (same size as focused, different color)   */
.minimap {
  position: fixed; left: .5rem; top: 50%; transform: translateY(-50%); z-index: 50;
  width: 2rem; transition: width .2s ease;
}
.minimap:hover, .minimap:focus-within { width: 24rem; }
.mm-list {
  list-style: none; margin: 0; padding: .32rem .85rem .32rem .3rem;
  display: flex; flex-direction: column; gap: .28rem;
  background: var(--bg);
  border-radius: 10px; box-shadow: none;
  width: 100%; overflow: hidden;
  max-height: 13.16rem;  /* border-box: 12.52rem content = 10 rows (1rem) + 9 gaps (.28rem), + .64rem padding */
  transition: background .15s ease, box-shadow .15s ease;
}
.minimap:hover .mm-list, .minimap:focus-within .mm-list {
  background: var(--focus);
  box-shadow: 0 3px 12px rgba(0,0,0,.15);
}
/* custom scrollbar: the strip never scrolls natively, so no native scrollbar
   can render in any viewer and no arrow buttons can ever appear */
.mm-scroll {
  position: absolute; right: .28rem; top: .32rem; bottom: .32rem; width: 5px;
  border-radius: 999px; background: rgba(128,128,128,.16);
  opacity: 0; transition: opacity .1s ease; pointer-events: none;
}
.minimap:hover .mm-scroll, .minimap:focus-within .mm-scroll {
  opacity: 1; transition: opacity .15s ease .25s;  /* appears after the expansion */
}
.mm-thumb {
  position: absolute; left: 0; width: 100%; min-height: 1.2rem;
  border-radius: 999px; background: #9aa3ad; cursor: grab; pointer-events: auto;
}
.mm-row { display: flex; align-items: center; gap: .42rem; min-width: 0; height: 1rem; }
.mm-dot {
  width: .42rem; height: .42rem; min-width: .42rem; padding: 0;
  border: none; border-radius: 50%; background: #9aa3ad; cursor: pointer;
  transition: width .12s ease, height .12s ease, min-width .12s ease,
              background .12s ease, box-shadow .12s ease;
}
.mm-row:hover .mm-dot {           /* focused: large, same gray as inactive */
  width: .62rem; height: .62rem; min-width: .62rem;
  background: #9aa3ad;
}
.mm-row.active .mm-dot {          /* active: same size as focused, accent color
                                      (rule order keeps hover from recoloring it) */
  width: .62rem; height: .62rem; min-width: .62rem;
  background: #2457c5;
  box-shadow: 0 0 0 2.5px rgba(36,87,197,.3);
}
.mm-label {
  flex: 1 1 auto; min-width: 0; text-align: left;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  font-family: inherit; font-size: .72rem; line-height: 1.25; color: #3d444d;
  background: none; border: none; border-radius: 5px;
  padding: .05rem .3rem; cursor: pointer; opacity: 0; transition: opacity .15s;
}
.minimap:hover .mm-label, .minimap:focus-within .mm-label { opacity: 1; }
.mm-row.active .mm-label { color: #1f4fb8; font-weight: 650; }
.mm-row:hover .mm-label { background: rgba(36,87,197,.1); }
@media (prefers-color-scheme: dark) {
  .mm-label { color: #c6cbd2; }
  .mm-row.active .mm-label { color: #8ab0ff; }
  .mm-row:hover .mm-label { background: rgba(138,176,255,.14); }
  .mm-row:hover .mm-dot, .mm-row.active .mm-dot { background: #9aa3ad; }
  .mm-row.active .mm-dot { background: #8ab0ff; box-shadow: 0 0 0 2.5px rgba(138,176,255,.3); }
  .steps { border-left-color: rgba(255,255,255,.22); }
  .steps-toggle { color: #b9c0c9; background: rgba(255,255,255,.06); border-color: rgba(255,255,255,.18); }
}
@media print {
  body { background: #fff; }
  .bubble { box-shadow: none; break-inside: avoid; }
  .turn { break-inside: avoid; }
  .minimap, .steps-toggle { display: none !important; }
  .bubble.user { position: static !important; opacity: 1 !important; }
  .steps[hidden] { display: block !important; }  /* print the full transcript */
}
"""


def _fmt_ts(ts: str | None) -> str:
    if not ts:
        return ""
    try:
        dt = datetime.fromisoformat(str(ts).replace("Z", "+00:00")).astimezone()
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    except ValueError:
        return str(ts)


def _fmt_duration(ms: int) -> str:
    s = ms // 1000
    if s < 1:
        return "instant"
    if s < 60:
        return f"{s}s"
    m, sec = divmod(s, 60)
    if m < 60:
        return f"{m}m {sec:02d}s"
    h, m = divmod(m, 60)
    return f"{h}h {m:02d}m"


def _chip(key: str, value_html: str) -> str:
    return (
        f'<span class="chip"><span class="k">{key}</span>'
        f'<span class="v">{value_html}</span></span>'
    )


def _metric(value, label: str) -> str:
    return f'<div class="metric"><b>{value}</b><span>{label}</span></div>'


def render_html(meta: dict) -> str:
    esc = html.escape
    turns: list[dict] = meta["turns"]
    stats = meta["stats"]
    summary = meta.get("summary") or f"Copilot session {meta['session_id'][:8]}"
    parts_total = sum(len(t["assistant"]) for t in turns)
    total_steps = sum(t.get("steps") or 0 for t in turns)
    excluded = stats["sub_agent_msgs_excluded"]

    # header: identity chips + labeled metric boxes; verbose omission counters
    # (reasoning chars, tool-only drops, exclusions) live behind a details toggle
    sid = str(meta["session_id"])
    chips = [_chip("source", esc(str(meta["source"])))]
    if meta.get("model"):
        chips.append(_chip("model", esc(str(meta["model"]))))
    if meta.get("started"):
        started = str(meta["started"])
        chips.append(
            _chip("started", f'<time data-iso="{esc(started)}">{esc(_fmt_ts(started))}</time>')
        )
    if meta.get("repository"):
        branch = f"@{esc(str(meta['branch']))}" if meta.get("branch") else ""
        chips.append(_chip("repo", f"<code>{esc(str(meta['repository']))}{branch}</code>"))
    elif meta.get("cwd"):
        chips.append(_chip("cwd", f"<code>{esc(str(meta['cwd']))}</code>"))

    metrics = [
        _metric(len(turns), "turns"),
        _metric(parts_total, "responses"),
    ]
    if total_steps:
        metrics.append(_metric(total_steps, "steps"))
    total_ms = sum(t.get("duration_ms") or 0 for t in turns)
    if total_ms:
        metrics.append(_metric(_fmt_duration(total_ms), "agent time"))
    # the curated DB fallback stores no tool/reasoning telemetry — omit rather
    # than display misleading zeros
    if meta["source"] == "events":
        metrics.append(_metric(stats["tool_calls_hidden"], "tools hidden"))

    verbose: list[str] = []
    if meta["source"] == "events":
        if stats["reasoning_chars_hidden"]:
            verbose.append(f"{stats['reasoning_chars_hidden']:,} chars of reasoning hidden")
        if stats["tool_only_steps_dropped"]:
            verbose.append(f"{stats['tool_only_steps_dropped']} tool-only steps dropped")
        if excluded:
            verbose.append(f"{excluded} sub-agent messages excluded")
        if stats["parse_errors"]:
            verbose.append(f"{stats['parse_errors']} unparseable events skipped")
    more_html = ""
    if verbose:
        more_html = (
            '<details class="more"><summary>details</summary>'
            f'<div class="more-body">{" · ".join(verbose)}</div></details>'
        )

    body: list[str] = []
    mm_rows: list[str] = []
    for n, t in enumerate(turns, 1):
        iso = str(t["ts"]) if t.get("ts") else ""
        time_html = (
            f'<time data-iso="{esc(iso)}">{esc(_fmt_ts(iso))}</time>' if iso else ""
        )
        head = f"Turn {n}" + (f" · {time_html}" if time_html else "")
        plain = (
            re.sub(r"\s+", " ", t["user"]).strip()
            or "(no text: attachment or continuation)"
        )
        user_html = (
            md_to_html(t["user"])
            if t["user"]
            else "<p class='empty'>(no text: attachment or continuation)</p>"
        )
        for att in t["attachments"]:
            user_html += f"<p class='empty'>attachment: {esc(att)}</p>"
        body.append(f'<section class="turn" id="turn-{n}"><div class="turn-head">{head}</div>')
        body.append(
            f'<div class="bubble user" id="req-{n}"><div class="who">User</div>'
            f'<div class="body">{user_html}</div></div>'
        )

        # Collapse every intermediate step; the final block (the agent's brief
        # for the whole response) stays open by default.
        blocks = t["assistant"]
        toggle_html = steps_html = ""
        if not blocks:
            final_html = "<p class='empty'>(no recorded response)</p>"
        elif len(blocks) == 1:
            final_html = md_to_html(blocks[0])
        else:
            k = len(blocks) - 1
            word = "step" if k == 1 else "steps"
            toggle_html = (
                f'<button type="button" class="steps-toggle" '
                f'data-collapsed="▸ Show {k} intermediate {word}" '
                f'data-expanded="▼ Hide {k} intermediate {word}">'
                f'▸ Show {k} intermediate {word}</button>'
            )
            steps_html = (
                '<div class="steps" hidden>'
                + "<hr>".join(md_to_html(b) for b in blocks[:-1])
                + "</div>"
            )
            final_html = md_to_html(blocks[-1])

        note: list[str] = []
        steps = t.get("steps")
        if steps:
            note.append(f"{steps} step{'s' if steps != 1 else ''}")
        if t.get("duration_ms") is not None:
            note.append(_fmt_duration(t["duration_ms"]))
        if t["tools"]:
            note.append(f"{t['tools']} tool call{'s' if t['tools'] > 1 else ''} hidden")
        if t["reasoning"]:
            note.append(f"{t['reasoning']:,} reasoning chars hidden")
        tools_html = (
            f"<div class='tools'>{esc('; '.join(note))}</div>" if note else ""
        )
        body.append(
            f'<div class="bubble agent"><div class="who">Copilot</div>'
            f'<div class="body">{toggle_html}{steps_html}{final_html}</div>'
            f"{tools_html}</div></section>"
        )

        active_cls = " active" if n == 1 else ""
        mm_rows.append(
            f'<li class="mm-row{active_cls}" data-target="req-{n}" '
            f'data-plain="{esc(plain)}" title="{esc(plain)}">'
            f'<button type="button" class="mm-dot" data-target="req-{n}" '
            f'aria-label="Go to turn {n}"></button>'
            f'<button type="button" class="mm-label" data-target="req-{n}" '
            f'tabindex="-1">{esc(plain)}</button></li>'
        )

    minimap_html = ""
    body_cls = ""
    if len(turns) >= 2:
        body_cls = ' class="has-minimap"'
        minimap_html = (
            '<nav class="minimap" id="minimap" aria-label="User requests mini-map">'
            f'<ol class="mm-list">{"".join(mm_rows)}</ol>'
            '<div class="mm-scroll" aria-hidden="true"><div class="mm-thumb"></div></div></nav>'
        )
    exported_dt = datetime.now().astimezone()
    exported_iso = exported_dt.isoformat()
    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(summary)}</title>
<style>{CSS}</style></head>
<body{body_cls}>
<header>
  <div class="head-top">
    <h1>{esc(summary)}</h1>
    <button type="button" class="sid" data-copy="{esc(sid)}" title="Copy full session id">
      <span class="sid-id">{esc(sid[:8])}</span><span class="sid-act">copy</span>
    </button>
  </div>
  <div class="chips">{''.join(chips)}</div>
  <div class="metrics">{''.join(metrics)}{more_html}</div>
</header>
<main>
{chr(10).join(body)}
</main>
{minimap_html}
<footer>Exported <time data-iso="{esc(exported_iso)}">{esc(_fmt_ts(exported_iso))}</time>
by scripts/export-copilot-transcript.py — user turns and visible agent responses only;
thinking, tool invocations and sub-agent threads omitted by construction.</footer>
{JS}
</body></html>
"""


JS = r"""
<script>
(function () {
  var rows = Array.prototype.slice.call(document.querySelectorAll('.mm-row'));
  var targets = rows.map(function (r) { return document.getElementById(r.dataset.target); });
  // pick up the server-rendered active marker so the first setActive() that
  // lands on a different row removes it (otherwise a refresh that restores the
  // scroll away from the top leaves TWO active symbols: row 1 + the computed one)
  var active = -1;
  for (var k = 0; k < rows.length; k++) {
    if (rows[k].classList.contains('active')) { active = k; break; }
  }
  // click selection: a symbol/label click pins its request as active until the
  // user really interacts again (a click on the LAST symbol must not be
  // overridden by an earlier request that is still visible in the same viewport)
  var selected = -1;
  var flying = false, flyTimer = 0;  // goTo smooth-scroll flight window
  var mmUserScroll = false, lastFollowed = -1;  // mini-map: user strip scroll beats follow

  function setActive(i) {
    if (i < 0 || !rows[i]) return;
    // reconcile in one pass on every update: exactly one active row, always —
    // this also sweeps stray markers (e.g. the server-rendered class on row 1
    // after a refresh whose scroll position restored away from the top)
    for (var j = 0; j < rows.length; j++) {
      var has = rows[j].classList.contains('active');
      if (j === i) { if (!has) rows[j].classList.add('active'); }
      else if (has) { rows[j].classList.remove('active'); }
    }
    active = i;
    // slide the mini-map strip to the active symbol — but never fight the
    // user's own strip scrolling: follow resumes when the active turn changes
    var strip = rows[i].parentNode;
    if (strip && strip.scrollHeight > strip.clientHeight) {
      if (i !== lastFollowed) { mmUserScroll = false; lastFollowed = i; }
      if (!mmUserScroll) {
        var lr = strip.getBoundingClientRect(), rr = rows[i].getBoundingClientRect();
        if (rr.top < lr.top) { strip.scrollTop -= (lr.top - rr.top); }
        else if (rr.bottom > lr.bottom) { strip.scrollTop += (rr.bottom - lr.bottom); }
      }
    }
  }

  // Active rule, in precedence order:
  //   1. click selection — owns the active state until real user input
  //      (wheel/touch/key/mousedown), so it survives the whole smooth-scroll
  //      flight even while the target request is still off screen, and it beats
  //      both rules below when several requests share the viewport
  //   2. document tail: the LAST visible request wins — a short final response
  //      keeps an earlier request on screen at the bottom, but the reader is on
  //      the final turn
  //   3. topmost visible request; if none is visible, the last one scrolled past
  // A pinned request releases as soon as the NEXT turn's request is visible in
  // the same viewport (the spec's "sticky only until the next consecutive turn
  // is visible"). Two-phase: fade out while still pinned, then unpin — at that
  // moment its flow position is far above the viewport, so the jump is invisible.
  function setReleased(el, shouldRelease) {
    if (!el) return;
    var rel = el.classList.contains('released');
    var fading = el.classList.contains('releasing');
    if (shouldRelease && !rel && !fading) {
      el.classList.add('releasing');
      el._releaseTimer = setTimeout(function () {
        el.classList.remove('releasing');
        el.classList.add('released');
      }, 150);
    } else if (!shouldRelease && (rel || fading)) {
      clearTimeout(el._releaseTimer);
      el.classList.remove('releasing', 'released');  // re-pins (fades back in)
    }
  }

  function update() {
    if (!targets.length) return;
    var vh = window.innerHeight;
    var firstVisible = -1, lastAbove = -1, lastVisible = -1;
    var visible = [];
    for (var i = 0; i < targets.length; i++) {
      var el = targets[i];
      if (!el) { visible.push(false); continue; }
      var r = el.getBoundingClientRect();
      var vis = r.bottom > 0 && r.top < vh;
      visible.push(vis);
      if (vis) {
        if (firstVisible < 0) firstVisible = i;
        lastVisible = i;
      } else if (r.bottom <= 0) {
        lastAbove = i;
      }
    }
    for (var j = 0; j < targets.length - 1; j++) {
      setReleased(targets[j], !!visible[j + 1]);
    }
    var idx;
    if (selected >= 0) {
      idx = selected;
    } else {
      idx = firstVisible >= 0 ? firstVisible : (lastAbove >= 0 ? lastAbove : 0);
      var doc = document.documentElement;
      var atEnd = doc.scrollHeight - (window.pageYOffset + doc.clientHeight) <= 2;
      if (atEnd && doc.scrollHeight > doc.clientHeight + 2 && lastVisible >= 0) {
        idx = lastVisible;
      }
    }
    setActive(idx);
  }

  // rAF keeps it smooth when frames run; the synchronous throttle and the
  // interval keep the active symbol correct even when rAF is paused
  // (background/occluded viewers) — belt and braces against dead scroll handling.
  var ticking = false, lastExec = 0;
  function onScroll() {
    // a scroll that is neither user input nor a goTo flight (scrollbar drag)
    // abandons the click selection
    if (selected >= 0 && !flying) clearSelection();
    var now = Date.now();
    if (now - lastExec >= 100) { lastExec = now; update(); }
    if (!ticking) {
      ticking = true;
      requestAnimationFrame(function () { update(); ticking = false; });
    }
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', onScroll);
  window.addEventListener('pageshow', update);
  setInterval(update, 500);

  // any real user input abandons the click selection and returns control to
  // the scroll rules (the wheel/touch/key listeners fire BEFORE the minimap's
  // own click handler re-selects, so clicking still works)
  function clearSelection() { selected = -1; }
  window.addEventListener('wheel', clearSelection, { passive: true });
  window.addEventListener('touchstart', clearSelection, { passive: true });
  window.addEventListener('keydown', clearSelection);
  document.addEventListener('mousedown', clearSelection);

  function goTo(i) {
    var el = targets[i];
    if (!el) return;
    selected = i;   // the clicked request owns the active state after landing
    flying = true;
    clearTimeout(flyTimer);
    flyTimer = setTimeout(function () { flying = false; }, 5000);
    window.addEventListener('scrollend', function landed() {
      window.removeEventListener('scrollend', landed);
      flying = false;
    });
    var y = el.getBoundingClientRect().top + window.pageYOffset - 8;
    window.scrollTo({ top: Math.max(0, y), behavior: 'smooth' });
  }

  var minimap = document.getElementById('minimap');
  if (minimap) {
    minimap.addEventListener('click', function (e) {
      var t = e.target.closest('[data-target]');
      if (!t) return;
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].dataset.target === t.dataset.target) { goTo(i); return; }
      }
    });
  }

  // custom scrollbar: the strip never scrolls natively (overflow: hidden), so
  // this thumb is the only scrollbar — wheel over the mini-map scrolls the
  // strip, the thumb drags, and no arrow buttons can ever render
  if (minimap) {
    var strip = minimap.querySelector('.mm-list');
    var thumb = minimap.querySelector('.mm-thumb');
    var syncThumb = function () {
      if (!strip || !thumb) return;
      var h = strip.clientHeight, sh = strip.scrollHeight;
      var holder = thumb.parentNode;
      if (sh <= h + 1) { holder.style.display = 'none'; return; }
      holder.style.display = 'block';
      var hh = holder.clientHeight;
      var th = Math.max(Math.round(hh * h / sh), 19);
      if (th > hh) { th = hh; }
      thumb.style.height = th + 'px';
      thumb.style.top = Math.round((hh - th) * strip.scrollTop / (sh - h)) + 'px';
    };
    if (strip) {
      strip.addEventListener('scroll', syncThumb);
      window.addEventListener('resize', syncThumb);
      minimap.addEventListener('wheel', function (e) {
        if (strip.scrollHeight <= strip.clientHeight) return;
        e.preventDefault();
        mmUserScroll = true;
        strip.scrollTop += e.deltaY;
      }, { passive: false });
      syncThumb();
    }
    if (thumb && strip) {
      var dragging = false, dragY = 0, dragTop = 0;
      thumb.addEventListener('mousedown', function (e) {
        dragging = true; dragY = e.clientY; dragTop = strip.scrollTop;
        mmUserScroll = true;
        e.preventDefault();
      });
      document.addEventListener('mousemove', function (e) {
        if (!dragging) return;
        var h = strip.clientHeight, sh = strip.scrollHeight;
        var th = thumb.offsetHeight, hh = thumb.parentNode.clientHeight;
        if (sh <= h) return;
        strip.scrollTop = dragTop + (e.clientY - dragY) * (sh - h) / Math.max(hh - th, 1);
      });
      document.addEventListener('mouseup', function () { dragging = false; });
    }
  }

  document.addEventListener('click', function (e) {
    var b = e.target.closest('.steps-toggle');
    if (!b) return;
    var bubble = b.closest('.bubble');
    var steps = bubble && bubble.querySelector('.steps');
    if (!steps) return;
    if (steps.hasAttribute('hidden')) {
      steps.removeAttribute('hidden');
      b.textContent = b.dataset.expanded;
    } else {
      steps.setAttribute('hidden', '');
      b.textContent = b.dataset.collapsed;
    }
  });

  document.addEventListener('click', function (e) {
    var b = e.target.closest('.sid');
    if (!b) return;
    var act = b.querySelector('.sid-act');
    var text = b.dataset.copy || '';
    var show = function (cls, msg) {
      b.classList.remove('copied', 'failed');
      b.classList.add(cls);
      if (act) act.textContent = msg;
      setTimeout(function () {
        b.classList.remove(cls);
        if (act) act.textContent = 'copy';
      }, 1500);
    };
    var fallback = function () {
      try {
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.style.cssText = 'position:fixed;opacity:0';
        document.body.appendChild(ta);
        ta.select();
        var ok = document.execCommand('copy');
        document.body.removeChild(ta);
        if (ok) show('copied', 'copied ✓'); else show('failed', 'copy failed');
      } catch (err) { show('failed', 'copy failed'); }
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(
        function () { show('copied', 'copied ✓'); },
        fallback
      );
    } else { fallback(); }
  });

  try {
    var fmt = new Intl.DateTimeFormat(undefined, {
      year: 'numeric', month: 'short', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit'
    });
    Array.prototype.forEach.call(document.querySelectorAll('time[data-iso]'), function (el) {
      var d = new Date(el.dataset.iso);
      if (!isNaN(d)) el.textContent = fmt.format(d);
    });
  } catch (err) { /* keep export-time fallback formatting */ }

  update();
})();
</script>
"""


# --------------------------------------------------------------------------- #
# --list
# --------------------------------------------------------------------------- #

def list_sessions(limit: int) -> None:
    entries: dict[str, dict] = {}
    if STATE_DIR.is_dir():
        for d in STATE_DIR.iterdir():
            f = d / "events.jsonl"
            if d.is_dir() and f.is_file():
                entries[d.name] = {
                    "source": "events",
                    "updated": datetime.fromtimestamp(f.stat().st_mtime),
                }
    if STORE_DB.exists():
        con = sqlite3.connect(f"file:{STORE_DB}?mode=ro", uri=True)
        try:
            for sid, summary, updated in con.execute(
                "SELECT id, summary, updated_at FROM sessions ORDER BY updated_at DESC LIMIT 200"
            ):
                e = entries.setdefault(sid, {"source": "db", "summary": summary})
                e["summary"] = summary
                e["updated"] = updated
        finally:
            con.close()
    rows = sorted(entries.items(), key=lambda kv: str(kv[1].get("updated") or ""), reverse=True)
    print(f"{'session':<38} {'source':<8} {'updated':<21} summary")
    for sid, e in rows[:limit]:
        has_events = (STATE_DIR / sid / "events.jsonl").exists()
        src = "both" if has_events and e.get("summary") else ("events" if has_events else "db")
        upd = e.get("updated")
        upd = upd.strftime("%Y-%m-%d %H:%M") if isinstance(upd, datetime) else str(upd or "")[:16]
        summary = (e.get("summary") or "").replace("\n", " ")[:60]
        print(f"{sid:<38} {src:<8} {upd:<21} {summary}")


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #

def main() -> int:
    ap = argparse.ArgumentParser(description="Export a Copilot session transcript to HTML (turns only).")
    ap.add_argument("--session", help="session id, session folder, or path to events.jsonl (default: newest)")
    ap.add_argument("--out", help="output .html path (default: ./copilot-transcript-<id8>.html)")
    ap.add_argument("--source", choices=("auto", "events", "db"), default="auto")
    ap.add_argument("--final-only", action="store_true", help="keep only the last response block per turn (DB semantics)")
    ap.add_argument("--include-sub-agents", action="store_true", help="also render task-tool sub-agent threads")
    ap.add_argument("--list", action="store_true", help="list recent sessions and exit")
    ap.add_argument("--list-limit", type=int, default=15)
    ap.add_argument("--open", action="store_true", help="open the result in the default browser")
    args = ap.parse_args()

    if args.list:
        list_sessions(args.list_limit)
        return 0

    session_dir = resolve_session_dir(args.session)
    events_available = session_dir is not None and (session_dir / "events.jsonl").exists()
    session_id = session_dir.name if session_dir else (args.session or "")

    source = args.source
    if source == "auto":
        source = "events" if events_available else "db"
    if source == "events" and not events_available:
        raise SystemExit(
            f"error: no events.jsonl for session {session_id or '(newest)'} under {STATE_DIR}\n"
            "       use --source db, or pick another session with --list"
        )
    if source == "db" and not session_id:
        raise SystemExit("error: --source db needs --session <id>")

    if source == "events":
        meta = extract_from_events(session_dir, args.include_sub_agents, args.final_only)
    else:
        meta = extract_from_db(session_id, args.final_only)
    meta["session_id"] = session_id or meta.get("session_id", "unknown")

    if not meta["turns"]:
        raise SystemExit("error: no turns extracted (session may still be empty)")

    out = Path(args.out) if args.out else Path.cwd() / f"copilot-transcript-{meta['session_id'][:8]}.html"
    out.write_text(render_html(meta), encoding="utf-8")

    s = meta["stats"]
    print(f"wrote {out}")
    print(
        f"  {len(meta['turns'])} turns | source={meta['source']} | "
        f"{s['tool_calls_hidden']} tool calls hidden | {s['reasoning_chars_hidden']:,} reasoning chars hidden | "
        f"{s['sub_agent_msgs_excluded']} sub-agent messages excluded"
    )
    if args.open:
        if os.name == "nt":
            os.startfile(out)  # type: ignore[attr-defined]
        elif sys.platform == "darwin":
            subprocess.run(["open", str(out)], check=False)
        else:
            subprocess.run(["xdg-open", str(out)], check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
