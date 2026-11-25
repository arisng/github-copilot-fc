"""Tests for assets/validate_frontmatter.py (installed as scripts/validate_skill_frontmatter.py).

Covers the Copilot harness limits: description 10-1024 chars, kebab name <=64,
name/directory equality, required metadata.version (semver), unknown top-level
keys, folded-scalar descriptions, and exit codes. Run with: python3 -m pytest skills -q
"""

import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "assets" / "validate_frontmatter.py"

GOOD_NAME = "demo-skill"
GOOD_DESC = "A demo skill used for testing. USE FOR: tests. DO NOT USE FOR: prod."


def write_schema(repo: Path) -> None:
    schema_dir = repo / "schemas"
    schema_dir.mkdir(parents=True, exist_ok=True)
    src = Path(__file__).resolve().parents[3] / "schemas" / "skill.schema.json"
    (schema_dir / "skill.schema.json").write_text(
        src.read_text(encoding="utf-8"), encoding="utf-8"
    )


def write_skill(
    repo: Path,
    name: str = GOOD_NAME,
    description: str = GOOD_DESC,
    metadata: str | None = "    version: 1.0.0\n    status: candidate",
    extra_top: str = "",
    folded: bool = False,
    frontmatter: bool = True,
) -> None:
    skill_dir = repo / "skills" / GOOD_NAME
    skill_dir.mkdir(parents=True, exist_ok=True)
    if not frontmatter:
        (skill_dir / "SKILL.md").write_text("# No frontmatter\n", encoding="utf-8")
        return
    if folded:
        lines = "\n".join(f"  {chunk}" for chunk in description.split("|"))
        desc_block = f"description: >-\n{lines}"
    else:
        desc_block = f"description: {json.dumps(description)}"
    meta_block = f"metadata:\n{metadata}" if metadata is not None else ""
    text = (
        "---\n"
        f"name: {name}\n"
        f"{desc_block}\n"
        f"{meta_block}\n"
        f"{extra_top}"
        "---\n"
        f"# {name}\n"
    )
    (skill_dir / "SKILL.md").write_text(text, encoding="utf-8")


def run_check(repo: Path) -> tuple[int, str]:
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(repo)],
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout + result.stderr


def make_repo(tmp_path: Path, **kwargs) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir()
    write_schema(repo)
    write_skill(repo, **kwargs)
    return repo


def test_valid_skill_passes(tmp_path: Path) -> None:
    code, out = run_check(make_repo(tmp_path))
    assert code == 0, out
    assert "green" in out


def test_description_at_1024_passes(tmp_path: Path) -> None:
    desc = "x" * 1024
    code, out = run_check(make_repo(tmp_path, description=desc))
    assert code == 0, out


def test_description_over_1024_fails(tmp_path: Path) -> None:
    desc = "x" * 1025
    code, out = run_check(make_repo(tmp_path, description=desc))
    assert code == 1, out
    assert "1025 chars (max 1024)" in out


def test_description_under_10_fails(tmp_path: Path) -> None:
    code, out = run_check(make_repo(tmp_path, description="short"))
    assert code == 1, out
    assert "min 10" in out


def test_folded_description_length_enforced(tmp_path: Path) -> None:
    # Folded scalars join with spaces; the cap must apply to the joined value.
    desc = "|".join(["y" * 600, "y" * 600])
    code, out = run_check(make_repo(tmp_path, description=desc, folded=True))
    assert code == 1, out
    assert "max 1024" in out


def test_folded_description_valid_passes(tmp_path: Path) -> None:
    desc = "A folded description that is long enough. | USE FOR: testing folds."
    code, out = run_check(make_repo(tmp_path, description=desc, folded=True))
    assert code == 0, out


def test_non_kebab_name_fails(tmp_path: Path) -> None:
    code, out = run_check(make_repo(tmp_path, name="Bad_Name"))
    assert code == 1, out
    assert "pattern" in out or "kebab" in out or "does not match" in out


def test_name_directory_mismatch_fails(tmp_path: Path) -> None:
    # write_skill always writes into skills/demo-skill/; a different frontmatter
    # name must be reported even when it is individually well-formed.
    code, out = run_check(make_repo(tmp_path, name="other-name"))
    assert code == 1, out
    assert "!= directory" in out


def test_missing_metadata_fails(tmp_path: Path) -> None:
    code, out = run_check(make_repo(tmp_path, metadata=None))
    assert code == 1, out
    assert "missing required 'metadata'" in out


def test_non_semver_version_fails(tmp_path: Path) -> None:
    code, out = run_check(
        make_repo(tmp_path, metadata="    version: latest")
    )
    assert code == 1, out
    assert "metadata.version" in out and "pattern" in out


def test_unknown_top_level_key_fails(tmp_path: Path) -> None:
    code, out = run_check(make_repo(tmp_path, extra_top="bogus: true\n"))
    assert code == 1, out
    assert "unknown top-level key 'bogus'" in out


def test_missing_frontmatter_fails(tmp_path: Path) -> None:
    code, out = run_check(make_repo(tmp_path, frontmatter=False))
    assert code == 1, out
    assert "frontmatter" in out


def test_no_skills_is_green_skip(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    repo.mkdir()
    write_schema(repo)
    code, out = run_check(repo)
    assert code == 0, out
    assert "SKIP" in out
    assert "inert" in out  # divergence from canonical gate must be explicit


def test_missing_schema_is_exit_2(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    repo.mkdir()
    write_skill(repo)
    code, out = run_check(repo)
    assert code == 2, out
    assert "schema not found" in out


# --- Parity fixtures: shapes probed against PyYAML (the canonical gate's
# --- parser). Both engines must reach the same verdict on each one.


def write_raw(tmp_path: Path, body: str, name: str = GOOD_NAME) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir(exist_ok=True)
    write_schema(repo)
    skill_dir = repo / "skills" / name
    skill_dir.mkdir(parents=True, exist_ok=True)
    (skill_dir / "SKILL.md").write_text(f"---\n{body}---\n# {name}\n", encoding="utf-8")
    return repo


def test_plain_multiline_description_folds(tmp_path: Path) -> None:
    # PyYAML: {'description': 'text that wraps onto a second line'}
    repo = write_raw(
        tmp_path,
        f"name: {GOOD_NAME}\n"
        "description: A plain scalar description that wraps\n"
        "  onto a second line like YAML allows\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 0, out


def test_plain_multiline_length_counts_folded_value(tmp_path: Path) -> None:
    repo = write_raw(
        tmp_path,
        f"name: {GOOD_NAME}\n"
        f"description: {'x' * 600}\n"
        f"  {'y' * 600}\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 1, out
    assert "max 1024" in out


def test_squote_with_trailing_comment_passes(tmp_path: Path) -> None:
    # PyYAML: {'description': 'a quoted: description with # hash'}
    repo = write_raw(
        tmp_path,
        f"name: {GOOD_NAME}\n"
        "description: 'a quoted: description with # hash' # trailing comment\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 0, out


def test_plain_scalar_colon_space_rejected(tmp_path: Path) -> None:
    # PyYAML ScannerError: mapping values are not allowed here.
    repo = write_raw(
        tmp_path,
        f"name: {GOOD_NAME}\n"
        "description: Does X. USE FOR: y unquoted\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 1, out
    assert "frontmatter" in out


def test_wrap_containing_colon_space_rejected(tmp_path: Path) -> None:
    # Continuation folds first; the folded ': ' must fail like PyYAML's error.
    repo = write_raw(
        tmp_path,
        f"name: {GOOD_NAME}\n"
        "description: some plain text\n"
        "  nested: value on continuation line\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 1, out


def test_quoted_then_indented_line_rejected(tmp_path: Path) -> None:
    # PyYAML ParserError: a quoted scalar cannot be followed by deeper lines.
    repo = write_raw(
        tmp_path,
        f'name: {GOOD_NAME}\n'
        'description: "a quoted description that is long enough here"\n'
        "  orphan continuation\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 1, out


def test_comment_ends_fold_then_next_key_parses(tmp_path: Path) -> None:
    # PyYAML: {'description': 'text', 'name': 'demo'}
    repo = write_raw(
        tmp_path,
        f"name: {GOOD_NAME}\n"
        "description: text which is long enough # note\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 0, out


def test_block_header_indent_indicator_passes(tmp_path: Path) -> None:
    # PyYAML: {'description': '  text here\n'} for '>2'.
    repo = write_raw(
        tmp_path,
        f"name: {GOOD_NAME}\n"
        "description: >2\n"
        "    text here\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 0, out


def test_block_indicator_with_junk_rejected(tmp_path: Path) -> None:
    # PyYAML ScannerError for '>2 text' / '>not-a-block'.
    for junk in (">2 text", ">not-a-block"):
        repo = write_raw(
            tmp_path,
            f"name: {GOOD_NAME}\n"
            f"description: {junk}\n"
            "    text\n"
            "metadata:\n  version: 1.0.0\n",
            name=GOOD_NAME,
        )
        code, out = run_check(repo)
        assert code == 1, (junk, out)


def test_flow_mapping_env_passes(tmp_path: Path) -> None:
    # PyYAML: {'env': {'API_URL': 'https://x'}} - valid; env allows object.
    repo = write_raw(
        tmp_path,
        f"name: {GOOD_NAME}\n"
        f"description: {json.dumps(GOOD_DESC)}\n"
        "env: {API_URL: https://x, DEBUG: 'true'}\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 0, out


def test_numeric_plain_description_rejected(tmp_path: Path) -> None:
    # PyYAML types an all-digit plain scalar as int; schema requires string.
    repo = write_raw(
        tmp_path,
        f"name: {GOOD_NAME}\n"
        "description: 123456789012345\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 1, out


def test_allowed_tools_number_rejected(tmp_path: Path) -> None:
    # jsonschema: 42 is not valid under any of the given schemas.
    repo = write_raw(
        tmp_path,
        f"name: {GOOD_NAME}\n"
        f"description: {json.dumps(GOOD_DESC)}\n"
        "allowed-tools: 42\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 1, out
    assert "any allowed schema branch" in out


def test_allowed_tools_array_item_type_rejected(tmp_path: Path) -> None:
    repo = write_raw(
        tmp_path,
        f"name: {GOOD_NAME}\n"
        f"description: {json.dumps(GOOD_DESC)}\n"
        "allowed-tools:\n  - 1\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 1, out


def test_allowed_tools_valid_shapes_pass(tmp_path: Path) -> None:
    values = [
        '"Bash(git:*)"',                              # one-line quoted
        '["Bash(git:*)", read]',                      # one-line flow seq
        '[\n  "Bash(git:*)",\n  read\n]',            # multi-line flow, commas
        '\n  - "Bash(git:*)"\n  - read',              # block seq (canonical)
    ]
    for value in values:
        body = (
            f"name: {GOOD_NAME}\n"
            f"description: {json.dumps(GOOD_DESC)}\n"
            f"allowed-tools: {value}\n"
            "metadata:\n  version: 1.0.0\n"
        )
        repo = write_raw(tmp_path, body)
        code, out = run_check(repo)
        assert code == 0, (value, out)


def test_bare_dash_flow_entry_rejected(tmp_path: Path) -> None:
    # PyYAML ParserError: '- item' is invalid inside a flow sequence.
    repo = write_raw(
        tmp_path,
        f"name: {GOOD_NAME}\n"
        f"description: {json.dumps(GOOD_DESC)}\n"
        "allowed-tools: [ - a, - b ]\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 1, out
    assert "flow sequence" in out


def test_unclosed_flow_collection_rejected(tmp_path: Path) -> None:
    # PyYAML ParserError: unterminated flow sequence.
    repo = write_raw(
        tmp_path,
        f"name: {GOOD_NAME}\n"
        f"description: {json.dumps(GOOD_DESC)}\n"
        "allowed-tools: [\n  a\n"
        "metadata:\n  version: 1.0.0\n",
    )
    code, out = run_check(repo)
    assert code == 1, out
    assert "flow" in out


def test_bundled_schema_is_canonical_copy() -> None:
    bundled = Path(__file__).resolve().parents[1] / "assets" / "skill.schema.json"
    canonical = Path(__file__).resolve().parents[3] / "schemas" / "skill.schema.json"
    assert json.loads(bundled.read_text(encoding="utf-8")) == json.loads(
        canonical.read_text(encoding="utf-8")
    )
