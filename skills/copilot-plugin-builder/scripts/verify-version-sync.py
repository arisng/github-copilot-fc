#!/usr/bin/env python3
"""Verify that marketplace.json entries stay aligned with their plugin.json manifests.

Checks:
    * entry "version" (when present) matches plugin.json "version"
    * entry "name" matches plugin.json "name"
    * entry "description" matches plugin.json "description" (warning)
    * entry "source" resolves to a plugin.json (warning)
    * local plugin directories with no marketplace entry — orphans (warning)

Usage:
    python3 verify-version-sync.py <marketplace-dir>

The marketplace-dir should contain .github/plugin/marketplace.json (or
.claude-plugin/marketplace.json) and the plugin directories referenced
by each plugin's "source" field.

Exit codes:
    0 — All entries aligned (warnings may have been printed)
    1 — Drift detected (version or name mismatch)
    2 — Structural error (missing files, parse failure)
"""

import json
import sys
from pathlib import Path


def find_marketplace_json(base: Path) -> Path | None:
    """Locate marketplace.json in canonical or fallback locations."""
    for rel in [".github/plugin/marketplace.json", ".claude-plugin/marketplace.json"]:
        p = base / rel
        if p.is_file():
            return p
    return None


def resolve_plugin_json(marketplace_dir: Path, source: str) -> Path | None:
    """Resolve a plugin source path to its plugin.json."""
    # Strip leading ./ or /
    source = source.lstrip("./")
    plugin_dir = marketplace_dir / source
    plugin_json = plugin_dir / "plugin.json"
    return plugin_json if plugin_json.is_file() else None


def find_orphans(marketplace_dir: Path, referenced: set[Path]) -> list[str]:
    """Local plugin.json files that no marketplace entry claims.

    Scans plugins/ when it exists (skipping hidden directories such as
    .claude-plugin/ plus vendored trees), otherwise the repo-root manifest
    for a single-plugin repo.
    """
    plugins_root = marketplace_dir / "plugins"
    if plugins_root.is_dir():
        candidates = [
            p
            for p in plugins_root.rglob("plugin.json")
            if not any(
                part.startswith(".") or part in {"node_modules", "vendor"}
                for part in p.relative_to(marketplace_dir).parts
            )
        ]
    else:
        root_manifest = marketplace_dir / "plugin.json"
        candidates = [root_manifest] if root_manifest.is_file() else []

    return [
        str(p.relative_to(marketplace_dir))
        for p in candidates
        if p.resolve() not in referenced
    ]


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <marketplace-dir>", file=sys.stderr)
        return 2

    marketplace_dir = Path(sys.argv[1]).resolve()
    if not marketplace_dir.is_dir():
        print(f"Error: {marketplace_dir} is not a directory", file=sys.stderr)
        return 2

    # Find marketplace.json
    mkt_path = find_marketplace_json(marketplace_dir)
    if mkt_path is None:
        print(
            f"Error: No marketplace.json found in {marketplace_dir} "
            "(looked in .github/plugin/ and .claude-plugin/)",
            file=sys.stderr,
        )
        return 2

    try:
        with open(mkt_path, encoding="utf-8") as f:
            mkt = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"Error: Failed to parse {mkt_path}: {e}", file=sys.stderr)
        return 2

    plugins = mkt.get("plugins", [])
    if not plugins:
        print("No plugins defined in marketplace.json — nothing to check.")
        return 0

    mismatches = []
    name_mismatches = []
    description_drift = []
    missing = []
    referenced: set[Path] = set()

    for entry in plugins:
        name = entry.get("name", "<unnamed>")
        mkt_version = entry.get("version")
        source = entry.get("source")

        if source is None:
            missing.append((name, "no source field"))
            continue

        # Source can be a string or an object
        if isinstance(source, dict):
            # GitHub/URL source — can't verify local plugin.json
            continue

        plugin_json = resolve_plugin_json(marketplace_dir, source)
        if plugin_json is None:
            missing.append((name, f"plugin.json not found at {source}/plugin.json"))
            continue

        referenced.add(plugin_json.resolve())

        try:
            with open(plugin_json, encoding="utf-8") as f:
                plugin = json.load(f)
        except (json.JSONDecodeError, OSError) as e:
            missing.append((name, f"failed to parse {plugin_json}: {e}"))
            continue

        plugin_name = plugin.get("name")
        if plugin_name and plugin_name != name:
            name_mismatches.append((name, plugin_name, str(plugin_json)))

        entry_desc = entry.get("description")
        plugin_desc = plugin.get("description")
        if entry_desc and plugin_desc and entry_desc != plugin_desc:
            description_drift.append((name, str(plugin_json)))

        if mkt_version is None:
            # No version in marketplace entry — skip (version is optional)
            continue

        plugin_version = plugin.get("version")
        if plugin_version is None:
            missing.append((name, f"no version field in {plugin_json}"))
            continue

        if mkt_version != plugin_version:
            mismatches.append((name, mkt_version, plugin_version, str(plugin_json)))

    orphans = find_orphans(marketplace_dir, referenced)

    # Report
    if missing:
        print("\nWARN Warnings (could not verify):")
        for name, reason in missing:
            print(f"  - {name}: {reason}")

    if description_drift:
        print("\nWARN Description divergence (marketplace entry vs plugin.json):")
        for name, path in description_drift:
            print(f"  - {name}: {path}")

    if orphans:
        print("\nWARN Orphan plugin(s) — local plugin.json with no marketplace entry:")
        for path in orphans:
            print(f"  - {path}")

    if name_mismatches:
        print("\nFAIL Entry name does not match plugin.json:")
        for name, plugin_name, path in name_mismatches:
            print(f"  - marketplace entry {name!r} vs plugin.json {plugin_name!r}: {path}")

    if mismatches:
        print("\nFAIL Version drift detected:")
        print(f"  {'Plugin':<20} {'marketplace.json':<18} {'plugin.json':<18} Path")
        print(f"  {'-'*20} {'-'*18} {'-'*18} {'-'*40}")
        for name, mkt_v, plug_v, path in mismatches:
            print(f"  {name:<20} {mkt_v:<18} {plug_v:<18} {path}")
        print("\nFix: Update both files to the same version, then commit atomically.")

    if name_mismatches or mismatches:
        return 1

    if not missing and not description_drift and not orphans:
        print(f"OK All {len(plugins)} plugin entry/manifest pairs aligned.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
