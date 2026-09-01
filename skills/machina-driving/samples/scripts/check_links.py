#!/usr/bin/env python3
"""Read-only checker: assert a markdown file has no broken links.

Usage: check_links.py <path>
Prints a JSON object on stdout: {"valid": bool, "broken": int}
"""
import json
import re
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 2:
        print("usage: check_links.py <path>", file=sys.stderr)
        return 2
    p = Path(sys.argv[1])
    if not p.exists():
        print(json.dumps({"valid": False, "broken": 1}))
        return 1
    text = p.read_text(encoding="utf-8", errors="replace")
    links = re.findall(r"\[[^\]]*\]\(([^)]+)\)", text)
    broken = 0
    for link in links:
        if link.startswith(("http://", "https://", "#")):
            continue
        target = (p.parent / link).resolve()
        if not target.exists():
            broken += 1
    valid = broken == 0
    print(json.dumps({"valid": valid, "broken": broken}))
    return 0 if valid else 1


if __name__ == "__main__":
    sys.exit(main())