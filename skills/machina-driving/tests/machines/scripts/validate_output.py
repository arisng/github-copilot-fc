#!/usr/bin/env python3
"""Read-only checker: validate output file and report error count.
Prints JSON: {"errors": <count>}"""
import json, sys
from pathlib import Path

def main():
    if len(sys.argv) < 2:
        print("usage: validate_output.py <path>", file=sys.stderr)
        return 2
    p = Path(sys.argv[1])
    if not p.exists():
        print(json.dumps({"errors": 1}))
        return 1
    text = p.read_text(encoding="utf-8", errors="replace")
    errors = text.lower().count("error")
    print(json.dumps({"errors": errors}))
    return 0 if errors == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
