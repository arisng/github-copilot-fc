#!/usr/bin/env python3
"""Validate repo JSON artifacts against the schemas/ JSON Schemas.

Checks (each printed as PASS/FAIL with file:line detail):
  1. The schemas themselves are valid draft 2020-12 schemas.
  2. plugins/<runtime>/<name>/plugin.json  -> schemas/plugin.schema.json
  3. skills/<name>/SKILL.md YAML frontmatter -> schemas/skill.schema.json
  4. .github/plugin/marketplace.json (when present) -> schemas/marketplace.schema.json
5. instructions/*.instructions.md frontmatter: description (1-500 chars) + applyTo
   required (meta.instructions.md spec) — plan W3.1.

Exit 0 when everything validates, 1 on any validation failure,
2 on missing tooling (python3 jsonschema; PyYAML for frontmatter).

Design notes:
  - jsonschema + PyYAML are existing gate dependencies (skills pytest already
    requires PyYAML-level tooling); no new runtime is introduced.
  - Frontmatter is parsed with a real YAML parser: descriptions use folded
    scalars (>-) that a regex cannot read correctly.
  - This is the repo-green engine behind W1.1/W2.1 acceptance: every current
    artifact must validate clean for the gate to pass.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCHEMAS = {
    "plugin": REPO / "schemas" / "plugin.schema.json",
    "marketplace": REPO / "schemas" / "marketplace.schema.json",
    "skill": REPO / "schemas" / "skill.schema.json",
}

failures: list[str] = []


def fail(msg: str) -> None:
    failures.append(msg)
    print(f"[FAIL] {msg}")


def ok(msg: str) -> None:
    print(f"[PASS] {msg}")


def load_schema(name: str):
    import jsonschema

    path = SCHEMAS[name]
    try:
        schema = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"{path.relative_to(REPO)}: unreadable schema: {exc}")
        return None
    try:
        jsonschema.Draft202012Validator.check_schema(schema)
    except jsonschema.SchemaError as exc:
        fail(f"{path.relative_to(REPO)}: invalid schema: {exc.message}")
        return None
    return jsonschema.Draft202012Validator(schema)


def rel(path: Path) -> str:
    return str(path.relative_to(REPO)).replace("\\", "/")


def report(label: str, path: Path, errors) -> None:
    errors = sorted(errors, key=lambda e: list(e.absolute_path))
    if errors:
        for err in errors[:5]:
            loc = "/".join(str(p) for p in err.absolute_path) or "<root>"
            fail(f"{label} {rel(path)} [{loc}]: {err.message}")
        if len(errors) > 5:
            fail(f"{label} {rel(path)}: ...and {len(errors) - 5} more error(s)")
    else:
        ok(f"{label} {rel(path)}")


def split_frontmatter(text: str):
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    return text[3:end]


def main() -> int:
    try:
        import jsonschema  # noqa: F401
    except ImportError:
        print("[FAIL] python3 package 'jsonschema' is required (pip install jsonschema)")
        return 2

    validators = {name: load_schema(name) for name in SCHEMAS}
    if any(v is None for v in validators.values()):
        return 1

    # 2. Plugin manifests: source under plugins/ and release bundles under dist/
    manifests = sorted((REPO / "plugins").glob("*/*/plugin.json")) + sorted(
        (REPO / "dist").glob("plugins/*/*/plugin.json")
    )
    if not manifests:
        # Zero live plugins is now a legitimate state (all archived 2026-11-19):
        # schemas stay ready for the next plugin authored.
        print("[SKIP] no live plugin manifests (all plugins archived; schemas remain for the next one)")
    for manifest in manifests:
        try:
            # utf-8-sig: tolerate a BOM (copilot-vscode-docs/SKILL.md carries one).
            data = json.loads(manifest.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError) as exc:
            fail(f"plugin {rel(manifest)}: unreadable JSON: {exc}")
            continue
        report("plugin", manifest, validators["plugin"].iter_errors(data))

    # 3. Skill frontmatter
    try:
        import yaml
    except ImportError:
        print("[FAIL] python3 package 'PyYAML' is required for frontmatter parsing")
        return 2
    skills = sorted((REPO / "skills").glob("*/SKILL.md"))
    if not skills:
        fail("skills/*/SKILL.md: no skills found")
    for skill in skills:
        fm = split_frontmatter(skill.read_text(encoding="utf-8-sig"))
        if fm is None:
            fail(f"skill {rel(skill)}: missing or unterminated YAML frontmatter")
            continue
        try:
            data = yaml.safe_load(fm)
        except yaml.YAMLError as exc:
            fail(f"skill {rel(skill)}: invalid YAML frontmatter: {exc}")
            continue
        if not isinstance(data, dict):
            fail(f"skill {rel(skill)}: frontmatter is not a mapping")
            continue
        report("skill", skill, validators["skill"].iter_errors(data))

    # 4. Marketplace index (created by the distribution workstream)
    marketplace = REPO / ".github" / "plugin" / "marketplace.json"
    if marketplace.exists():
        try:
            data = json.loads(marketplace.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError) as exc:
            fail(f"marketplace {rel(marketplace)}: unreadable JSON: {exc}")
        else:
            report("marketplace", marketplace, validators["marketplace"].iter_errors(data))
    else:
        print("[SKIP] .github/plugin/marketplace.json not present (no live plugins; recreate alongside the next new plugin release)")

    # 5. Instruction frontmatter (meta.instructions.md spec: description 1-500 + applyTo)
    instructions = sorted((REPO / "instructions").glob("*.instructions.md"))
    if not instructions:
        fail("instructions/*.instructions.md: no instruction files found")
    for instr in instructions:
        fm = split_frontmatter(instr.read_text(encoding="utf-8-sig"))
        if fm is None:
            fail(f"instruction {rel(instr)}: missing or unterminated YAML frontmatter")
            continue
        try:
            data = yaml.safe_load(fm)
        except yaml.YAMLError as exc:
            fail(f"instruction {rel(instr)}: invalid YAML frontmatter: {exc}")
            continue
        if not isinstance(data, dict):
            fail(f"instruction {rel(instr)}: frontmatter is not a mapping")
            continue
        errs = []
        desc = data.get("description")
        if not isinstance(desc, str) or not desc.strip():
            errs.append("missing required 'description'")
        elif not 1 <= len(desc) <= 500:
            errs.append(f"'description' length {len(desc)} outside 1-500")
        apply_to = data.get("applyTo")
        if isinstance(apply_to, str):
            if not apply_to.strip():
                errs.append("'applyTo' is an empty string")
        elif isinstance(apply_to, list):
            if not apply_to or not all(isinstance(p, str) and p.strip() for p in apply_to):
                errs.append("'applyTo' list must contain non-empty glob strings")
        else:
            errs.append("missing required 'applyTo' (string or list of glob strings)")
        if errs:
            fail(f"instruction {rel(instr)}: " + "; ".join(errs))
        else:
            ok(f"instruction {rel(instr)}")

    # 6. Eval workspace rules (W4.2): waza preflight owns schema validity (run
    #    by the gate); here we own what preflight does not cover for this repo:
    #    declared metric weights must be positive numbers (waza treats weights
    #    as relative — no sum-1 contract; machina-authoring's weight: 30 passes
    #    preflight) and task globs must resolve.
    eval_files = sorted((REPO / "evals").glob("*/eval.yaml"))
    for eval_path in eval_files:
        if ".archived" in eval_path.parts:
            continue
        try:
            data = yaml.safe_load(eval_path.read_text(encoding="utf-8-sig"))
        except yaml.YAMLError as exc:
            fail(f"eval {rel(eval_path)}: invalid YAML: {exc}")
            continue
        if not isinstance(data, dict):
            fail(f"eval {rel(eval_path)}: root is not a mapping")
            continue
        errs = []
        metrics = data.get("metrics")
        if isinstance(metrics, list) and metrics:
            for metric in metrics:
                if not isinstance(metric, dict):
                    errs.append("metrics entries must be mappings")
                    continue
                if "weight" in metric:
                    weight = metric["weight"]
                    label = metric.get("name", "<unnamed>")
                    if not isinstance(weight, (int, float)) or isinstance(weight, bool) or weight <= 0:
                        errs.append(f"metrics entry '{label}' weight must be a positive number (got {weight!r})")
        tasks = data.get("tasks")
        if isinstance(tasks, list):
            for entry in tasks:
                if not isinstance(entry, str):
                    continue
                if any(ch in entry for ch in "*?["):
                    if not list(eval_path.parent.glob(entry)):
                        errs.append(f"tasks glob '{entry}' resolves to nothing")
                elif not (eval_path.parent / entry).exists():
                    errs.append(f"tasks entry '{entry}' not found")
        if errs:
            fail(f"eval {rel(eval_path)}: " + "; ".join(errs))
        else:
            ok(f"eval {rel(eval_path)}")

    # 7. Issues index freshness: .issues/index.md must index every issue file
    #    (FAIL with reindex hint).
    issues_index = REPO / ".issues" / "index.md"
    if not issues_index.exists():
        fail(".issues/index.md: missing (run: task issues:index)")
    else:
        idx_text = issues_index.read_text(encoding="utf-8-sig")
        issue_files = sorted(p for p in (REPO / ".issues").glob("*.md") if p.name != "index.md")
        missing_issues = [p.name for p in issue_files if p.name not in idx_text]
        if missing_issues:
            fail(".issues/index.md: not indexed: " + ", ".join(missing_issues[:5])
                 + " - run: task issues:index")
        else:
            ok(f".issues/index.md covers all {len(issue_files)} issue file(s)")

    checked = (
        len(manifests) + len(skills) + len(instructions) + len(eval_files)
        + (1 if marketplace.exists() else 0)
    )
    if failures:
        print(f"validate-manifests: {len(failures)} failure(s) across {checked} artifact(s)")
        return 1
    print(f"validate-manifests: {checked} artifact(s) green, 3 schemas valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
