#!/usr/bin/env python3
"""Generate the Skill Catalog table in skills/README.md (plan W2.4).

The catalog lives between these markers in skills/README.md:

    <!-- SKILLS-CATALOG:BEGIN -->
    ...generated table...
    <!-- SKILLS-CATALOG:END -->

Modes:
    (default)  rewrite the block from skills/*/SKILL.md frontmatter (idempotent)
    --check    exit 1 when the committed block differs from the generated one
               (wired into scripts/workspace/check-consistency.ps1)

Rows: | `name` | metadata.version | description (folded to one line, 160 chars) |
Sorted by name; descriptions pipe-escaped. Stdlib + PyYAML only.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
README = REPO / "skills" / "README.md"
BEGIN = "<!-- SKILLS-CATALOG:BEGIN -->"
END = "<!-- SKILLS-CATALOG:END -->"
DESC_LIMIT = 160


def build_catalog() -> tuple[str, int]:
    rows: list[tuple[str, str, str]] = []
    for skill_dir in sorted((REPO / "skills").iterdir(), key=lambda p: p.name.lower()):
        skill_md = skill_dir / "SKILL.md"
        if not skill_dir.is_dir() or skill_dir.name.startswith(".") or not skill_md.exists():
            continue
        text = skill_md.read_text(encoding="utf-8-sig")
        if not text.startswith("---"):
            continue
        try:
            data = yaml.safe_load(text.split("---", 2)[1])
        except yaml.YAMLError:
            continue
        if not isinstance(data, dict) or "name" not in data:
            continue
        metadata = data.get("metadata")
        version = str(metadata.get("version", "")) if isinstance(metadata, dict) else ""
        desc = " ".join(str(data.get("description", "")).split())
        if len(desc) > DESC_LIMIT:
            desc = desc[: DESC_LIMIT - 1].rsplit(" ", 1)[0] + "…"
        desc = desc.replace("|", "\\|")
        rows.append((str(data["name"]), version, desc))

    lines = ["| Skill | Version | Description |", "|---|---|---|"]
    lines += [f"| `{name}` | {version} | {desc} |" for name, version, desc in rows]
    return "\n".join(lines), len(rows)


def main() -> int:
    if not README.exists():
        print("[FAIL] skills/README.md not found")
        return 1
    text = README.read_text(encoding="utf-8")
    if BEGIN not in text or END not in text:
        print(f"[FAIL] skills/README.md is missing the {BEGIN} / {END} markers")
        return 1

    catalog, count = build_catalog()
    pattern = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END), re.DOTALL)
    committed = pattern.search(text).group(0)
    normalized = lambda s: s.replace("\r\n", "\n").strip()  # noqa: E731

    if "--check" in sys.argv:
        if normalized(committed) != normalized(f"{BEGIN}\n{catalog}\n{END}"):
            print("[FAIL] skills catalog is stale - run: python3 scripts/workspace/generate-skills-catalog.py")
            return 1
        print(f"[PASS] skills catalog up to date ({count} skill(s))")
        return 0

    updated = pattern.sub(lambda _: f"{BEGIN}\n{catalog}\n{END}", text, count=1)
    if updated.replace("\r\n", "\n") == text.replace("\r\n", "\n"):
        print(f"[PASS] skills catalog already current ({count} skill(s))")
        return 0
    README.write_text(updated, encoding="utf-8", newline="\n")
    print(f"[PASS] skills catalog regenerated ({count} skill(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
