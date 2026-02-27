#!/usr/bin/env python
"""Bind chat hook session IDs to Ralph session IDs from user input hints."""

from __future__ import annotations

import json
import os
import re
import sys
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


def read_payload() -> dict:
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


def extract_candidate_text(payload: dict) -> str:
    parts: list[str] = []
    for key in ("prompt", "userPrompt", "message", "text", "input"):
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            parts.append(value)
    return "\n".join(parts)


def find_session_id(text: str, sessions_root: Path) -> str | None:
    if not text:
        return None
    candidates = [m.group(0) for m in SESSION_ID_IN_TEXT.finditer(text)]
    for candidate in reversed(candidates):
        if SESSION_ID_PATTERN.match(candidate) and (sessions_root / candidate).exists():
            return candidate
    return None


def main() -> int:
    payload = read_payload()
    hook_event = str(payload.get("hookEventName", "")).strip()
    if hook_event and hook_event != "UserPromptSubmit":
        return 0

    hook_session_id = str(payload.get("sessionId", "")).strip()
    if not hook_session_id:
        return 0

    repo_root = get_repo_root()
    sessions_root = repo_root / ".ralph-sessions"
    bindings_dir = sessions_root / ".hook-bindings"
    bindings_dir.mkdir(parents=True, exist_ok=True)

    text = extract_candidate_text(payload)
    ralph_session_id = find_session_id(text, sessions_root)
    if not ralph_session_id:
        return 0

    marker = sessions_root / ralph_session_id / ".hook-enabled"
    if not marker.exists():
        return 0

    binding = {
        "ralph_session_id": ralph_session_id,
        "updated_at": iso_now(),
        "source": "user_prompt",
    }
    binding_path = bindings_dir / f"{hook_session_id}.json"
    binding_path.write_text(json.dumps(binding, separators=(",", ":")), encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
