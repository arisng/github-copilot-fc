# Repo-agnostic checklist

Read this when executing step 2 of [SKILL.md](../SKILL.md). Goal: the extracted skill
must read as if it were written for any repository — only the d2 case history below is
concrete.

## Grep the candidate copy for

Run case-insensitively over the whole skill folder (`SKILL.md`, `references/`,
`scripts/`, `assets/`):

| Pattern class | Examples found in the wild |
|---|---|
| Repo / org names | `dprocess`, `github-copilot-fc`, workspace folder names |
| Repo-local tool paths | `tools/validate.mjs`, `.github/…`, `scripts/<repo>/…` |
| Repo commands | `task check`, `npm run gate`, `<repo> hook names` |
| CI / gate wording | "the repo gate enforces…", "runs in our CI" |
| Internal docs links | relative links into the source repo (`../../README.md`) |
| Product / domain nouns | internal products, teams, marketplace plugin names |

`subprocess`-style false positives (`CompletedProcess`, `--d2 PATH`) are fine — judge by
meaning, not by raw match count.

## Rewrite rules

- **Repo-local script path** → published path, or drop the claim:
  - before: `python3 .github/skills/d2/scripts/build_html.py file.d2`
  - after: `python ~/.agents/skills/d2/scripts/build_html.py file.d2`
- **Repo gate reference** → generic consumer wording:
  - before: `# gate: exit 1 when unformatted (use in CI — task check enforces it)`
  - after: `# gate: exit 1 when unformatted (use in CI / agent verification)`
- **Comment naming internal tooling** → name the contract, not the tool:
  - before: `# so the repo gate (tools/validate.mjs) can detect a stale build`
  - after: `# so any consumer (manifest check, CI gate, diff review) can detect a stale build`
- **Markdown link to `~` or an absolute path** → inline code (link-checkers reject it):
  - before: `see the [d2 skill](~/.agents/skills/d2/SKILL.md)`
  - after: `see the \`d2\` skill (installed at \`~/.agents/skills/d2\`)`
- **Angle brackets in `description`** → brace or plain-word placeholders:
  skill-creator's `quick_validate.py` rejects `<` or `>` anywhere in the
  description value while the factory schema allows them, so a placeholder
  clears lint and dies at validate:
  - before: `` rendered as `reports/daily/<git user>/yymmdd.md` ``
  - after: `` rendered as `reports/daily/{git user}/yymmdd.md` ``

Do not touch: CLI syntax, version pins, cross-platform commands, or anything already
repo-agnostic. After rewriting, re-run the grep — only known false positives may remain.

## Validate the candidate before the factory commit

Run `python ~/.agents/skills/skill-creator/scripts/quick_validate.py <candidate-dir>`.
It gates frontmatter shape the factory lint never looks at: required `name` /
`description` / `metadata`, kebab name, description length, and the angle-bracket
ban above. Green lint plus red validate is the cheap outcome; discovering the
failure after the push is the expensive one.

## Frontmatter versioning (public skills only)

Repo-level skills may omit `metadata`; the factory copy must not:

```yaml
metadata:
  version: 1.0.0
  author: arisng
```

`metadata.version` is what `npx skills update -g` compares. Start a freshly extracted
skill at `1.0.0`; leave `name` and `description` byte-identical to the source.
