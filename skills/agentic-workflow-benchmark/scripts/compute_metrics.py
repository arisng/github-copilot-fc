#!/usr/bin/env python3
"""Compute agentic-workflow benchmark metrics from a Copilot session events.jsonl.

Pure-function core: parse episode window -> classify steps -> metrics + baseline
delta -> render report markdown + latest.json.

Usage:
    python compute_metrics.py --events <events.jsonl> --skill <name> --out-dir <dir>
        [--session-dir <dir>] [--episode N] [--set-baseline] [--template <path>]
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = 2
SELF_SKILLS = {"agentic-workflow-benchmark"}

# --- Step classification taxonomy (see references/classification.md) ---

WORKFLOW_CONTROL = {
    "ask_user", "exit_plan_mode", "task_complete", "rename_chat",
    "addcomment", "replytocomment", "resolvecomments", "deletecomments",
    "viewunreviewedcomments",
}
SEMANTIC = {
    "edit", "create", "skill", "task", "open_canvas", "runplaywrightcode",
}
QUERY_READ = {
    "grep", "glob", "view", "read", "web_fetch", "lsp",
    "list_sessions", "get_current_session", "session_store_sql",
    "read_powershell", "list_powershell", "stop_powershell",
    "list_powershell", "get_session_context",
}
QUERY_READ_PREFIXES = (
    "github-mcp-server-", "mcp-docker-brave_", "mcp-docker-get_",
    "mcp-docker-code-mode",
)
SHELL_TOOLS = {"powershell", "bash", "shell", "terminal"}
# Provenance: a shell step is "deterministic" only when it executes
# pre-authored repo/toolchain code (scripts, builds, tests, publish tooling).
PROVENANCE_PATTERNS = [
    re.compile(r"\.ps1\b", re.IGNORECASE),
    re.compile(r"\bnpm (?:run|test|npx)\b", re.IGNORECASE),
    re.compile(r"\bdotnet (?:build|test|run|publish|pack|tool)\b", re.IGNORECASE),
    re.compile(r"\bdotnet-coverage\b", re.IGNORECASE),
    re.compile(r"\bpytest\b", re.IGNORECASE),
    re.compile(r"\bpwsh\b", re.IGNORECASE),
    re.compile(r"python3?\s+\S+\.py\b", re.IGNORECASE),
    re.compile(r"\bpy -3\s+\S+\.py\b", re.IGNORECASE),
    re.compile(r"\bgit (?:commit|push|merge|rebase|add|restore|stash|worktree"
               r"|cherry-pick|reset|revert|mv|rm|checkout|switch)\b", re.IGNORECASE),
    re.compile(r"\bcopilot (?:plugin|plugins)\b", re.IGNORECASE),
    re.compile(r"\bnpx skills\b", re.IGNORECASE),
    # Taskfile target invocation (task ax:build:cold) — pre-authored repo tooling
    re.compile(r"(?<![\w-])task\s+[\w:./-]+", re.IGNORECASE),
    # GitHub CLI — pre-authored tooling
    re.compile(r"\bgh\s+(?:api|pr|issue|run|repo|release|workflow|auth|browse"
               r"|check|gist|search|status)\b", re.IGNORECASE),
]
# Read-only git: structured repo queries. Deterministic execution, but each is a
# model decision point, so they route to query_read (not deterministic).
READ_ONLY_GIT_PATTERN = re.compile(
    r"\bgit\s+(?:status|diff|log|show|branch|ls-files|remote|config|blame"
    r"|shortlog|ls-remote|reflog|rev-parse|describe|tag|fetch)\b", re.IGNORECASE)
# Mutating git above wins over read-only; `git stash list` etc. are edge cases
# documented in classification.md.
# Inline model-authored code executed at runtime — semantic by authorship
# (same rule as runplaywrightcode). Checked BEFORE provenance so `python -c`
# is not also credited as tooling.
INLINE_CODE_PATTERNS = [
    re.compile(r"\bpython3?\s+-c\b", re.IGNORECASE),
    re.compile(r"\bpy\s+(?:-3\s+)?-c\b", re.IGNORECASE),
    re.compile(r"\bnode\s+(-\S+\s+)*-e\b", re.IGNORECASE),
]
INLINE_PWSH_COMMAND_PATTERN = re.compile(r"\b(?:pwsh|powershell)\b", re.IGNORECASE)
TOOL_NAME_ALIASES = {
    "sql": "session_store_sql",
    "read": "view",
}


def normalize_tool_name(raw: str) -> str:
    name = (raw or "unknown").strip().lower()
    name = TOOL_NAME_ALIASES.get(name, name)
    return name


def classify_step(tool_name: str, arguments: dict) -> str:
    """Return one of: semantic | deterministic | query_read | workflow_control | uncertain."""
    name = normalize_tool_name(tool_name)
    if name in WORKFLOW_CONTROL:
        return "workflow_control"
    if name in SEMANTIC:
        return "semantic"
    if name in QUERY_READ or name.startswith(QUERY_READ_PREFIXES):
        return "query_read"
    if name in SHELL_TOOLS:
        command = ""
        if isinstance(arguments, dict):
            command = str(arguments.get("command", ""))
        elif isinstance(arguments, str):
            command = arguments
        # Inline model-authored code: semantic by authorship (t5). `pwsh -Command`
        # only when it does NOT reference a pre-authored .ps1 script.
        for pattern in INLINE_CODE_PATTERNS:
            if pattern.search(command):
                return "semantic"
        inline_pwsh = (INLINE_PWSH_COMMAND_PATTERN.search(command)
                       and re.search(r"-Command\b", command, re.IGNORECASE)
                       and not re.search(r"\.ps1\b", command, re.IGNORECASE))
        if inline_pwsh:
            return "semantic"
        # Provenance (deterministic) checked before read-only git so mixed
        # commands like `git commit && git status` count as deterministic.
        for pattern in PROVENANCE_PATTERNS:
            if pattern.search(command):
                return "deterministic"
        if READ_ONLY_GIT_PATTERN.search(command):
            return "query_read"
        return "uncertain"
    return "uncertain"


# --- Parsing ---

def parse_ts(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def load_events(path: Path):
    events, bad_lines = [], 0
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                bad_lines += 1
    return events, bad_lines


def find_episodes(events, skill_name: str):
    """Return list of (start_ts, end_ts_or_None) for each invocation of skill_name.

    Raw mechanical windows (next invoke of ANY skill); chain/subagent-aware
    attribution is done by resolve_episode_end().
    """
    invokes = [
        ev for ev in events
        if ev.get("type") == "skill.invoked"
        and str((ev.get("data") or {}).get("name", "")).lower() == skill_name.lower()
    ]
    all_invokes = [ev for ev in events if ev.get("type") == "skill.invoked"]
    episodes = []
    for inv in invokes:
        start = parse_ts(inv["timestamp"])
        end = None
        for other in all_invokes:
            ts = parse_ts(other["timestamp"])
            if ts > start:
                end = ts
                break
        episodes.append((start, end))
    return episodes


def real_invokes(events):
    """skill.invoked events with a non-empty data.name (filters invoked_ref noise)."""
    return [
        ev for ev in events
        if ev.get("type") == "skill.invoked"
        and str((ev.get("data") or {}).get("name", "")).strip()
    ]


def get_subagent_windows(events):
    """Pair subagent.started/subagent.completed by agentId -> [(start_ts, end_ts)]."""
    open_windows = {}
    windows = []
    for ev in events:
        if ev.get("type") not in ("subagent.started", "subagent.completed"):
            continue
        data = ev.get("data") or {}
        agent_id = ev.get("agentId") or data.get("agentId") or data.get("toolCallId")
        ts = parse_ts(ev["timestamp"])
        if ev["type"] == "subagent.started":
            open_windows[agent_id] = ts
        elif agent_id in open_windows:
            windows.append((open_windows.pop(agent_id), ts))
    # Unclosed windows extend to end of events (best effort)
    if open_windows and events:
        last_ts = parse_ts(max(e["timestamp"] for e in events if e.get("timestamp")))
        windows.extend((start, last_ts) for start in open_windows.values())
    return sorted(windows)


def inside_subagent_window(ts, windows):
    for start, end in windows:
        if start <= ts < end:
            return True
    return False


def skill_md_texts(invoke_events):
    """Chain-detection sources for a skill: event content + on-disk SKILL.md (frontmatter)."""
    texts = []
    for ev in invoke_events:
        data = ev.get("data") or {}
        content = data.get("content")
        if content:
            texts.append(str(content))
        path = data.get("path")
        if path:
            try:
                p = Path(path)
                if p.exists() and p.is_file():
                    texts.append(p.read_text(encoding="utf-8"))
            except OSError:
                pass
    return texts


def declares_machina(texts):
    return any(re.search(r"(?m)^machina\s*:", t) for t in texts)


def chain_merges(target_texts, target_machina, next_name, next_ts, prev_ts):
    """Should next skill's invoke extend the target's episode (skill-chain)?"""
    lower = next_name.lower()
    if lower in SELF_SKILLS:
        return False  # hard stop: benchmark self-activation always terminates
    # Declarative: target's SKILL.md declares machina: and next is the driver
    if target_machina and lower == "machina-driving":
        return True
    # Fallback heuristic: invoked within 120s of previous chain event AND
    # some chain member's SKILL.md names it
    if (next_ts - prev_ts).total_seconds() < 120:
        for text in target_texts:
            if re.search(r"(?<![\w-])" + re.escape(lower) + r"(?![\w-])", text):
                return True
    return False


def resolve_episode_end(events, target_invokes, start, subagent_windows):
    """Chain/subagent-aware episode end for the episode beginning at `start`.

    Returns (end_ts_or_None, boundaries) where boundaries is a list of
    {skill, timestamp, subagent, tokens, tool_steps} rows for skill loads that
    were merged into the episode instead of terminating it.
    """
    target_name = str((target_invokes[0].get("data") or {}).get("name", "")).lower()
    anchor = next((inv for inv in target_invokes
                   if parse_ts(inv["timestamp"]) == start), target_invokes[0])
    chain_texts = skill_md_texts([anchor])
    chain_machina = declares_machina(chain_texts)
    prev_ts = start
    boundaries = []
    for ev in real_invokes(events):
        ts = parse_ts(ev["timestamp"])
        if ts <= start:
            continue
        name = str((ev.get("data") or {}).get("name", "")).lower()
        if name in SELF_SKILLS or name == target_name:
            return ts, boundaries  # hard stop: benchmark or a re-invocation of the target
        subagent_internal = inside_subagent_window(ts, subagent_windows)
        merged = subagent_internal or chain_merges(
            chain_texts, chain_machina, name, ts, prev_ts)
        if not merged:
            return ts, boundaries
        boundaries.append({
            "skill": name,
            "timestamp": ev["timestamp"],
            "subagent": subagent_internal,
        })
        chain_texts.extend(skill_md_texts([ev]))
        prev_ts = ts
    return None, boundaries


def window_token_steps(events, start, end):
    """Tokens total and tool-step count in [start, end) for boundary rows."""
    tokens_total = 0
    steps = 0
    for ev in events:
        if not ev.get("timestamp"):
            continue
        ts = parse_ts(ev["timestamp"])
        if ts < start or (end is not None and ts >= end):
            continue
        if ev.get("type") == "session.usage_record":
            usage = (ev.get("data") or {}).get("usage") or {}
            tokens_total += (int(usage.get("inputTokens") or 0)
                             + int(usage.get("outputTokens") or 0)
                             + int(usage.get("cacheReadTokens") or 0)
                             + int(usage.get("cacheWriteTokens") or 0)
                             + int(usage.get("reasoningTokens") or 0))
        elif ev.get("type") == "tool.execution_start":
            steps += 1
    return tokens_total, steps


def to_epoch_ms(ts: datetime) -> float:
    return ts.timestamp() * 1000.0


# --- Metric computation ---

def compute_metrics(events, skill_name: str, episode_index: int, session_dir: str,
                    bad_lines: int = 0, mode: str = "episode"):
    if mode == "session":
        return compute_session_metrics(events, skill_name, session_dir, bad_lines)
    episodes = find_episodes(events, skill_name)
    if not episodes:
        return None, {"reason": f"no skill.invoked event found for '{skill_name}'"}

    idx = episode_index if episode_index >= 0 else len(episodes) - 1
    if idx >= len(episodes):
        return None, {"reason": f"episode {idx} out of range ({len(episodes)} found)"}
    start, mechanical_end = episodes[idx]

    subagent_windows = get_subagent_windows(events)
    target_invokes = [
        ev for ev in real_invokes(events)
        if str((ev.get("data") or {}).get("name", "")).lower() == skill_name.lower()
    ]
    end, boundaries = resolve_episode_end(
        events, target_invokes, start, subagent_windows)

    in_window = [
        ev for ev in events
        if ev.get("timestamp")
        and start <= parse_ts(ev["timestamp"])
        and (end is None or parse_ts(ev["timestamp"]) < end)
    ]
    if end is None and in_window:
        end = parse_ts(max(ev["timestamp"] for ev in in_window))
    wall_ms = (to_epoch_ms(end) - to_epoch_ms(start)) if end else 0.0

    # Boundary rows: merged skill loads with their own sub-window totals
    for i, boundary in enumerate(boundaries):
        b_start = parse_ts(boundary["timestamp"])
        b_end = (parse_ts(boundaries[i + 1]["timestamp"])
                 if i + 1 < len(boundaries) else end)
        tokens, steps = window_token_steps(events, b_start, b_end)
        boundary["tokens"] = tokens
        boundary["tool_steps"] = steps

    result = _compute_window_metrics(in_window, events, skill_name, session_dir,
                                     bad_lines, idx, len(episodes), start, end, wall_ms)
    if result is None:
        return None, {"reason": "metric window computation failed"}

    metrics, _ = result
    metrics["episode"]["boundaries"] = boundaries
    metrics["episode"]["mechanical_end"] = (
        mechanical_end.isoformat() if mechanical_end else None)

    # Degenerate-episode guard (t1)
    total_session_steps = sum(
        1 for ev in events if ev.get("type") == "tool.execution_start")
    outside_steps = total_session_steps - metrics["steps"]["total"]
    degenerate_reasons = []
    if metrics["steps"]["total"] <= 2:
        degenerate_reasons.append(
            f"episode holds only {metrics['steps']['total']} tool step(s)")
    if wall_ms < 120000 and outside_steps > 50:
        degenerate_reasons.append(
            f"episode window is {fmt_ms(wall_ms)} while {outside_steps} tool steps "
            "exist outside it")
    other_invokes = sorted({
        str((ev.get("data") or {}).get("name", "")).lower()
        for ev in real_invokes(events)
        if parse_ts(ev["timestamp"]) != start
    })
    metrics["degenerate"] = {
        "is_degenerate": bool(degenerate_reasons),
        "reasons": degenerate_reasons,
        "session_tool_steps_outside": outside_steps,
    }
    metrics["other_skill_invokes"] = other_invokes
    return metrics, None


def _compute_window_metrics(in_window, all_events, skill_name, session_dir,
                            bad_lines, idx, episode_count, start, end, wall_ms):
    """Token/time/step metrics for one time window (episode or session)."""
    # Tokens / LLM calls
    tokens = {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0,
              "reasoning": 0, "total": 0}
    sub_agent_tokens = dict(tokens)
    llm_calls = 0
    llm_ms = 0.0
    cost_reported = 0.0
    models = set()
    for ev in in_window:
        if ev.get("type") != "session.usage_record":
            continue
        usage = (ev.get("data") or {}).get("usage") or {}
        llm_calls += 1
        models.add(str(usage.get("model", "unknown")))
        llm_ms += float(usage.get("duration") or 0)
        cost_reported += float(usage.get("cost") or 0)
        values = {
            "input": int(usage.get("inputTokens") or 0),
            "output": int(usage.get("outputTokens") or 0),
            "cache_read": int(usage.get("cacheReadTokens") or 0),
            "cache_write": int(usage.get("cacheWriteTokens") or 0),
            "reasoning": int(usage.get("reasoningTokens") or 0),
        }
        values["total"] = sum(values.values())
        for key, value in values.items():
            tokens[key] += value
        initiator = str(usage.get("initiator", "")).lower()
        if initiator in ("sub-agent", "subagent") or usage.get("agentId"):
            for key, value in values.items():
                sub_agent_tokens[key] += value

    # Tool steps
    starts = {}
    for ev in in_window:
        if ev.get("type") == "tool.execution_start":
            data = ev.get("data") or {}
            starts[data.get("toolCallId")] = {
                "toolName": data.get("toolName", "unknown"),
                "arguments": data.get("arguments") or {},
                "start_ms": to_epoch_ms(parse_ts(ev["timestamp"])),
                "duration_ms": 0.0,
            }
    for ev in in_window:
        if ev.get("type") != "tool.execution_complete":
            continue
        data = ev.get("data") or {}
        entry = starts.get(data.get("toolCallId"))
        if entry is not None:
            entry["duration_ms"] = to_epoch_ms(parse_ts(ev["timestamp"])) - entry["start_ms"]

    steps = {"semantic": 0, "deterministic": 0, "query_read": 0,
             "workflow_control": 0, "uncertain": 0, "total": 0}
    tool_ms = 0.0
    ask_user_wait_ms = 0.0
    uncertain_samples = []
    for entry in starts.values():
        bucket = classify_step(entry["toolName"], entry["arguments"])
        steps[bucket] += 1
        steps["total"] += 1
        tool_ms += entry["duration_ms"]
        if normalize_tool_name(entry["toolName"]) == "ask_user":
            ask_user_wait_ms += entry["duration_ms"]
        if bucket == "uncertain" and len(uncertain_samples) < 10:
            uncertain_samples.append(normalize_tool_name(entry["toolName"]))

    active_ms = max(wall_ms - ask_user_wait_ms, 0.0)
    decision_points = steps["semantic"] + steps["query_read"]
    scored = steps["semantic"] + steps["deterministic"]
    ratios = {
        "deterministic_ratio": round(steps["deterministic"] / steps["total"], 4) if steps["total"] else 0.0,
        "workflow_control_ratio": round(steps["workflow_control"] / steps["total"], 4) if steps["total"] else 0.0,
        "decision_points": decision_points,
        "tokens_per_semantic_step": round(tokens["total"] / steps["semantic"], 1) if steps["semantic"] else None,
        "active_ms_per_semantic_step": round(active_ms / steps["semantic"], 1) if steps["semantic"] else None,
        "scored_steps": scored,
    }

    cli_version = "unknown"
    for ev in all_events:
        if ev.get("type") == "session.start":
            cli_version = str((ev.get("data") or {}).get("copilotVersion") or "unknown")
            break

    metrics = {
        "schema_version": SCHEMA_VERSION,
        "mode": "episode",
        "skill": skill_name,
        "session_dir": session_dir,
        "episode_index": idx,
        "episode_count": episode_count,
        "episode": {
            "start": start.isoformat(),
            "end": end.isoformat() if end else None,
            "wall_clock_ms": round(wall_ms, 1),
        },
        "cli_version": cli_version,
        "models": sorted(models),
        "tokens": tokens,
        "sub_agent_tokens": sub_agent_tokens,
        "llm_calls": llm_calls,
        "cost": {
            "reported": round(cost_reported, 4),
            "note": "informational only; BYOK sessions report 0",
        },
        "time": {
            "wall_clock_ms": round(wall_ms, 1),
            "active_ms": round(active_ms, 1),
            "tool_ms": round(tool_ms, 1),
            "llm_ms": round(llm_ms, 1),
            "ask_user_wait_ms": round(ask_user_wait_ms, 1),
        },
        "steps": steps,
        "ratios": ratios,
        "uncertain_tool_samples": uncertain_samples,
        "bad_event_lines": bad_lines,
    }
    return metrics, None


def compute_session_metrics(events, skill_name: str, session_dir: str,
                            bad_lines: int = 0):
    """Session-aggregate mode: every event before the benchmark's own activation.

    Headline scorecard = whole-workflow cost; per-episode table is the
    secondary breakdown. Self-exclusion preserved via SELF_SKILLS hard stop.
    """
    if not events:
        return None, {"reason": "no events found"}
    first_ts = parse_ts(min(ev["timestamp"] for ev in events if ev.get("timestamp")))

    # End = benchmark's own most recent activation; offline re-runs fall back
    # to end of events (the benchmark ran in an earlier session pass).
    end = None
    for ev in real_invokes(events):
        if str((ev.get("data") or {}).get("name", "")).lower() in SELF_SKILLS:
            ts = parse_ts(ev["timestamp"])
            if end is None or ts > end:
                end = ts
    if end is None:
        end = parse_ts(max(ev["timestamp"] for ev in events if ev.get("timestamp")))
    wall_ms = to_epoch_ms(end) - to_epoch_ms(first_ts)

    in_window = [
        ev for ev in events
        if ev.get("timestamp")
        and first_ts <= parse_ts(ev["timestamp"]) < end
    ]
    result = _compute_window_metrics(in_window, events, skill_name, session_dir,
                                     bad_lines, 0, 0, first_ts, end, wall_ms)
    if result is None:
        return None, {"reason": "session window computation failed"}
    metrics, _ = result
    metrics["mode"] = "session"

    # Secondary breakdown: mechanical per-skill episode table (chain-unaware
    # windows; attribution detail lives in episode mode reports).
    breakdown = []
    invokes = real_invokes(events)
    for i, inv in enumerate(invokes):
        name = str((inv.get("data") or {}).get("name", "")).lower()
        if name in SELF_SKILLS:
            continue
        start = parse_ts(inv["timestamp"])
        next_ts = None
        for other in invokes:
            ts = parse_ts(other["timestamp"])
            if ts > start:
                next_ts = ts
                break
        b_end = next_ts if next_ts else end
        tokens_total, step_count = window_token_steps(events, start, b_end)
        breakdown.append({
            "skill": name,
            "start": inv["timestamp"],
            "end": b_end.isoformat(),
            "wall_clock_ms": round(to_epoch_ms(b_end) - to_epoch_ms(start), 1),
            "tokens": tokens_total,
            "tool_steps": step_count,
        })
    metrics["episode_breakdown"] = breakdown
    metrics["degenerate"] = {"is_degenerate": False, "reasons": [],
                             "session_tool_steps_outside": 0}
    metrics["other_skill_invokes"] = sorted({b["skill"] for b in breakdown})
    return metrics, None


# --- Baseline deltas ---

# goal direction: True => lower is better
HEADLINE_METRICS = [
    ("tokens.total", "Minimize LLM token usage", True),
    ("time.active_ms", "Minimize execution time", True),
    ("steps.semantic", "Minimize semantic steps", True),
    ("ratios.deterministic_ratio", "Maximize deterministic steps", False),
]


def dig(metrics: dict, dotted: str):
    node = metrics
    for part in dotted.split("."):
        if not isinstance(node, dict):
            return None
        node = node.get(part)
    return node


def delta_rows(current: dict, baseline: dict | None):
    rows = []
    for key, goal, lower_is_better in HEADLINE_METRICS:
        value = dig(current, key)
        base = dig(baseline, key) if baseline else None
        delta = None
        trend = "n/a"
        if isinstance(value, (int, float)) and isinstance(base, (int, float)) and base != 0:
            delta = round(value - base, 4)
            if delta == 0:
                trend = "= unchanged"
            else:
                improved = (delta < 0) if lower_is_better else (delta > 0)
                trend = "improved" if improved else "regressed"
        rows.append({"metric": key, "goal": goal, "value": value,
                     "baseline": base, "delta": delta, "trend": trend})
    return rows


# --- Report rendering ---

def fmt_ms(value) -> str:
    if value is None:
        return "n/a"
    if value >= 60000:
        return f"{value / 60000:.1f} min"
    if value >= 1000:
        return f"{value / 1000:.1f} s"
    return f"{value:.0f} ms"


def kv_table(pairs):
    lines = ["| Metric | Value |", "|---|---|"]
    lines += [f"| {k} | {v} |" for k, v in pairs]
    return "\n".join(lines)


def render_report(metrics: dict, rows, baseline_path: Path | None,
                  template_text: str, baseline: dict | None = None,
                  baseline_refused_reason: str | None = None) -> str:
    steps = metrics["steps"]
    tokens = metrics["tokens"]
    time_info = metrics["time"]
    ratios = metrics["ratios"]
    scorecard = ["| # | Goal | Metric | Value | Baseline | Δ | Trend |",
                 "|---|------|--------|-------|----------|---|-------|"]
    for i, row in enumerate(rows, 1):
        value, base, delta = row["value"], row["baseline"], row["delta"]
        scorecard.append(
            f"| {i} | {row['goal']} | `{row['metric']}` | {value} "
            f"| {base if base is not None else '—'} "
            f"| {delta if delta is not None else '—'} | {row['trend']} |")

    tokens_table = kv_table([
        ("input tokens", f"{tokens['input']:,}"),
        ("output tokens", f"{tokens['output']:,}"),
        ("cache read", f"{tokens['cache_read']:,}"),
        ("cache write", f"{tokens['cache_write']:,}"),
        ("reasoning", f"{tokens['reasoning']:,}"),
        ("**total**", f"**{tokens['total']:,}**"),
        ("LLM calls", metrics["llm_calls"]),
        ("sub-agent total (broken out)", f"{metrics['sub_agent_tokens']['total']:,}"),
        ("cost (informational)", metrics["cost"]["reported"]),
    ])
    time_table = kv_table([
        ("wall-clock", fmt_ms(time_info["wall_clock_ms"])),
        ("active (excl. ask_user waits)", fmt_ms(time_info["active_ms"])),
        ("tool time", fmt_ms(time_info["tool_ms"])),
        ("LLM time", fmt_ms(time_info["llm_ms"])),
        ("ask_user wait", fmt_ms(time_info["ask_user_wait_ms"])),
    ])
    steps_table = kv_table([
        ("semantic", steps["semantic"]),
        ("deterministic", steps["deterministic"]),
        ("query/read", steps["query_read"]),
        ("workflow-control", steps["workflow_control"]),
        ("uncertain", steps["uncertain"]),
        ("**total**", steps["total"]),
    ])
    ratios_table = kv_table([
        ("deterministic ratio", ratios["deterministic_ratio"]),
        ("decision points (semantic + query/read)", ratios["decision_points"]),
        ("tokens per semantic step", ratios["tokens_per_semantic_step"]),
        ("active time per semantic step", fmt_ms(ratios["active_ms_per_semantic_step"])),
    ])
    notes = []
    if metrics["uncertain_tool_samples"]:
        notes.append("Uncertain tools observed: "
                     + ", ".join(f"`{t}`" for t in metrics["uncertain_tool_samples"])
                     + " — consider extending the taxonomy in `references/classification.md`.")
    if metrics["bad_event_lines"]:
        notes.append(f"{metrics['bad_event_lines']} unparseable event lines skipped.")
    if metrics["sub_agent_tokens"]["total"]:
        notes.append("Sub-agent usage is included in totals and broken out separately.")
    if metrics.get("other_skill_invokes"):
        others = [s for s in metrics["other_skill_invokes"] if s != metrics["skill"]]
        if others:
            notes.append("Other skills invoked in this session: "
                         + ", ".join(f"`{s}`" for s in others)
                         + " — if the target skill is an orchestrator, verify the "
                         "boundaries table above represents the whole workflow.")
    if baseline_refused_reason:
        notes.append(f"**Baseline NOT written**: {baseline_refused_reason}.")
    else:
        notes.append(f"Baseline file: `{baseline_path}`" if baseline_path
                     else "No baseline yet — this run becomes the baseline "
                          "(pass `-SetBaseline` to overwrite an existing one later).")
    notes.append("Cost is informational only (BYOK sessions report 0).")
    baseline_schema = baseline.get("schema_version") if baseline else None
    if baseline_schema is not None and baseline_schema < SCHEMA_VERSION:
        notes.append(f"Baseline was written by schema v{baseline_schema}; "
                     "re-baseline recommended after this upgrade.")

    # Caveats (prominent, top of report) — degenerate episodes etc.
    caveats = []
    degenerate = metrics.get("degenerate") or {}
    if degenerate.get("is_degenerate"):
        caveats.append(
            "**DEGENERATE EPISODE** — " + "; ".join(degenerate["reasons"])
            + ". This scorecard measures a skill load, not the workflow. "
              "`baseline.json` was NOT written (pass `-SetBaseline`/`--set-baseline` "
              "to force). Use `--mode session` for a whole-workflow number, or "
              "check episode boundaries for skill-chain/subagent attribution gaps.")
    if not caveats:
        caveats.append("_None._")

    # Boundaries: merged skill loads inside the episode (episode mode)
    boundaries = metrics["episode"].get("boundaries") or []
    if boundaries:
        lines = ["| Skill | Loaded at | Origin | Tokens | Tool steps |",
                 "|---|---|---|---|---|"]
        for b in boundaries:
            origin = "subagent" if b.get("subagent") else "skill-chain"
            lines.append(f"| `{b['skill']}` | {b['timestamp']} | {origin} "
                         f"| {b.get('tokens', 'n/a'):,} "
                         f"| {b.get('tool_steps', 'n/a')} |")
        boundaries_text = "\n".join(lines)
    else:
        if metrics.get("mode") == "session":
            boundaries_text = "_n/a (session mode) — attribution is shown in the " \
                              "per-episode breakdown below._"
        else:
            boundaries_text = "_No merged skill loads — episode ended at the next external skill invocation._"

    # Episode breakdown (session mode secondary table)
    breakdown = metrics.get("episode_breakdown") or []
    if breakdown:
        lines = ["| Skill | Start | End | Duration | Tokens | Tool steps |",
                 "|---|---|---|---|---|---|"]
        for b in breakdown:
            lines.append(f"| `{b['skill']}` | {b['start']} | {b['end']} "
                         f"| {fmt_ms(b['wall_clock_ms'])} | {b['tokens']:,} "
                         f"| {b['tool_steps']} |")
        breakdown_text = "\n".join(lines)
    else:
        breakdown_text = "_n/a (episode mode)._"

    if metrics.get("mode") == "session":
        window_line = (f"Session window (whole transcript): {metrics['episode']['start']}"
                       f" → {metrics['episode']['end'] or 'n/a'}")
    else:
        window_line = (f"Episode: {metrics['episode_index'] + 1} of {metrics['episode_count']}"
                       f" — {metrics['episode']['start']} → {metrics['episode']['end'] or 'n/a'}")

    replacements = {
        "{{WINDOW_LINE}}": window_line,
        "{{SKILL_NAME}}": metrics["skill"],
        "{{SESSION_DIR}}": metrics["session_dir"] or "n/a",
        "{{EPISODE_INDEX}}": str(metrics["episode_index"] + 1),
        "{{EPISODE_COUNT}}": str(metrics["episode_count"]),
        "{{EPISODE_START}}": metrics["episode"]["start"],
        "{{EPISODE_END}}": metrics["episode"]["end"] or "n/a",
        "{{GENERATED_AT}}": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "{{CLI_VERSION}}": metrics["cli_version"],
        "{{MODELS}}": ", ".join(metrics["models"]) or "unknown",
        "{{MODE}}": metrics.get("mode", "episode"),
        "{{CAVEATS}}": "\n".join(f"- {c}" for c in caveats),
        "{{BOUNDARIES}}": boundaries_text,
        "{{EPISODE_BREAKDOWN}}": breakdown_text,
        "{{SCORECARD_ROWS}}": "\n".join(scorecard[2:]),
        "{{SCORECARD_HEADER}}": "\n".join(scorecard[:2]),
        "{{TOKENS_TABLE}}": tokens_table,
        "{{TIME_TABLE}}": time_table,
        "{{STEPS_TABLE}}": steps_table,
        "{{RATIOS_TABLE}}": ratios_table,
        "{{NOTES}}": "\n".join(f"- {n}" for n in notes),
    }
    report = template_text
    for key, value in replacements.items():
        report = report.replace(key, value)
    return report


CANNOT_BENCHMARK_TEMPLATE = """# Agentic Workflow Benchmark — CANNOT BENCHMARK

- Skill: `{{SKILL_NAME}}`
- Session dir: `{{SESSION_DIR}}`
- Reason: {{REASON}}
- Generated: {{GENERATED_AT}}

No metrics were produced. Fix the gap above (typically: missing `events.jsonl`
telemetry for the session, or the target skill was never invoked in it) and re-run.
"""


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--events", required=True, type=Path)
    parser.add_argument("--skill", required=True)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--session-dir", default="")
    parser.add_argument("--episode", type=int, default=-1,
                        help="episode index; default -1 = most recent invocation")
    parser.add_argument("--mode", choices=("episode", "session"), default="episode",
                        help="episode = one skill-execution run; session = "
                             "aggregate of everything before the benchmark's own "
                             "activation (whole-workflow number)")
    parser.add_argument("--set-baseline", action="store_true")
    parser.add_argument("--template", type=Path, default=None)
    args = parser.parse_args(argv)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")

    if not args.events.exists():
        reason = f"events file not found: {args.events}"
        report_path = args.out_dir / f"{stamp}-cannot-benchmark.md"
        text = (CANNOT_BENCHMARK_TEMPLATE
                .replace("{{SKILL_NAME}}", args.skill)
                .replace("{{SESSION_DIR}}", str(args.session_dir or "n/a"))
                .replace("{{REASON}}", reason)
                .replace("{{GENERATED_AT}}", datetime.now(timezone.utc).isoformat(timespec="seconds")))
        report_path.write_text(text, encoding="utf-8")
        print(f"CANNOT BENCHMARK: {reason}", file=sys.stderr)
        return 3

    template_path = args.template or (Path(__file__).resolve().parent.parent
                                      / "assets" / "report-template.md")
    template_text = template_path.read_text(encoding="utf-8") if template_path.exists() else \
        "# Benchmark — {{SKILL_NAME}}\n\n{{SCORECARD_HEADER}}\n{{SCORECARD_ROWS}}\n"

    events, bad_lines = load_events(args.events)
    metrics, error = compute_metrics(events, args.skill, args.episode,
                                     str(args.session_dir), bad_lines,
                                     mode=args.mode)
    if metrics is None:
        reason = error["reason"]
        report_path = args.out_dir / f"{stamp}-cannot-benchmark.md"
        text = (CANNOT_BENCHMARK_TEMPLATE
                .replace("{{SKILL_NAME}}", args.skill)
                .replace("{{SESSION_DIR}}", str(args.session_dir or "n/a"))
                .replace("{{REASON}}", reason)
                .replace("{{GENERATED_AT}}", datetime.now(timezone.utc).isoformat(timespec="seconds")))
        report_path.write_text(text, encoding="utf-8")
        print(f"CANNOT BENCHMARK: {reason}", file=sys.stderr)
        return 3

    # Baselines are mode-separated: episode and session scorecards answer
    # different questions and must never cross-compare.
    baseline_name = "baseline.session.json" if args.mode == "session" else "baseline.json"
    latest_name = "latest.session.json" if args.mode == "session" else "latest.json"
    baseline_path = args.out_dir / baseline_name
    latest_path = args.out_dir / latest_name
    baseline = json.loads(baseline_path.read_text(encoding="utf-8")) if baseline_path.exists() else None
    previous = json.loads(latest_path.read_text(encoding="utf-8")) if latest_path.exists() else None

    rows = delta_rows(metrics, baseline)

    # Baseline write policy: explicit --set-baseline always wins; otherwise a
    # degenerate episode must NOT silently anchor the baseline (t1).
    degenerate = (metrics.get("degenerate") or {}).get("is_degenerate", False)
    baseline_refused_reason = None
    if degenerate and not args.set_baseline:
        baseline_refused_reason = (
            "degenerate episode — refusing to anchor baseline; "
            "pass --set-baseline to force")
    baseline_written = False
    if args.set_baseline or (baseline is None and baseline_refused_reason is None):
        baseline_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
        baseline_written = True

    report = render_report(metrics, rows, baseline_path if baseline else None,
                           template_text, baseline,
                           baseline_refused_reason=baseline_refused_reason)

    if metrics.get("mode") == "session":
        report_path = args.out_dir / f"{stamp}-session-report.md"
    else:
        report_path = args.out_dir / f"{stamp}-episode{metrics['episode_index'] + 1}-report.md"
    report_path.write_text(report, encoding="utf-8")
    latest_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    summary = {
        "report": str(report_path),
        "mode": metrics.get("mode", "episode"),
        "tokens_total": metrics["tokens"]["total"],
        "active_ms": metrics["time"]["active_ms"],
        "semantic_steps": metrics["steps"]["semantic"],
        "deterministic_steps": metrics["steps"]["deterministic"],
        "deterministic_ratio": metrics["ratios"]["deterministic_ratio"],
        "vs_baseline": rows,
        "previous_run_exists": previous is not None,
        "baseline_written": baseline_written,
        "baseline_refused_reason": baseline_refused_reason,
    }
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
