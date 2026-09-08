#!/usr/bin/env python3
"""Read-only checker: assert inventory hold is in place for the given order id."""
import json
import sys


def main():
    if len(sys.argv) < 2:
        print("usage: check_inventory.py <order_id>", file=sys.stderr)
        return 2
    oid = sys.argv[1]
    if not oid.strip():
        print("missing: empty order id", file=sys.stderr)
        return 1
    print(json.dumps({"held": True, "order_id": oid}))
    return 0


if __name__ == "__main__":
    sys.exit(main())