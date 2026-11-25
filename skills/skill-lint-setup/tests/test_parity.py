"""Parity guardrail: the bundled validator against the canonical engine.

The adversarial audit that preceded this skill found 11 findings - two of
them false rejections of valid YAML - because nothing compared the stdlib
subset parser with the canonical stack the repo gate runs (yaml.safe_load +
jsonschema + the name==directory rule). The differential battery that found
them was a throwaway probe; this file commits it as a standing check:

  1. Shape battery - every shape below must reach the SAME gate verdict
     (PASS/FAIL) in both engines, valid and invalid shapes alike.
  2. Real-repo parity - both engines must agree on every skills/*/SKILL.md
     in this workspace.

Run with: python3 -m pytest skills -q (wired into task test / the full gate).
"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import jsonschema
import pytest
import yaml

SKILL_DIR = Path(__file__).resolve().parents[1]
BUNDLED = SKILL_DIR / "assets" / "validate_frontmatter.py"
REPO = Path(__file__).resolve().parents[3]
SCHEMA = json.loads((REPO / "schemas" / "skill.schema.json").read_text(encoding="utf-8"))

NAME = "demo-skill"
DESC = "A demo skill used for testing. USE FOR: tests. DO NOT USE FOR: prod."
DQ_DESC = json.dumps(DESC)
META = "metadata:\n  version: 1.0.0"
_LONG_A = "x" * 600
_LONG_B = "y" * 600


def _load_bundled():
    spec = importlib.util.spec_from_file_location("bundled_validate_frontmatter", BUNDLED)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


V = _load_bundled()


def _split_frontmatter(text: str) -> str | None:
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    return None if end == -1 else text[3:end]


def canonical_errors(inner: str, dirname: str) -> list[str]:
    """The repo gate's verdict: PyYAML + jsonschema + name==directory."""
    try:
        data = yaml.safe_load(inner)
    except yaml.YAMLError as exc:
        return [f"yaml {type(exc).__name__}: {exc}"]
    if not isinstance(data, dict):
        return ["frontmatter is not a mapping"]
    errors = [
        "/".join(str(p) for p in err.absolute_path) or "<root>"
        for err in jsonschema.Draft202012Validator(SCHEMA).iter_errors(data)
    ]
    if isinstance(data.get("name"), str) and data["name"] != dirname:
        errors.append("name != directory")
    return errors


def both_engines(tmp_path: Path, inner: str) -> tuple[list[str], list[str]]:
    repo = tmp_path / "repo"
    skill_dir = repo / "skills" / NAME
    skill_dir.mkdir(parents=True, exist_ok=True)
    (skill_dir / "SKILL.md").write_text(f"---\n{inner}---\n# {NAME}\n", encoding="utf-8")
    mine = V.check_skill(skill_dir / "SKILL.md", SCHEMA, repo)
    ref = canonical_errors(inner, NAME)
    return mine, ref


def base(*lines: str, name: str = NAME, desc: str | None = DQ_DESC,
         meta: str | None = META) -> str:
    out = [f"name: {name}"]
    if desc is not None:
        out.append(f"description: {desc}")
    out.extend(lines)
    if meta is not None:
        out.append(meta)
    return "\n".join(out) + "\n"


BATTERY = {
    # ---- shapes both engines must PASS (each probed against PyYAML) ----
    "plain_simple": base(desc="simple plain text with plenty of length"),
    "plain_wrap": base(
        desc="A plain scalar description that wraps\n  onto a second line here"
    ),
    "plain_para": base(desc="para one which is long enough\n\n  para two more text"),
    "plain_comment_tail": base(desc="text here which is long enough # note"),
    "plain_url": base(desc="see http://example.com/docs for the guide"),
    "quoted_colon_hash": base(
        desc=json.dumps("has: colon and # hash inside a long value")
    ),
    "quoted_comment_tail": base(desc='"quoted text long enough here" # note'),
    "squote_doubled": base(desc="'it''s a quoted description long enough here'"),
    "squote_comment": base(
        desc="'a quoted: description with # hash long here' # tail"
    ),
    "folded_strip": base(desc=">-\n  line one of the folded text\n  line two of the folded text"),
    "folded_clip": base(desc=">\n  line one of the clipped text"),
    "folded_keep": base(desc="|+\n  text kept with newline here"),
    "folded_para": base(desc=">-\n  para one text\n\n  para two text"),
    "folded_extra_indent": base(desc=">-\n  line one text\n    deeper line text"),
    "folded_indent_ind": base(desc=">2\n    text here indented plenty"),
    "folded_header_comment": base(desc=">- # note\n  text after header comment"),
    "literal_dash": base(desc="|-\n  literal line one text\n  literal line two"),
    "block_seq": base("allowed-tools:\n  - read\n  - edit"),
    "flow_seq_oneline": base('allowed-tools: ["Bash(git:*)", read]'),
    "flow_seq_comma_in_quotes": base('allowed-tools: ["a, b", read]'),
    "flow_seq_multiline": base('allowed-tools: [\n  "a",\n  read\n]'),
    "flow_map_int": base(meta=META + "\nenv: {A: 1}"),
    "flow_map_empty": base(meta=META + "\nenv: {}"),
    "flow_map_bare": base(meta=META + "\nenv: {a}"),
    "env_string": base(meta=META + "\nenv: production"),
    "allowed_string": base(meta=META + '\nallowed-tools: "Bash(git:*)"'),
    "argument_hint": base(meta=META + '\nargument-hint: "<query>"'),
    "dup_last_wins": (
        f"name: {NAME}\n"
        f"description: short\n"
        f"description: {DQ_DESC}\n"
        f"{META}\n"
    ),
    "comment_first": "# lead comment\n" + base(
        desc="comment-first description that is long enough"
    ),
    # ---- shapes both engines must FAIL (parser errors, schema violations) ----
    "plain_colon_space": base(desc="Does X. USE FOR: y unquoted"),
    "wrap_colon_space": base(desc="some plain text here\n  nested: value line"),
    "quoted_then_indent": base(desc='"a quoted description long enough"\n  orphan line'),
    "folded_junk_gt2": base(desc=">2 text\n    text here"),
    "folded_gt_junk": base(desc=">not-a-block\n    text here"),
    "allowed_num": base(meta=META + "\nallowed-tools: 42"),
    "allowed_items_num": base(meta=META + "\nallowed-tools:\n  - 1"),
    "dash_flow": base(meta=META + "\nallowed-tools: [ - a, - b ]"),
    "unclosed_flow": base(meta=META + "\nallowed-tools: [\n  read"),
    "bad_semver": base(meta="metadata:\n  version: latest"),
    "unknown_key": base(meta=META + "\nbogus: true"),
    "missing_metadata": f"name: {NAME}\ndescription: {DQ_DESC}\n",
    "desc_too_long": base(desc=json.dumps("x" * 1025)),
    "desc_too_short": base(desc=json.dumps("short")),
    "name_bad_kebab": base(desc=DQ_DESC, name="Bad_Name"),
    "name_dir_mismatch": base(desc=DQ_DESC, name="other-name"),
    "numeric_desc": base(desc="123456789012345"),
    "null_description": base(desc="# note"),
    "blank_frontmatter": "",
    "folded_over_length": (
        f"name: {NAME}\n"
        f"description: >-\n  {_LONG_A}\n  {_LONG_B}\n"
        f"{META}\n"
    ),
}


def _verdict(errs: list[str]) -> str:
    return f"FAIL {errs}" if errs else "PASS"


@pytest.mark.parametrize("inner", list(BATTERY.values()), ids=list(BATTERY.keys()))
def test_shape_verdict_parity(tmp_path: Path, inner: str) -> None:
    mine, ref = both_engines(tmp_path, inner)
    assert bool(mine) == bool(ref), (
        f"engine verdict divergence:\n  bundled:   {_verdict(mine)}\n"
        f"  canonical: {_verdict(ref)}\nfrontmatter:\n{inner}"
    )


def test_real_repo_skill_parity() -> None:
    """Both engines must agree on every real skill in this workspace."""
    skills = sorted((REPO / "skills").glob("*/SKILL.md"))
    assert skills, "no skills/*/SKILL.md found for parity"
    diverged: list[str] = []
    for skill in skills:
        text = skill.read_text(encoding="utf-8-sig")
        fm = _split_frontmatter(text)
        ref = canonical_errors(fm if fm is not None else "", skill.parent.name)
        mine = V.check_skill(skill, SCHEMA, REPO)
        if bool(mine) != bool(ref):
            diverged.append(f"{skill.parent.name}: bundled={mine} canonical={ref}")
    assert not diverged, "engine verdict divergence on real skills:\n" + "\n".join(diverged)
