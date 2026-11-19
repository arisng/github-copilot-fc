---
name: join-copilot-fc
description: "Extract (promote) a repo-level agent skill from the current repository into the github-copilot-fc skills factory and publish it as a user-level skill — the join-copilot-fc flow: locate the repo skill, strip repo-specific references, add metadata.version, commit and push inside the factory, then remove the skill from the source repo and repoint its references. Use when the user asks to 'promote this repo skill', 'extract the repo-level skill', 'move a skill into github-copilot-fc', 'make this repo skill public/user-level', 'install this repo skill globally', or says 'join-copilot-fc'. Not for updating or version-bumping an already-extracted skill, authoring a brand-new skill, or publishing skills that did not originate in a repo."
metadata:
  version: 1.0.0
  author: arisng
---

# Join the copilot-fc skills factory

Promote a repo-level skill into the `github-copilot-fc` factory and publish it as a
user-level skill. Run the pipeline **locate -> agnostize -> land in fc -> clean up source
-> verify**. The factory push is the install gate: report success only after it lands.

## 1. Locate the repo-level skill

Find `SKILL.md` files outside plugin/payload content. Common roots, checked in order:

1. `.github/skills/<name>/` (Copilot repo-level skills)
2. `.claude/skills/<name>/`, `.agents/skills/<name>/`, `.codex/skills/<name>/`
3. repo-root `skills/<name>/`

Match on the user's named skill; if several candidates remain, ask which one to extract.
Inventory the folder (`SKILL.md`, `scripts/`, `references/`, `assets/`) — everything in
it moves together.

## 2. Agnostize before copying

Rewrite repo-specific content in the **candidate copy**; step 4 owns the source repo. Read
[references/agnostic-checklist.md](references/agnostic-checklist.md) for the grep
patterns and before/after rewrites. Rules of thumb:

- Replace repo-local script paths (`tools/…`, `.github/…`, `task <x>`, repo gates) with
  the published path `~/.agents/skills/<name>/…` or generic wording.
- Keep behavior byte-identical: touch wording and paths only.
- A link-checker rejects markdown links to `~` paths: reference them as inline code.

## 3. Land the skill in the factory

Factory clone: `C:\Workplace\Agents\github-copilot-fc` (branch `main`, remote
`arisng/github-copilot-fc`); ask the user if it lives elsewhere.

1. Copy the agnostized folder to `skills/<name>/`.
2. Add public-skill metadata to the frontmatter (required so consumers can run
   `npx skills update -g`); keep `name` and `description` untouched:

   ```yaml
   metadata:
     version: 1.0.0
     author: arisng
   ```

3. Lint what you changed: `npx --yes markdownlint-cli2 skills/<name>/**/*.md`. TOC
   fragments must match heading anchors exactly (punctuation drops, spaces become `-`).
4. Commit with the factory's style — `agent(skill): add <name> skill`. The post-commit
   hook publishes the skill to `~/.agents/skills/` automatically.
5. Push `origin main`. The pre-push hook runs `workspace-check` (markdownlint on changed
   `.md`, TOC freshness, skill pytest). Fix failures and re-push — the push landing is
   what you report as installed.

## 4. Clean up the source repo

1. Delete the skill directory from the source repo.
2. Grep the whole repo for the old skill path and repoint every reference (README,
   AGENTS.md, tool error messages, build recipes) to `~/.agents/skills/<name>/…`.
3. Run the repo's local gate (`task check`, `npm test`, hooks — discover it, do not
   guess) and fix what your edits broke.
4. Commit using the source repo's conventions: conventional commits, explicit staged
   paths, and `EXPECTED_HEAD=$(git rev-parse HEAD)` on shared-branch repos so the hook
   aborts if a sibling session moved HEAD. Push the source repo on the user's request.

## 5. Verify

- `git diff --no-index <fc>/skills/<name> ~/.agents/skills/<name>` → empty (installed
  copy matches the pushed factory copy).
- Validate frontmatter (skill-creator's `scripts/quick_validate.py`) and confirm
  `npx skills list` shows the skill.
- Smoke-test bundled scripts: `--help`, then one real end-to-end run in a temp dir;
  delete temp files afterwards.

## Guardrails

1. **Order is the contract:** agnostize -> factory commit -> factory push -> clean up
   source -> verify. The factory push is the publish gate; the source deletion lands
   only after it succeeds.
2. **One skill per run.** Start a fresh run for each additional skill.
3. **Correct with follow-up commits** in both repos; published history stays as is.
4. **Leave the source repo's gate green** — your reference edits ship in the same
   commit as the skill deletion.
