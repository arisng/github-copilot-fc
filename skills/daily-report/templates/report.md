---
created: {YYYY-MM-DD HH:mm +HH:MM}
updated: {YYYY-MM-DD HH:mm +HH:MM}
---

# Daily Report

> Timeless body — no clock times, timestamps, or dates in the text. Time lives only in the `created` and `updated` stamps above, each carrying the generating machine's runtime UTC offset. The filename (`yymmdd.md`) carries the date; the folder (`<git-username>/`) carries the owner.
> Section order is completion-first: Completed → Under Review → Active Work → Blockers → Next Up.
> **Scope:** one checkout in single mode — no tags needed. In multi-repo tower mode every change names its repository: `[repo]` on a Completed title, `[repo]` in the first cell of an Under Review or Active Work row. The token is an alias of a watched repo (a substring of its path leaf; `+` joins a cross-repo change, e.g. `[webapi+fc]`). Blockers and Next Up stay untagged when no single repo owns them.
> **Executive one-page report.** Signal over noise: every line must earn its place. Report outcomes and decisions — never a change log of files.
> **Session pointers.** A cited session is a link: display text is the 8-char id, the target is the exported transcript `sessions/<yymmdd>/<full-uuid>.html`. The transcripts are committed, so the link resolves for every reader; the full UUID in the target is what makes it survive a rerun. Write it `[b5696ab2](sessions/261125/b5696ab2-4a90-4196-a743-767e58bb450b.html)`. A prose ``session `xxxxxxxx` `` citation still exports, but the link is the form this template asks for.

---

## 🏆 Completed Today

> Direct value delivered in the day. At most 4 items.

### 1. [repo] {Main outcome — one line, written as an outcome, not a task name}

- **Why:** {one sentence — what breaks or gets lost if this had not been done}
- **Result:** {one sentence — the verifiable state change; the action verbs live here}
- **Refs:** {ONE line with 2 to 4 pointers — session link · hyperlinked pull request or issue · check result (a short label with its outcome: `quality gate → PASS` — never a full shell command) · file path. Never commit hashes, turn numbers, or window tags}

### 2. {Second item — same three lines}

- **Why:**
- **Result:**
- **Refs:**

---

## 👀 Under Review

> Tasks awaiting feedback or approval. At most 3 rows.

| Item | Awaiting | Where |
| :--- | :--- | :--- |
| {[repo] work that waits for feedback or approval} | {who or what it waits on} | {PR / issue / proposal pointer} |

---

## 🚀 Active Work

> Current focus at day end. At most 3 rows.

| Task Item | Why it matters | Current State |
| :--- | :--- | :--- |
| {[repo] Task in flight} | {one clause — the outcome it aims at} | {honest state in one clause} |

---

## ⚠️ Blockers & Risks

> What is stuck and who holds it up. At most 3 rows.

| What is stuck | Impact | Who holds it |
| :--- | :--- | :--- |
| {Blocker or risk} | {what it stops or endangers} | {owner — or "None"} |

---

## 📋 Next Up

> Top priority items for the next run. At most 4 items.

1. {Highest-priority next task}
2. {Second priority}

---

## Glossary

> The runner's personal-growth record: the day's terms for this git user only. Harvest from grounding — issue titles and headings, artifact section names, session terms — then make the body use each term. De-duplication is the canonical comparison only: `NEW`/`known` comes from reading `glossary.md`, and every `known` row's meaning matches canonical verbatim. NEW terms first. At most 8 rows. Never drop a NEW term for a known one; cut a repeated known row instead. Skip only when the day introduced no special terms.

| Term | Status | Meaning |
| :--- | :--- | :--- |
| {New term} | NEW | {one-line definition written here for the first time} |
| {Known term} | known | {meaning carried verbatim from the canonical glossary} |

---

## One-page budget (hard rule)

- Frontmatter plus body fit **one rendered page**: at most **56 lines** and **600 words**.
- Completed Today: at most **4 items**, each at most **4 lines**.
- Each table: at most **3 rows**. Next Up: at most **4 items**. Glossary: at most **8 rows** (NEW first).
- Refs: **one line per item with 2 to 4 pointers** — never a list of every touched file.
- Over budget → cut the lowest-signal rows first. Never spill onto a second page.
- **Cut rows, never meaning** — never shorten Why/Result to fit the word cap. Why states
  the gap; Result carries the action verbs and the verifiable state (fold what you did
  into Result — the item has no Action line). If over, drop table rows and Next Up items first.
