#!/usr/bin/env python
"""Deterministic Ralph v2 session metadata finalizer for Stop hook."""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
from datetime import datetime
from pathlib import Path


SESSION_ID_PATTERN = re.compile(r"^[0-9]{6}-[0-9]{6}$")
SESSION_ID_IN_TEXT = re.compile(r"[0-9]{6}-[0-9]{6}")


def iso_now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def get_repo_root() -> Path:
    override = os.environ.get("RALPH_HOOK_REPO_ROOT", "").strip()
    if override:
        return Path(override).resolve()
    return Path(__file__).resolve().parents[2]


def read_hook_payload() -> dict:
    """Best-effort stdin JSON reader for hook context.

    When script is run manually in a TTY, skip stdin reads to avoid blocking.
    """
    try:
        if sys.stdin.isatty():
            return {}
        raw = sys.stdin.read().strip()
        if not raw:
            return {}
        data = json.loads(raw)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def write_jsonl(log_path: Path, event: dict) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(event, separators=(",", ":")) + "\n")


def find_session_ids_in_text(text: str) -> list[str]:
    return [m.group(0) for m in SESSION_ID_IN_TEXT.finditer(text)]


def read_binding_session_id(payload: dict, sessions_root: Path) -> str | None:
    hook_session_id = str(payload.get("sessionId", "")).strip()
    if not hook_session_id:
        return None

    bindings_dir = sessions_root / ".hook-bindings"
    binding_path = bindings_dir / f"{hook_session_id}.json"
    if not binding_path.exists():
        return None

    try:
        data = json.loads(binding_path.read_text(encoding="utf-8"))
        candidate = str(data.get("ralph_session_id", "")).strip()
        if SESSION_ID_PATTERN.match(candidate):
            return candidate
    except Exception:
        return None
    return None


def read_transcript_session_id(payload: dict, sessions_root: Path) -> str | None:
    transcript_path_raw = str(payload.get("transcript_path", "")).strip()
    if not transcript_path_raw:
        return None

    transcript_path = Path(transcript_path_raw)
    if not transcript_path.exists() or not transcript_path.is_file():
        return None

    try:
        # Read tail to keep cost low while prioritizing most recent session mentions.
        raw = transcript_path.read_text(encoding="utf-8", errors="ignore")
        tail = raw[-200000:]
        candidates = find_session_ids_in_text(tail)
        for candidate in reversed(candidates):
            if (sessions_root / candidate).exists():
                return candidate
    except Exception:
        return None
    return None


def resolve_target_session_id(payload: dict, sessions_root: Path) -> str | None:
    binding_id = read_binding_session_id(payload, sessions_root)
    if binding_id:
        return binding_id

    transcript_id = read_transcript_session_id(payload, sessions_root)
    if transcript_id:
        return transcript_id

    active_pointer = sessions_root / ".active-session"
    if active_pointer.exists():
        candidate = active_pointer.read_text(encoding="utf-8").strip()
        if SESSION_ID_PATTERN.match(candidate):
            return candidate

    return None


def get_root_value(lines: list[str], key: str) -> str | None:
    matcher = re.compile(rf"^{re.escape(key)}:\s*(.+?)\s*$")
    for line in lines:
        m = matcher.match(line)
        if m:
            return m.group(1)
    return None


def ensure_root_key(lines: list[str], key: str, value: str) -> list[str]:
    matcher = re.compile(rf"^{re.escape(key)}:\s*.*$")
    for i, line in enumerate(lines):
        if matcher.match(line):
            lines[i] = f"{key}: {value}"
            return lines
    lines.append(f"{key}: {value}")
    return lines


def ensure_orchestrator_state(lines: list[str], state: str) -> list[str]:
    orchestrator_idx = -1
    for i, line in enumerate(lines):
        if re.match(r"^orchestrator:\s*$", line):
            orchestrator_idx = i
            break

    if orchestrator_idx < 0:
        lines.append("orchestrator:")
        lines.append(f"  state: {state}")
        return lines

    block_end = len(lines)
    for j in range(orchestrator_idx + 1, len(lines)):
        if re.match(r"^[^\s].*:\s*.*$", lines[j]):
            block_end = j
            break

    for k in range(orchestrator_idx + 1, block_end):
        if re.match(r"^\s{2}state:\s*.*$", lines[k]):
            lines[k] = f"  state: {state}"
            return lines

    lines.insert(orchestrator_idx + 1, f"  state: {state}")
    return lines


def atomic_write(path: Path, text: str) -> None:
    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8", dir=str(path.parent)) as tmp:
        tmp.write(text)
        tmp_path = Path(tmp.name)
    os.replace(tmp_path, path)


def main() -> int:
    now = iso_now()
    payload = read_hook_payload()

    # Hard guard: skip recursive stop hooks and non-Stop events.
    if payload.get("stop_hook_active") is True:
        return 0
    hook_event = str(payload.get("hookEventName", "")).strip()
    if hook_event and hook_event != "Stop":
        return 0

    repo_root = get_repo_root()
    sessions_root = repo_root / ".ralph-sessions"
    active_pointer = sessions_root / ".active-session"
    session_id = resolve_target_session_id(payload, sessions_root)
    if not session_id:
        return 0

    session_path = sessions_root / session_id
    marker_path = session_path / ".hook-enabled"
    metadata_path = session_path / "metadata.yaml"
    log_path = session_path / "logs" / "hook-finalization.jsonl"
    lock_path = session_path / ".finalize.lock"

    if not session_path.exists():
        return 0

    # Hard guard: only finalize sessions explicitly marked as Ralph hook-enabled.
    if not marker_path.exists():
        return 0

    if not metadata_path.exists():
        write_jsonl(
            log_path,
            {
                "ts": now,
                "hook": "stop-finalizer",
                "session_id": session_id,
                "result": "warning",
                "reason": "metadata_missing",
            },
        )
        return 0

    lock_fd = None
    try:
        lock_fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.write(lock_fd, now.encode("utf-8"))
        os.close(lock_fd)
        lock_fd = None
    except FileExistsError:
        write_jsonl(
            log_path,
            {
                "ts": now,
                "hook": "stop-finalizer",
                "session_id": session_id,
                "result": "warning",
                "reason": "lock_exists",
            },
        )
        return 0
    except Exception:
        pass

    try:
        raw = metadata_path.read_text(encoding="utf-8")
        lines = raw.splitlines()

        current_status = (get_root_value(lines, "status") or "").strip()
        normalized_status = "completed" if current_status == "completed" else "blocked"

        lines = ensure_root_key(lines, "updated_at", now)
        lines = ensure_root_key(lines, "status", normalized_status)
        lines = ensure_orchestrator_state(lines, "COMPLETE")
        lines = ensure_root_key(lines, "finalized_at", now)
        lines = ensure_root_key(lines, "finalized_by", "hook.stop")
        lines = ensure_root_key(lines, "finalize_reason", "session_stopped")
        lines = ensure_root_key(lines, "finalization_version", "1")

        output = "\n".join(lines).rstrip() + "\n"
        atomic_write(metadata_path, output)

        write_jsonl(
            log_path,
            {
                "ts": now,
                "hook": "stop-finalizer",
                "session_id": session_id,
                "result": "ok",
                "status": normalized_status,
                "orchestrator_state": "COMPLETE",
            },
        )

        if active_pointer.exists() and active_pointer.read_text(encoding="utf-8").strip() == session_id:
            active_pointer.write_text("", encoding="utf-8")

        return 0
    except Exception as exc:
        write_jsonl(
            log_path,
            {
                "ts": now,
                "hook": "stop-finalizer",
                "session_id": session_id,
                "result": "error",
                "reason": str(exc),
            },
        )
        return 0
    finally:
        try:
            if lock_path.exists():
                lock_path.unlink()
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
