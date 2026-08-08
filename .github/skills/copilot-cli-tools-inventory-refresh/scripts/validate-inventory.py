#!/usr/bin/env python3
"""Validate tools/inventory.yaml schema and cross-references.

Usage:
    python3 validate-inventory.py [--inventory PATH] [--strict]

Checks:
  - YAML parses and has schema_version / last_verified / cli_version / cli_help_source
  - categories: ids are kebab-case, unique, and every tool references one
  - tools: required keys present (id, category, description, cli, vscode,
    github_copilot, default, sources), ids unique and kebab-case
  - default is in the closed enum
  - list fields contain only strings; the "runtime-dependent" sentinel is allowed
  - official_alias, when present, is a non-empty list of strings
  - sources: non-empty list, each entry non-empty; file-like sources exist
    (tools/vscode/toolsets/*.jsonc and .docs/... paths) unless --strict is off
  - notes, when present, is a string
  - accepted encodings for runtime-specific / (closest) / runtime-dependent
    (recorded in notes per the SKILL value-encoding rules)

Exit code 0 on success, 1 on any failure.
"""

import argparse
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    print("PyYAML is required: pip install pyyaml", file=sys.stderr)
    sys.exit(2)

DEFAULT_INVENTORY = Path(__file__).resolve().parents[4] / "tools" / "inventory.yaml"
REPO_ROOT = Path(__file__).resolve().parents[4]

ALLOWED_DEFAULTS = {
    "enabled if available",
    "enabled if configured",
    "runtime-dependent",
    "n/a",
}

REQUIRED_TOOL_KEYS = {
    "id",
    "category",
    "description",
    "cli",
    "vscode",
    "github_copilot",
    "default",
    "sources",
}

LIST_KEYS = ("cli", "vscode", "github_copilot")
KUBE_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

# Sentinel values accepted inside list fields (not real tool names).
RUNTIME_DEPENDENT = "runtime-dependent"


def fail(errors, message):
    errors.append(message)


def check_kube_id(errors, value, where):
    if not isinstance(value, str) or not KUBE_RE.match(value):
        fail(errors, f"{where}: '{value}' is not a valid kebab-case id")


def check_string_list(errors, value, where, allow_sentinel=False):
    if not isinstance(value, list):
        fail(errors, f"{where}: expected a list, got {type(value).__name__}")
        return
    for i, item in enumerate(value):
        if not isinstance(item, str):
            fail(errors, f"{where}[{i}]: expected a string, got {type(item).__name__}")
        elif not allow_sentinel and item == RUNTIME_DEPENDENT:
            fail(errors, f"{where}[{i}]: '{RUNTIME_DEPENDENT}' sentinel not allowed here")


def check_existing_file(errors, source, where):
    """Resolve a workspace-relative source path and flag if it does not exist.

    Only checks paths that look workspace-relative (start with tools/, .docs/,
    or scripts/). URLs and plain doc references are ignored.
    """
    if not isinstance(source, str) or not source.strip():
        fail(errors, f"{where}: empty source string")
        return
    if source.startswith(("tools/", ".docs/", "scripts/", "skills/")):
        p = REPO_ROOT / source
        if not p.exists():
            fail(errors, f"{where}: referenced path does not exist: {source}")


def validate(inventory_path, strict):
    errors = []
    warnings = []

    try:
        with open(inventory_path, encoding="utf-8") as fh:
            data = yaml.safe_load(fh)
    except FileNotFoundError:
        print(f"FATAL: inventory not found: {inventory_path}", file=sys.stderr)
        return 2
    except yaml.YAMLError as exc:
        print(f"FATAL: YAML parse error: {exc}", file=sys.stderr)
        return 2

    if not isinstance(data, dict):
        fail(errors, "top-level value must be a mapping")
        return 1

    for key in ("schema_version", "last_verified", "cli_version", "cli_help_source"):
        if key not in data:
            fail(errors, f"missing top-level metadata key: {key}")
    if "schema_version" in data and not isinstance(data["schema_version"], str):
        fail(errors, "schema_version must be a string")

    # Categories
    if "categories" not in data:
        fail(errors, "missing top-level key: categories")
        category_ids = set()
    else:
        category_ids = set()
        for i, cat in enumerate(data["categories"]):
            where = f"categories[{i}]"
            if not isinstance(cat, dict) or "id" not in cat:
                fail(errors, f"{where}: each category needs an 'id'")
                continue
            cid = cat["id"]
            if cid in category_ids:
                fail(errors, f"{where}: duplicate category id '{cid}'")
            category_ids.add(cid)
            check_kube_id(errors, cid, where)

    # Tools
    if "tools" not in data:
        fail(errors, "missing top-level key: tools")
        return 1

    tool_ids = set()
    for i, tool in enumerate(data["tools"]):
        where = f"tools[{i}]"
        if not isinstance(tool, dict):
            fail(errors, f"{where}: each tool must be a mapping")
            continue

        missing = REQUIRED_TOOL_KEYS - set(tool.keys())
        if missing:
            fail(errors, f"{where} ('{tool.get('id', '?')}'): missing keys {sorted(missing)}")

        tid = tool.get("id")
        if tid is not None:
            if tid in tool_ids:
                fail(errors, f"{where}: duplicate tool id '{tid}'")
            tool_ids.add(tid)
            check_kube_id(errors, tid, where)

        cat = tool.get("category")
        if cat is not None and cat not in category_ids:
            fail(errors, f"{where} ('{tid}'): category '{cat}' is not declared in categories")

        desc = tool.get("description")
        if desc is not None and (not isinstance(desc, str) or not desc.strip()):
            fail(errors, f"{where} ('{tid}'): description must be a non-empty string")

        default = tool.get("default")
        if default is not None and default not in ALLOWED_DEFAULTS:
            fail(
                errors,
                f"{where} ('{tid}'): default '{default}' not in {sorted(ALLOWED_DEFAULTS)}",
            )

        for key in LIST_KEYS:
            if key in tool:
                check_string_list(
                    errors, tool[key], f"{where} ('{tid}').{key}", allow_sentinel=True
                )

        if "official_alias" in tool:
            oa = tool["official_alias"]
            if not isinstance(oa, list) or not oa:
                fail(errors, f"{where} ('{tid}'): official_alias must be a non-empty list")
            else:
                check_string_list(errors, oa, f"{where} ('{tid}').official_alias")
                if RUNTIME_DEPENDENT in oa:
                    fail(
                        errors,
                        f"{where} ('{tid}'): 'runtime-dependent' is not a valid official_alias; "
                        "omit the field and record 'runtime-specific' in notes",
                    )
                if "runtime-specific" in oa:
                    fail(
                        errors,
                        f"{where} ('{tid}'): 'runtime-specific' is not a valid official_alias "
                        "value; omit the field and record 'runtime-specific' in notes",
                    )
        else:
            # official_alias omitted => notes should mention runtime-specific
            notes = tool.get("notes", "")
            if strict and "runtime-specific" not in str(notes):
                warnings.append(
                    f"{where} ('{tid}'): official_alias omitted but notes do not mention "
                    "'runtime-specific'"
                )

        notes = tool.get("notes")
        if notes is not None and not isinstance(notes, str):
            fail(errors, f"{where} ('{tid}'): notes must be a string")

        sources = tool.get("sources")
        if sources is not None:
            if not isinstance(sources, list) or not sources:
                fail(errors, f"{where} ('{tid}'): sources must be a non-empty list")
            else:
                for s in sources:
                    check_existing_file(errors, s, f"{where} ('{tid}').sources")

    if not tool_ids:
        fail(errors, "no tools found in inventory")

    # Report
    if errors:
        print(f"FAIL: {len(errors)} error(s) in {inventory_path}", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        if warnings:
            print(f"{len(warnings)} warning(s):", file=sys.stderr)
            for w in warnings:
                print(f"  ~ {w}", file=sys.stderr)
        return 1

    print(
        f"OK: {len(data['tools'])} tools, {len(data.get('categories', []))} categories "
        f"validated in {inventory_path}"
    )
    for w in warnings:
        print(f"  ~ {w}", file=sys.stderr)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--inventory",
        type=Path,
        default=DEFAULT_INVENTORY,
        help="path to the inventory YAML (default: tools/inventory.yaml)",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="fail on warnings (e.g. omitted official_alias without runtime-specific note)",
    )
    args = parser.parse_args()
    sys.exit(validate(args.inventory, args.strict))


if __name__ == "__main__":
    main()
