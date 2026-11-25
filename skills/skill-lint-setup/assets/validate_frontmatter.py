#!/usr/bin/env python3
"""Validate skills/*/SKILL.md frontmatter against schemas/skill.schema.json.

Standardized local gate installed by skill-lint-setup. Stdlib-only (no PyYAML,
no jsonschema) so any repo, git hook, Taskfile, or CI job can run it without a
virtualenv. The subset of JSON Schema honored here covers the schema's actual
skill rules: required keys, additionalProperties: false at the top level,
string minLength/maxLength/pattern, object required/properties, and $ref.

Rules enforced (all read from the schema, never hardcoded):
  - frontmatter present and parseable (plain scalars may wrap across
    more-indented continuation lines; quoted scalars may carry trailing
    comments - both fold the way PyYAML does)
  - required top-level keys (name, description, metadata)
  - no unknown top-level keys
  - name: kebab-case, 1-64 chars, equal to the containing directory name
  - description: 10-1024 chars (the Copilot harness cap)
  - metadata.version: semver
  - oneOf/anyOf unions and array item types (at least one branch must accept
    the value; branch errors are reported joined)

Zero skills found is a deliberate green: the gate stays inert until
skills/<name>/SKILL.md exists (the canonical github-copilot-fc gate FAILs this
state instead) and says so on an explicit [SKIP] line.

Exit codes: 0 green, 1 violations found, 2 tooling/config error (missing or
unreadable schema file).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


class FrontmatterError(ValueError):
    """Frontmatter text is not parseable by the subset parser."""


def split_frontmatter(text: str) -> str | None:
    """Return the YAML block between the --- fences, or None if absent."""
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    return text[3:end]


def _indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _strip_inline_comment(value: str) -> str:
    return re.sub(r"\s+#.*$", "", value)


def _scalar(raw: str):
    s = raw.strip()
    if s.startswith('"'):
        m = re.match(r'^"((?:[^"\\]|\\.)*)"', s)
        if not m:
            raise FrontmatterError(
                f"unterminated or multi-line double-quoted scalar: {raw!r} "
                "(use a folded block >- for multi-line values)"
            )
        tail = s[m.end():].strip()
        if tail and not tail.startswith("#"):
            raise FrontmatterError(f"unexpected content after quoted scalar: {raw!r}")
        inner = m.group(1)
        out = (
            inner.replace("\\\\", "\x00")
            .replace('\\"', '"')
            .replace("\\n", "\n")
            .replace("\\t", "\t")
            .replace("\\r", "\r")
        )
        return out.replace("\x00", "\\")
    if s.startswith("'"):
        # Closing quote plus optional trailing comment: 'a # b' # note
        m = re.match(r"^'((?:[^']|'')*)'(?:\s+#.*)?$", s)
        if not m:
            raise FrontmatterError(f"unterminated single-quoted scalar: {raw!r}")
        return m.group(1).replace("''", "'")
    s = _strip_inline_comment(s).strip()
    if s in ("{}",):
        return {}
    if s in ("[]",):
        return []
    if s.startswith("[") and s.endswith("]"):
        body = s[1:-1].strip()
        if not body:
            return []
        parts = _split_flow(body)
        # PyYAML rejects bare '- item' entries inside flow sequences.
        for part in parts:
            item = part.strip()
            if (item == "-" or item.startswith("- ")) and not item.startswith(("'", '"')):
                raise FrontmatterError(
                    f"bare '- {item[2:]}' entry in flow sequence: {raw!r}"
                )
        return [_scalar(part) for part in parts]
    if s.startswith("{") and s.endswith("}"):
        # Flow mapping (env: {KEY: val}) is valid YAML; the schema's object
        # branches impose no inner constraints, so typed pairs suffice.
        body = s[1:-1].strip()
        out: dict = {}
        for part in _split_flow(body) if body else []:
            k, sep, v = part.partition(":")
            out[_scalar(k)] = _scalar(v) if sep else None
        return out
    # Plain-scalar parity with PyYAML (probed): a raw ': ' or trailing ':' is
    # a ScannerError there - quote the value or use a folded >- block.
    if ": " in s or s.endswith(":"):
        raise FrontmatterError(
            f"plain scalar {raw!r} contains ':' where YAML forbids it; "
            f"quote the value or use a folded block (>-)"
        )
    if s in ("true", "True", "TRUE"):
        return True
    if s in ("false", "False", "FALSE"):
        return False
    if s in ("null", "Null", "NULL", "~", ""):
        return None
    # Numbers must stay numbers, or `allowed-tools: 42` looks like a string
    # and slips through every oneOf branch typed string|array.
    if re.fullmatch(r"[+-]?\d+", s):
        return int(s)
    if re.fullmatch(r"[+-]?(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?", s):
        return float(s)
    return s


def _skip_blank(lines: list[str], i: int) -> int:
    while i < len(lines) and (not lines[i].strip() or lines[i].lstrip().startswith("#")):
        i += 1
    return i


def _flow_unbalanced(s: str) -> bool:
    """True when an open '[' or '{' has no closer (quotes respected)."""
    net = 0
    in_quote: str | None = None
    prev = ""
    for ch in s:
        if in_quote:
            if ch == in_quote and not (in_quote == '"' and prev == "\\"):
                in_quote = None
        elif ch in "\"'":
            in_quote = ch
        elif ch in "[{":
            net += 1
        elif ch in "]}":
            net -= 1
        prev = ch
    return net > 0


def _split_flow(body: str) -> list[str]:
    """Split a flow collection body on top-level commas (quotes respected)."""
    parts: list[str] = []
    cur = ""
    quote: str | None = None
    prev = ""
    for ch in body:
        if quote:
            cur += ch
            if ch == quote and not (quote == '"' and prev == "\\"):
                quote = None
        elif ch in "\"'":
            quote = ch
            cur += ch
        elif ch == ",":
            parts.append(cur)
            cur = ""
        else:
            cur += ch
        prev = ch
    parts.append(cur)
    return parts


def _parse_map(lines: list[str], i: int, indent: int):
    result: dict = {}
    while i < len(lines):
        if not lines[i].strip() or lines[i].lstrip().startswith("#"):
            i += 1
            continue
        cur = _indent_of(lines[i])
        if cur < indent:
            break
        if cur > indent:
            raise FrontmatterError(f"unexpected indent at line {i + 1}: {lines[i]!r}")
        body = lines[i].strip()
        m = re.match(r"^([A-Za-z0-9_.\-]+):(?:\s+(.*))?$", body)
        if not m:
            raise FrontmatterError(f"expected 'key: value' at line {i + 1}: {lines[i]!r}")
        key, rest = m.group(1), m.group(2)
        if rest is not None and rest.lstrip().startswith("#"):
            rest = None  # `key: # comment` -> empty value, as in PyYAML
        i += 1
        if rest is None:
            value, i = _parse_nested(lines, i, indent)
            result[key] = value
        elif re.fullmatch(r"[>|](?:[+-]?\d*|\d[+-]?)",
                          _strip_inline_comment(rest).strip()):
            # Block scalar. Header may carry a trailing comment. Content is
            # dedented by the explicit indent indicator (relative to this
            # node) or by the first content line's indent; chomping and
            # folding then follow the YAML rules PyYAML implements.
            header = _strip_inline_comment(rest).strip()
            folded = header[0] == ">"
            keep = "+" in header
            strip_all = "-" in header
            ind = next((int(c) for c in header[1:] if c.isdigit()), None)
            raw: list[str] = []
            while i < len(lines):
                line = lines[i]
                if line.strip() and _indent_of(line) <= indent:
                    break
                raw.append(line)
                i += 1
            first = next((l for l in raw if l.strip()), None)
            if ind is not None:
                block_indent = indent + ind
            else:
                block_indent = _indent_of(first) if first is not None else 0
            for l in raw:
                if l.strip() and _indent_of(l) < block_indent:
                    raise FrontmatterError(
                        f"block scalar line under-indented near line {i}: {l!r}"
                    )
            content = ["" if not l.strip() else l[block_indent:] for l in raw]
            if folded:
                parts: list[str] = []
                words: list[str] = []
                owed = 0
                for l in content:
                    if l == "":
                        if words:
                            parts.append(" ".join(words))
                            words = []
                        owed += 1
                    elif l[0] in " \t":
                        # More-indented line: kept literally, with real breaks.
                        if words:
                            parts.append(" ".join(words))
                            words = []
                        if parts:
                            owed = max(owed, 1)
                        if owed:
                            parts.append("\n" * owed)
                            owed = 0
                        parts.append(l)
                        owed = 1
                    else:
                        if owed:
                            if words:
                                parts.append(" ".join(words))
                                words = []
                            parts.append("\n" * owed)
                            owed = 0
                        words.append(l)
                if words:
                    parts.append(" ".join(words))
                value = "".join(parts)
                if strip_all or not value:
                    pass
                elif keep:
                    value += "\n" * (owed + 1)
                else:
                    value += "\n"
            else:
                body = "\n".join(content)
                if strip_all:
                    value = body.rstrip("\n")
                elif keep:
                    value = body + "\n" if body else ""
                else:
                    stripped = body.rstrip("\n")
                    value = stripped + ("\n" if stripped else "")
            result[key] = value
        elif rest.startswith((">", "|")):
            # Plain scalar starting with a block indicator (`>- text`,
            # `>not-a-block`, `>2 text`) - PyYAML raises a ScannerError; only
            # a bare header (handled above) may introduce a block scalar.
            raise FrontmatterError(
                f"unexpected content after block indicator at line {i}: {rest!r}"
            )
        else:
            # Plain (unquoted) scalar: fold more-indented continuation lines
            # the way PyYAML does - `key: text\n  more text` is one string,
            # not an indent error. Quoted scalars are complete on their line;
            # following indented lines stay a parse error (matches YAML).
            if not rest.lstrip().startswith(("'", '"')):
                while i < len(lines):
                    nxt = lines[i]
                    # Unclosed flow collection: keep folding until the closer,
                    # even at zero indent ([ ... \n ] as PyYAML allows).
                    if rest.lstrip().startswith(("[", "{")) and _flow_unbalanced(rest):
                        if not nxt.strip():
                            raise FrontmatterError(
                                f"unterminated flow collection at line {i + 1}"
                            )
                        rest = rest.rstrip() + " " + nxt.strip()
                        i += 1
                        continue
                    # A ' # ' comment already ended the scalar in YAML; folding
                    # more lines would accept what PyYAML rejects.
                    if re.search(r"\s+#", rest):
                        break
                    if not nxt.strip():
                        # Blank inside a plain scalar: paragraph break only if
                        # a more-indented line follows, else the block ended.
                        j = _skip_blank(lines, i)
                        if j >= len(lines) or _indent_of(lines[j]) <= indent:
                            break
                        rest += "\n"
                        i = j
                        continue
                    if nxt.lstrip().startswith("#"):
                        break
                    if _indent_of(nxt) <= indent:
                        break
                    if rest.endswith("\n"):
                        rest += nxt.strip()      # after a paragraph break
                    else:
                        rest = rest.rstrip() + " " + nxt.strip()
                    i += 1
                if rest.lstrip().startswith(("[", "{")) and _flow_unbalanced(rest):
                    raise FrontmatterError(f"unterminated flow collection: {rest!r}")
            result[key] = _scalar(rest)
    return result, i


def _parse_seq(lines: list[str], i: int, indent: int):
    items: list = []
    while i < len(lines):
        if not lines[i].strip() or lines[i].lstrip().startswith("#"):
            i += 1
            continue
        cur = _indent_of(lines[i])
        if cur != indent or not lines[i].strip().startswith("- "):
            break
        items.append(_scalar(lines[i].strip()[2:]))
        i += 1
    return items, i


def _parse_nested(lines: list[str], i: int, parent_indent: int):
    j = _skip_blank(lines, i)
    if j >= len(lines) or _indent_of(lines[j]) <= parent_indent:
        return None, i
    return _parse_node(lines, j, _indent_of(lines[j]))


def _parse_node(lines: list[str], i: int, indent: int):
    if lines[i].strip().startswith("- "):
        return _parse_seq(lines, i, indent)
    return _parse_map(lines, i, indent)


def parse_frontmatter(fm: str):
    lines = fm.splitlines()
    i = _skip_blank(lines, 0)
    if i >= len(lines):
        return None  # blank block: PyYAML also yields None (gate: not a mapping)
    value, _ = _parse_node(lines, i, _indent_of(lines[i]))
    return value


def _resolve(spec: dict, schema: dict) -> dict:
    ref = spec.get("$ref")
    if not ref:
        return spec
    node = schema
    for part in ref.lstrip("#/").split("/"):
        node = node[part]
    return node


def _check_value(value, spec: dict, schema: dict, path: str) -> list[str]:
    spec = _resolve(spec, schema)
    if "oneOf" in spec or "anyOf" in spec:
        # Union semantics: at least one branch must accept the value. The
        # schema's unions (allowed-tools, env, machina) have no overlapping
        # branches, so this matches jsonschema's exactly-one for them.
        branches = spec.get("oneOf") or spec.get("anyOf") or []
        branch_errors: list[str] = []
        for branch in branches:
            errs = _check_value(value, branch, schema, path)
            if not errs:
                return []
            branch_errors.append(errs[0])
        return [
            f"{path}: does not match any allowed schema branch "
            f"({'; '.join(branch_errors)})"
        ]
    errors: list[str] = []
    expected = spec.get("type")
    if expected == "string":
        if not isinstance(value, str):
            return [f"{path}: expected a string, got {type(value).__name__}"]
        if "minLength" in spec and len(value) < spec["minLength"]:
            errors.append(f"{path}: value is {len(value)} chars (min {spec['minLength']})")
        if "maxLength" in spec and len(value) > spec["maxLength"]:
            errors.append(f"{path}: value is {len(value)} chars (max {spec['maxLength']})")
        if "pattern" in spec and not re.search(spec["pattern"], value):
            errors.append(f"{path}: {value!r} does not match pattern {spec['pattern']}")
        return errors
    if expected == "object":
        if not isinstance(value, dict):
            return [f"{path}: expected a mapping, got {type(value).__name__}"]
        props = spec.get("properties", {})
        for req in spec.get("required", []):
            if req not in value:
                errors.append(f"{path}: missing required '{req}'")
        for key, sub in props.items():
            if key in value:
                errors.extend(_check_value(value[key], sub, schema, f"{path}.{key}"))
        if spec.get("additionalProperties") is False:
            for key in value:
                if key not in props:
                    errors.append(f"{path}: unknown key '{key}'")
        return errors
    if expected == "array":
        if not isinstance(value, list):
            return [f"{path}: expected a list, got {type(value).__name__}"]
        item_spec = spec.get("items")
        if isinstance(item_spec, dict):
            for idx, item in enumerate(value):
                errors.extend(_check_value(item, item_spec, schema, f"{path}[{idx}]"))
        return errors
    if expected == "boolean" and not isinstance(value, bool):
        return [f"{path}: expected a boolean, got {type(value).__name__}"]
    return errors


def validate_data(data: dict, schema: dict) -> list[str]:
    errors: list[str] = []
    props = schema.get("properties", {})
    for req in schema.get("required", []):
        if req not in data:
            errors.append(f"missing required '{req}'")
    if schema.get("additionalProperties") is False:
        for key in data:
            if key not in props:
                errors.append(f"unknown top-level key '{key}'")
    for key, value in data.items():
        spec = props.get(key)
        if spec is not None:
            errors.extend(_check_value(value, spec, schema, key))
    return errors


def check_skill(path: Path, schema: dict, repo: Path) -> list[str]:
    rel = path.relative_to(repo).as_posix()
    try:
        raw = path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        return [f"{rel}: unreadable: {exc}"]
    fm = split_frontmatter(raw)
    if fm is None:
        return [f"{rel}: missing or unterminated YAML frontmatter"]
    try:
        data = parse_frontmatter(fm)
    except FrontmatterError as exc:
        return [f"{rel}: invalid frontmatter: {exc}"]
    if not isinstance(data, dict):
        return [f"{rel}: frontmatter is not a mapping"]
    errors = [f"{rel}: {err}" for err in validate_data(data, schema)]
    name = data.get("name")
    if isinstance(name, str) and name != path.parent.name:
        errors.append(f"{rel}: name {name!r} != directory {path.parent.name!r}")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        default=str(Path(__file__).resolve().parents[1]),
        help="repository root containing skills/ and schemas/ (default: parent of scripts/)",
    )
    args = parser.parse_args(argv)
    repo = Path(args.root).resolve()

    schema_path = repo / "schemas" / "skill.schema.json"
    if not schema_path.is_file():
        print(f"[FAIL] schema not found: {schema_path} (run scripts/setup_skill_lint.py)")
        return 2
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"[FAIL] unreadable schema {schema_path}: {exc}")
        return 2

    skills_dir = repo / "skills"
    skills = sorted(skills_dir.glob("*/SKILL.md")) if skills_dir.is_dir() else []
    if not skills:
        print(
            f"[SKIP] no skills/*/SKILL.md under {repo} - gate is inert until a "
            "skill exists (exit 0 by design; the canonical github-copilot-fc "
            "gate FAILs this state, so run this validator after any skills/ "
            "restructure)"
        )
        return 0

    failures = 0
    for skill in skills:
        errors = check_skill(skill, schema, repo)
        rel = skill.relative_to(repo).as_posix()
        if errors:
            failures += len(errors)
            for err in errors:
                print(f"[FAIL] {err}")
        else:
            print(f"[PASS] {rel}")

    if failures:
        print(f"validate_frontmatter: {failures} failure(s) across {len(skills)} skill(s)")
        return 1
    print(f"validate_frontmatter: {len(skills)} skill(s) green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
