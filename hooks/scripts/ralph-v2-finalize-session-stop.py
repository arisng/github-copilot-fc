#!/usr/bin/env python
"""Deterministic Ralph v2 session metadata finalizer for Stop hook."""

from __future__ import annotations

import json
import os
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path


SESSION_ID_PATTERN = re.compile(r"^[0-9]{6}-[0-9]{6}$")


def iso_now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def get_repo_root() -> Path:
    override = os.environ.get("RALPH_HOOK_REPO_ROOT", "").strip()
    if override:
        return Path(override).resolve()
    return Path(__file__).resolve().parents[2]


def write_jsonl(log_path: Path, event: dict) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(event, separators=(",", ":")) + "\n")


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
    repo_root = get_repo_root()
    sessions_root = repo_root / ".ralph-sessions"
    active_pointer = sessions_root / ".active-session"

    if not active_pointer.exists():
        return 0

    session_id = active_pointer.read_text(encoding="utf-8").strip()
    if not session_id or not SESSION_ID_PATTERN.match(session_id):
        return 0

    session_path = sessions_root / session_id
    metadata_path = session_path / "metadata.yaml"
    log_path = session_path / "logs" / "hook-finalization.jsonl"
    lock_path = session_path / ".finalize.lock"

    if not session_path.exists():
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
