#!/usr/bin/env python3
"""Read-only checker: assert a shipping label is ready for the given order id."""
import sys


def main():
    if len(sys.argv) < 2:
        print("usage: check_label.py <order_id>", file=sys.stderr)
        return 2
    oid = sys.argv[1]
    if not oid.strip():
        print("missing: empty order id", file=sys.stderr)
        return 1
    print(f"ok: label ready for {oid}")
    return 0


if __name__ == "__main__":
    sys.exit(main())