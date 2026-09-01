#!/usr/bin/env python3
"""Read-only checker: assert a file exists. Exit 0 if present, 1 otherwise.

Usage: check_file.py <path>
"""
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 2:
        print("usage: check_file.py <path>", file=sys.stderr)
        return 2
    p = Path(sys.argv[1])
    if p.exists():
        print(f"ok: {p}")
        return 0
    print(f"missing: {p}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())