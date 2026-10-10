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

SCHEMA_VERSION = 1
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
    re.compile(r"\bdotnet (?:build|test|run|publish|pack)\b", re.IGNORECASE),
    re.compile(r"\bpytest\b", re.IGNORECASE),
    re.compile(r"\bpwsh\b", re.IGNORECASE),
    re.compile(r"python3?\s+\S+\.py\b", re.IGNORECASE),
    re.compile(r"\bpy -3\s+\S+\.py\b", re.IGNORECASE),
    re.compile(r"\bgit (?:commit|push|merge|rebase)\b", re.IGNORECASE),
    re.compile(r"\bcopilot (?:plugin|plugins)\b", re.IGNORECASE),
    re.compile(r"\bnpx skills\b", re.IGNORECASE),
]
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
        for pattern in PROVENANCE_PATTERNS:
            if pattern.search(command):
                return "deterministic"
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
    """Return list of (start_ts, end_ts_or_None) for each invocation of skill_name."""
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


def to_epoch_ms(ts: datetime) -> float:
    return ts.timestamp() * 1000.0


# --- Metric computation ---

def compute_metrics(events, skill_name: str, episode_index: int, session_dir: str,
                    bad_lines: int = 0):
    episodes = find_episodes(events, skill_name)
    if not episodes:
        return None, {"reason": f"no skill.invoked event found for '{skill_name}'"}

    idx = episode_index if episode_index >= 0 else len(episodes) - 1
    if idx >= len(episodes):
        return None, {"reason": f"episode {idx} out of range ({len(episodes)} found)"}
    start, end = episodes[idx]

    in_window = [
        ev for ev in events
        if ev.get("timestamp")
        and start <= parse_ts(ev["timestamp"])
        and (end is None or parse_ts(ev["timestamp"]) < end)
    ]
    if end is None and in_window:
        end = parse_ts(max(ev["timestamp"] for ev in in_window))
    wall_ms = (to_epoch_ms(end) - to_epoch_ms(start)) if end else 0.0

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
    for ev in events:
        if ev.get("type") == "session.start":
            cli_version = str((ev.get("data") or {}).get("copilotVersion") or "unknown")
            break

    metrics = {
        "schema_version": SCHEMA_VERSION,
        "skill": skill_name,
        "session_dir": session_dir,
        "episode_index": idx,
        "episode_count": len(episodes),
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
                  template_text: str) -> str:
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
    notes.append(f"Baseline file: `{baseline_path}`" if baseline_path
                 else "No baseline yet — this run becomes the baseline with `-SetBaseline`.")
    notes.append("Cost is informational only (BYOK sessions report 0).")

    replacements = {
        "{{SKILL_NAME}}": metrics["skill"],
        "{{SESSION_DIR}}": metrics["session_dir"] or "n/a",
        "{{EPISODE_INDEX}}": str(metrics["episode_index"] + 1),
        "{{EPISODE_COUNT}}": str(metrics["episode_count"]),
        "{{EPISODE_START}}": metrics["episode"]["start"],
        "{{EPISODE_END}}": metrics["episode"]["end"] or "n/a",
        "{{GENERATED_AT}}": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "{{CLI_VERSION}}": metrics["cli_version"],
        "{{MODELS}}": ", ".join(metrics["models"]) or "unknown",
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
                                     str(args.session_dir), bad_lines)
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

    baseline_path = args.out_dir / "baseline.json"
    latest_path = args.out_dir / "latest.json"
    baseline = json.loads(baseline_path.read_text(encoding="utf-8")) if baseline_path.exists() else None
    previous = json.loads(latest_path.read_text(encoding="utf-8")) if latest_path.exists() else None

    rows = delta_rows(metrics, baseline)
    report = render_report(metrics, rows, baseline_path if baseline else None, template_text)

    report_path = args.out_dir / f"{stamp}-episode{metrics['episode_index'] + 1}-report.md"
    report_path.write_text(report, encoding="utf-8")
    latest_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    if args.set_baseline or baseline is None:
        baseline_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    summary = {
        "report": str(report_path),
        "tokens_total": metrics["tokens"]["total"],
        "active_ms": metrics["time"]["active_ms"],
        "semantic_steps": metrics["steps"]["semantic"],
        "deterministic_steps": metrics["steps"]["deterministic"],
        "deterministic_ratio": metrics["ratios"]["deterministic_ratio"],
        "vs_baseline": rows,
        "previous_run_exists": previous is not None,
        "baseline_written": args.set_baseline or baseline is None,
    }
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
