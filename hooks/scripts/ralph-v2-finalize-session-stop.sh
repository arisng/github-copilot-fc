#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v python >/dev/null 2>&1; then
	python "$SCRIPT_DIR/ralph-v2-finalize-session-stop.py"
fi
