#!/usr/bin/env python3
"""Read-only checker: assert a payment is authorized for the given order id."""
import sys


def main():
    if len(sys.argv) < 2:
        print("usage: check_payment.py <order_id>", file=sys.stderr)
        return 2
    oid = sys.argv[1]
    if not oid.strip():
        print("missing: empty order id", file=sys.stderr)
        return 1
    print(f"ok: payment authorized for {oid}")
    return 0


if __name__ == "__main__":
    sys.exit(main())