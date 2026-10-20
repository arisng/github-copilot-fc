#!/usr/bin/env python3
"""Browse the tool names a custom agent's `tools:` frontmatter accepts.

Every runtime spells the same `tools:` field differently. This script reads the
bundled runtime vocabulary and answers four questions:

    list     Which names does this runtime accept, and what is each for?
    profile  What is the minimal allowlist for a capability intent?
    check    Is this candidate list valid, and what is wrong with it?
    mcp      How do I name one tool, or a whole server, from an MCP server?

Usage:
    python3 browse_tools.py list --runtime cli
    python3 browse_tools.py list --runtime vscode --kind alias
    python3 browse_tools.py profile --runtime cli --profile read-only --format yaml
    python3 browse_tools.py check --runtime cli --names "view,search,create"
    python3 browse_tools.py mcp --runtime cli --server github-mcp-server

Exit codes: 0 success, 1 validation failure, 2 usage error.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    print("PyYAML is required: pip install pyyaml", file=sys.stderr)
    sys.exit(2)

VOCAB_PATH = Path(__file__).resolve().parent.parent / "references" / "runtime-vocabularies.yaml"

WILDCARD = "*"
EVIDENCE_ORDER = {"shipped": 0, "documented": 1, "reported": 2, "rejected": 3}


def load_vocab(path: Path | None = None) -> dict:
    p = path or VOCAB_PATH
    if not p.exists():
        print(f"vocabulary not found: {p}", file=sys.stderr)
        sys.exit(2)
    with p.open(encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    if not data or "runtimes" not in data:
        print(f"malformed vocabulary: {p}", file=sys.stderr)
        sys.exit(2)
    return data


def get_runtime(vocab: dict, name: str) -> dict:
    runtimes = vocab["runtimes"]
    if name not in runtimes:
        known = ", ".join(sorted(runtimes))
        print(f"unknown runtime '{name}'. Known runtimes: {known}", file=sys.stderr)
        sys.exit(2)
    return runtimes[name]


def split_names(raw: str) -> list[str]:
    """Accept comma or whitespace separated names, and drop YAML list syntax."""
    cleaned = raw.strip().strip("[]")
    parts = [p.strip().strip("'\"") for p in cleaned.replace("\n", ",").split(",")]
    return [p for p in parts if p]


def classify(name: str, rt: dict) -> tuple[str, dict | None]:
    """Return (verdict, metadata) for one candidate name in this runtime.

    verdicts: ok | advisory | rejected | mcp | unknown
    """
    names = rt.get("names") or {}
    if name == WILDCARD:
        return "advisory", {"kind": "wildcard", "evidence": "documented", "purpose": "Grant every tool"}
    if not rt.get("case_sensitive", True):
        lowered = {k.lower(): k for k in names}
        if name.lower() in lowered:
            meta = names[lowered[name.lower()]]
            return _verdict(meta), meta
    if name in names:
        meta = names[name]
        return _verdict(meta), meta
    # MCP form: serverName/toolName or serverName/*
    if "/" in name:
        return "mcp", None
    return "unknown", None


def _verdict(meta: dict) -> str:
    evidence = meta.get("evidence")
    if evidence == "rejected":
        return "rejected"
    if evidence == "reported":
        return "advisory"
    return "ok"


def cmd_list(args, vocab) -> int:
    rt = get_runtime(vocab, args.runtime)
    names = rt.get("names") or {}
    if args.kind:
        names = {k: v for k, v in names.items() if v.get("kind") == args.kind}
    if args.evidence:
        names = {
            k: v
            for k, v in names.items()
            if v.get("evidence") in args.evidence
        }
    rows = sorted(
        names.items(),
        key=lambda kv: (EVIDENCE_ORDER.get(kv[1].get("evidence"), 9), kv[0].lower()),
    )
    if args.format == "json":
        print(json.dumps({k: v for k, v in rows}, indent=2))
        return 0
    print(f"{rt['label']}  (evidence: {', '.join(sorted(set(args.evidence))) if args.evidence else 'all'})")
    print(f"case sensitive: {rt.get('case_sensitive', True)}")
    print()
    width = max((len(k) for k, _ in rows), default=4)
    for key, meta in rows:
        meta = meta or {}
        caution = meta.get("caution")
        line = f"  {key.ljust(width)}  {meta.get('kind', '?'):<9} {meta.get('evidence', '?'):<11} {meta.get('purpose', '')}"
        print(line)
        if caution:
            print(f"  {'':<{width}}  ! caution: {caution}")
    if rt.get("tool_sets"):
        print("\n  tool sets:")
        for set_name, members in rt["tool_sets"].items():
            print(f"    {set_name}: {', '.join(members)}")
    mcp = rt.get("mcp") or {}
    if mcp:
        print(f"\n  MCP form: {mcp.get('form')}  example: {mcp.get('example')}")
        if mcp.get("note"):
            print(f"  {mcp['note'].strip()}")
    return 0


def cmd_profile(args, vocab) -> int:
    profiles = vocab.get("profiles") or {}
    if args.profile not in profiles:
        known = ", ".join(sorted(profiles))
        print(f"unknown profile '{args.profile}'. Known: {known}", file=sys.stderr)
        sys.exit(2)
    prof = profiles[args.profile]
    rt = get_runtime(vocab, args.runtime)
    key = args.runtime
    if key not in prof:
        print(f"profile '{args.profile}' has no list for runtime '{args.runtime}'", file=sys.stderr)
        sys.exit(2)
    names = prof[key]
    if args.format == "json":
        print(json.dumps({"profile": args.profile, "runtime": args.runtime, "tools": names}, indent=2))
        return 0
    if args.format == "yaml":
        print("tools: [" + ", ".join(names) + "]")
        return 0
    print(f"profile : {args.profile}")
    print(f"intent  : {prof.get('description', '')}")
    print(f"runtime : {rt['label']}")
    print(f"tools   : [{', '.join(names)}]")
    for n in names:
        status, meta = classify(n, rt)
        purpose = (meta or {}).get("purpose", "")
        print(f"    {n:<16} {status:<7} {purpose}")
    return 0


def cmd_check(args, vocab) -> int:
    rt = get_runtime(vocab, args.runtime)
    names = split_names(args.names)
    if not names:
        print("no names supplied", file=sys.stderr)
        sys.exit(2)

    problems = []
    if WILDCARD in names:
        problems.append(
            "'*' grants every tool. A list like [\"view\", \"*\"] is unrestricted, "
            "not a restricted list. Remove '*' to scope the agent."
        )
    for n in names:
        verdict, meta = classify(n, rt)
        if verdict == "unknown":
            problems.append(f"'{n}' is not a known tool name for {rt['label']}.")
        elif verdict == "advisory" and n != WILDCARD:
            problems.append(
                f"'{n}' is a documented built-in but no shipped agent uses it. "
                "Prefer the alias that covers the same capability."
            )
        elif verdict == "rejected":
            problems.append(f"'{n}' has no effect in {rt['label']}. Remove it.")

    if args.format == "json":
        print(json.dumps({
            "runtime": args.runtime,
            "names": names,
            "problems": problems,
            "ok": not problems,
        }, indent=2))
        return 0 if not problems else 1

    print(f"runtime : {rt['label']}")
    for n in names:
        verdict, meta = classify(n, rt)
        meta = meta or {}
        mark = {
            "ok": "OK      ",
            "advisory": "ADVISORY",
            "rejected": "REJECTED",
            "mcp": "MCP     ",
            "unknown": "UNKNOWN ",
        }.get(verdict, "UNKNOWN ")
        extra = f"  [{meta.get('evidence')}] {meta.get('purpose', '')}" if meta else ""
        if verdict == "mcp":
            extra = "  MCP server tool, verify the server and tool exist"
        print(f"  {n:<34} {mark}{extra}")
    if problems:
        print("\nproblems:")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("\nno problems found")
    return 0


def cmd_mcp(args, vocab) -> int:
    rt = get_runtime(vocab, args.runtime)
    mcp = rt.get("mcp") or {}
    print(f"runtime : {rt['label']}")
    print(f"form    : {mcp.get('form', 'serverName/toolName')}")
    if args.server:
        print(f"one tool: {args.server}/{args.tool}" if args.tool else f"whole server: {args.server}/*")
    if mcp.get("note"):
        print()
        print(mcp["note"].strip())
    return 0


def cmd_runtimes(args, vocab) -> int:
    for key, rt in sorted(vocab["runtimes"].items()):
        count = len(rt.get("names") or {})
        print(f"{key:<18} {count:>3} names  {rt.get('label', '')}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--vocab", type=Path, help="override the runtime vocabulary path")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("runtimes", help="list the runtimes this script knows")
    p.set_defaults(fn=cmd_runtimes)

    p = sub.add_parser("list", help="list valid tool names for a runtime")
    p.add_argument("--runtime", required=True)
    p.add_argument("--kind", choices=["alias", "built-in", "namespace"])
    p.add_argument("--evidence", action="append", choices=["shipped", "documented", "reported", "rejected"])
    p.add_argument("--format", choices=["text", "json"], default="text")
    p.set_defaults(fn=cmd_list)

    p = sub.add_parser("profile", help="emit the minimal allowlist for a capability intent")
    p.add_argument("--runtime", required=True)
    p.add_argument("--profile", required=True)
    p.add_argument("--format", choices=["text", "yaml", "json"], default="text")
    p.set_defaults(fn=cmd_profile)

    p = sub.add_parser("check", help="validate a candidate tools list")
    p.add_argument("--runtime", required=True)
    p.add_argument("--names", required=True, help="comma or space separated names")
    p.add_argument("--format", choices=["text", "json"], default="text")
    p.set_defaults(fn=cmd_check)

    p = sub.add_parser("mcp", help="how to name MCP server tools")
    p.add_argument("--runtime", required=True)
    p.add_argument("--server")
    p.add_argument("--tool")
    p.set_defaults(fn=cmd_mcp)

    args = ap.parse_args()
    vocab = load_vocab(args.vocab)
    return args.fn(args, vocab)


if __name__ == "__main__":
    sys.exit(main())
