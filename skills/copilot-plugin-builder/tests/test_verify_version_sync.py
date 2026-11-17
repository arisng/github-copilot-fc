"""Tests for scripts/verify-version-sync.py.

Covers the catalog-maintenance checks: version sync, name mirror, description
divergence, orphan detection, the omitted-version convention, and structural
errors. Run with: python3 -m pytest skills -q
"""

import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "verify-version-sync.py"


def run_check(base: Path) -> tuple[int, str]:
    result = subprocess.run(
        [sys.executable, str(SCRIPT), str(base)],
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout + result.stderr


def write_marketplace(base: Path, entries: list[dict]) -> None:
    catalog_dir = base / ".github" / "plugin"
    catalog_dir.mkdir(parents=True, exist_ok=True)
    catalog = {"name": "test-market", "owner": {"name": "T"}, "plugins": entries}
    (catalog_dir / "marketplace.json").write_text(json.dumps(catalog), encoding="utf-8")


def write_plugin(
    base: Path,
    rel: str,
    name: str,
    version: str,
    description: str,
    host_manifest: bool = False,
) -> None:
    plugin_dir = base / rel
    plugin_dir.mkdir(parents=True, exist_ok=True)
    manifest = {"name": name, "version": version, "description": description}
    (plugin_dir / "plugin.json").write_text(json.dumps(manifest), encoding="utf-8")
    if host_manifest:
        hidden = plugin_dir / ".claude-plugin"
        hidden.mkdir(parents=True, exist_ok=True)
        (hidden / "plugin.json").write_text(
            json.dumps({"name": "host", "version": "0"}), encoding="utf-8"
        )


def entry(name: str, source, version: str | None = None, description: str | None = None) -> dict:
    result = {"name": name, "source": source}
    if version is not None:
        result["version"] = version
    if description is not None:
        result["description"] = description
    return result


def test_aligned_entries_pass(tmp_path: Path) -> None:
    write_plugin(tmp_path, "plugins/alpha", "alpha", "1.0.0", "Alpha plugin")
    write_plugin(tmp_path, "plugins/beta", "beta", "2.1.0", "Beta plugin")
    write_marketplace(
        tmp_path,
        [
            entry("alpha", "./plugins/alpha", "1.0.0", "Alpha plugin"),
            entry("beta", "./plugins/beta", "2.1.0", "Beta plugin"),
        ],
    )
    code, out = run_check(tmp_path)
    assert code == 0, out
    assert "OK" in out


def test_version_drift_fails(tmp_path: Path) -> None:
    write_plugin(tmp_path, "plugins/alpha", "alpha", "1.0.0", "A")
    write_marketplace(
        tmp_path, [entry("alpha", "./plugins/alpha", "0.9.0", "A")]
    )
    code, out = run_check(tmp_path)
    assert code == 1, out
    assert "Version drift" in out


def test_name_mismatch_fails(tmp_path: Path) -> None:
    write_plugin(tmp_path, "plugins/gamma", "gamma", "1.0.0", "G")
    write_marketplace(
        tmp_path, [entry("gamma-x", "./plugins/gamma", "1.0.0", "G")]
    )
    code, out = run_check(tmp_path)
    assert code == 1, out
    assert "Entry name" in out


def test_orphan_and_description_divergence_warn_but_pass(tmp_path: Path) -> None:
    write_plugin(tmp_path, "plugins/alpha", "alpha", "1.0.0", "Real alpha")
    write_plugin(tmp_path, "plugins/hidden", "hidden", "1.0.0", "H")
    write_marketplace(
        tmp_path, [entry("alpha", "./plugins/alpha", "1.0.0", "Different text")]
    )
    code, out = run_check(tmp_path)
    assert code == 0, out
    assert "Orphan" in out
    assert "Description divergence" in out
    assert "hidden" in out


def test_omitted_entry_version_passes(tmp_path: Path) -> None:
    write_plugin(tmp_path, "plugins/alpha", "alpha", "1.7.3", "A")
    write_marketplace(tmp_path, [entry("alpha", "./plugins/alpha", description="A")])
    code, out = run_check(tmp_path)
    assert code == 0, out
    assert "OK" in out


def test_missing_marketplace_is_structural_error(tmp_path: Path) -> None:
    code, _ = run_check(tmp_path)
    assert code == 2


def test_single_plugin_root_source(tmp_path: Path) -> None:
    write_plugin(tmp_path, ".", "solo", "1.0.0", "Solo")
    write_marketplace(
        tmp_path, [entry("solo", "./", "1.0.0", "Solo")]
    )
    code, out = run_check(tmp_path)
    assert code == 0, out
    assert "OK" in out


def test_hidden_host_manifest_not_counted_as_orphan(tmp_path: Path) -> None:
    write_plugin(
        tmp_path, "plugins/alpha", "alpha", "1.0.0", "A", host_manifest=True
    )
    write_marketplace(tmp_path, [entry("alpha", "./plugins/alpha", "1.0.0", "A")])
    code, out = run_check(tmp_path)
    assert code == 0, out
    assert "Orphan" not in out


def test_remote_source_skipped_without_local_verification(tmp_path: Path) -> None:
    write_marketplace(
        tmp_path,
        [
            entry(
                "remote-plugin",
                {"source": "github", "repo": "o/r", "path": "plugins/remote-plugin"},
                "1.0.0",
            )
        ],
    )
    code, out = run_check(tmp_path)
    assert code == 0, out
