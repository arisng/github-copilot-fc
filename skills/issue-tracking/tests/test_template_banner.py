"""Contract tests for the github-adapted tree template (banner + hide-closed).

The sync/render pipeline hands the template a dataJson with a top-level
``filter`` string plus optional numeric summary keys - ``total``/``asOfEpoch``
plus the sync-side ``cap`` (always in github trees) and ``lookback`` (present
only when a window applied) - sketch v6 §1.5/§1.6/§3. Two layers:

* static assertions pin the §1.6 banner grammar (shown-count with total
  floor, cap, lookback, as-of, draft caveat + query echo, conditional
  ``closed: K shown``), the textContent-only rendering, the exclusive
  hide-closed toggle wired into ``dimHit`` with the context rule untouched,
  the extended SUMMARY badge whitelist, and the github-variant footer;
* node-backed render tests execute the template's inline script under a
  minimal DOM stub with those keys PRESENT and ABSENT, asserting exact
  banner strings, banner hiding in local mode, and the hide-closed toggle
  being withheld at K = 0.

node is optional: the behavioral tests skip when it is not on PATH.
"""

from __future__ import annotations

import datetime
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

TEMPLATE = Path(__file__).resolve().parents[1] / "assets" / "tree-template.html"

EPOCH = 1763000000
AS_OF = datetime.datetime.fromtimestamp(EPOCH, tz=datetime.timezone.utc).strftime("%Y-%m-%d")
FILTER_STR = 'label:"x" <b> \\c @me→arisng'
GITHUB_FOOTER = (
    "edit issues in the repo — regenerate: sync-github-tree.ps1 first, "
    "then render-issue-tree.ps1"
)
LOCAL_FOOTER = "LOCAL-FOOTER-MARKER"


def read() -> str:
    return TEMPLATE.read_text(encoding="utf-8")


# --------------------------------------------------------------------------
# Static contract: §1.6 grammar, toggle wiring, whitelist, footer.
# --------------------------------------------------------------------------


def test_placeholders_intact() -> None:
    text = read()
    assert text.count("__ISSUE_TREE_DATA__") == 1
    assert text.count("__TREE_TEMPLATE_VERSION__") >= 1


def test_banner_is_textcontent_only_and_disjoint_from_live_counter() -> None:
    text = read()
    assert '<div class="banner" id="banner" hidden></div>' in text
    # Every segment can carry quotes/backslashes/< > (the query echo does),
    # so the banner is composed as text; markup assignment is forbidden.
    assert 'banner.textContent = parts.join(" · ");' in text
    assert "innerHTML" not in text
    # Snapshot inputs only: a bare local summary never unhides the banner.
    assert (
        "if (total === null && cap === null && lookback === null && "
        "!asOf && !filter) return;" in text
    )
    # Live counter wording stays its own string (disambiguated from banner).
    assert '"showing " + shown + " of " + total + " issues"' in text


def test_banner_segments_follow_1_6_grammar() -> None:
    text = read()
    # Shown-count with total floor; partial keys degrade, never crash.
    assert 'if (issues !== null && total !== null) parts.push(issues + " of ≥" + total + " issues");' in text
    assert 'else if (issues !== null) parts.push(issues + " issues");' in text
    assert 'else if (total !== null) parts.push("of ≥" + total + " issues");' in text
    assert 'if (cap !== null) parts.push("cap " + cap);' in text
    assert 'if (lookback !== null) parts.push("created within " + lookback + " days");' in text
    assert 'if (asOf) parts.push("as of " + asOf);' in text
    # Draft caveat + query echo are gated together on a non-empty filter.
    assert (
        'if (filter) {\n      parts.push("excludes drafts");\n'
        '      parts.push("filter: " + filter);\n    }' in text
    )
    # Conditional closed clause: K counted from issue rows, appended only > 0
    # - deliberately OUTSIDE the renderBanner builder (fleet gap-fill pins
    # that the builder itself stays free of the clause).
    assert 'if (n.status === "done" || n.status === "dropped") closedRowCount++;' in text
    assert 'banner.textContent += " · closed: " + closedRowCount + " shown";' in text


def test_render_banner_builder_is_closed_free() -> None:
    # Mirror of the fleet gap-fill acceptance: the builder reads presence via
    # literal `"key" in summary` checks and carries no closed-clause text
    # (that lives in appendClosedClause, so K = 0 renders without it).
    text = read()
    m = re.search(r"\(function renderBanner\(\) \{(.*?)\}\)\(\);", text, re.S)
    assert m, "renderBanner builder missing"
    body = m.group(1)
    assert "closed" not in body.lower(), body
    assert '"total" in summary' in body
    assert '"asOfEpoch" in summary' in body


def test_summary_badge_whitelist_extended() -> None:
    text = read()
    assert (
        'var order = ["themes", "issues", "P0", "P1", "P2", "P3", "blocked", '
        '"total", "asOfEpoch"];' in text
    )
    # asOfEpoch renders as a short date derived from the stored epoch only -
    # formatting, never a wall-clock comparison.
    assert "Date.now" not in text
    assert 'return d.toISOString().slice(0, 10);' in text


def test_hide_closed_is_exclusive_and_context_preserving() -> None:
    text = read()
    assert 'id="hide-closed"' in text
    assert 'title="hide closed (parents of matches shown as context)"' in text
    assert "hideClosed: false" in text  # default = closed shown
    # dimHit clause: closed rows fail, but the existing context rule
    # ("show = ownMatch || childAny") still keeps closed parents on screen.
    assert 'if (state.hideClosed && (node.status === "done" || node.status === "dropped")) return false;' in text
    assert "show = ownMatch || childAny" in text
    # Filtered indicator and count wording both account for the toggle.
    assert "state.prio.size > 0 || state.hideClosed" in text
    assert 'state.prio.size || state.hideClosed ? " (filtered)" : ""' in text
    # At K = 0 the toggle would be a no-op, so it is withheld - the same
    # data-driven rule §1.6 applies to the banner's "closed: K shown" clause.
    assert "hideClosedBtn.hidden = closedRowCount === 0;" in text


def test_footer_switches_only_on_nonempty_filter() -> None:
    text = read()
    assert GITHUB_FOOTER in text
    # Guard is data presence (filter string), not a new placeholder; local
    # wording below is the untouched fallback.
    assert 'if (!(typeof DATA.filter === "string" && DATA.filter)) return;' in text
    assert "edit issues, not this file" in text


# --------------------------------------------------------------------------
# Behavioral: run the inline script under a minimal DOM stub (needs node).
# --------------------------------------------------------------------------

HARNESS = r"""
"use strict";
const fs = require("fs");
const html = fs.readFileSync(__TPL__, "utf8");
const m = html.match(/<script>\s*([\s\S]*?)<\/script>/);
if (!m) { console.log(JSON.stringify({ fatal: "inline script not found" })); process.exit(0); }
const script = m[1];

function makeEl(tag) {
  const el = {
    tagName: tag, children: [], attrs: {}, dataset: {},
    style: { setProperty() {} },
    hidden: false, className: "", id: "", textContent: "", title: "", type: "",
    handlers: {},
    appendChild(c) { this.children.push(c); return c; },
    insertBefore(c) { this.children.unshift(c); return c; },
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k]; },
    addEventListener(t, fn) { (this.handlers[t] = this.handlers[t] || []).push(fn); },
    querySelector() { return makeEl("span"); },
    querySelectorAll() { return []; },
    closest() { return null; },
    scrollIntoView() {},
    get offsetWidth() { return 0; },
  };
  const s = new Set();
  el.classList = {
    add(c) { s.add(c); },
    remove(c) { s.delete(c); },
    toggle(c, force) {
      const want = force === undefined ? !s.has(c) : !!force;
      if (want) s.add(c); else s.delete(c);
      return want;
    },
    contains(c) { return s.has(c); },
  };
  return el;
}

function run(dataJson) {
  const byId = new Map();
  const get = (id) => {
    if (!byId.has(id)) byId.set(id, makeEl("div"));
    return byId.get(id);
  };
  get("banner").hidden = true;   // markup carries the hidden attribute
  get("foot-gen").textContent = "LOCAL-FOOTER-MARKER";
  get("foot-sep").textContent = "LOCAL-SEP-MARKER";
  get("issue-tree-data").textContent = dataJson;
  const document = {
    getElementById: get,
    createElement: makeEl,
    createTextNode: (t) => ({ nodeType: 3, text: String(t) }),
    querySelectorAll: () => [],
    addEventListener() {},
    activeElement: null,
  };
  const fn = new Function("document", "location", "navigator", "window", script);
  fn(document, { hash: "" }, {}, { addEventListener() {} });
  return { get };
}

const scenarios = JSON.parse(process.env.SCENARIOS || "[]");
const out = scenarios.map(function (s) {
  const env = run(JSON.stringify(s.data));
  const rec = {
    bannerHidden: env.get("banner").hidden,
    bannerText: env.get("banner").textContent,
    toggleHidden: env.get("hide-closed").hidden,
    count: env.get("count").textContent,
    footGen: env.get("foot-gen").textContent,
    footSep: env.get("foot-sep").textContent,
  };
  if (s.clickToggle) {
    const hs = env.get("hide-closed").handlers.click || [];
    if (hs.length) hs[0]();
    rec.countAfterClick = env.get("count").textContent;
    rec.togglePressed = env.get("hide-closed").getAttribute("aria-pressed");
    rec.rows = {};
    (function walk(el) {
      if (el.dataset && el.dataset.id) {
        rec.rows[el.dataset.id] = {
          hidden: el.classList.contains("hidden"),
          context: el.classList.contains("context"),
        };
      }
      (el.children || []).forEach(walk);
    })(env.get("tree"));
  }
  return rec;
});
console.log(JSON.stringify(out));
"""


def node_render(scenarios: list[dict]) -> list[dict]:
    node = shutil.which("node")
    if not node:
        pytest.skip("node not on PATH (behavioral template render tests need node)")
    src = HARNESS.replace("__TPL__", json.dumps(str(TEMPLATE)))
    env = dict(os.environ)
    env["SCENARIOS"] = json.dumps(scenarios)
    proc = subprocess.run(
        [node, "-e", src],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
        timeout=120,
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
    out = json.loads(proc.stdout)
    assert len(out) == len(scenarios), proc.stdout
    return out


def row(num: int, status: str, children: list | None = None, prio: str = "P1") -> dict:
    return {
        "id": f"{num:04d}",
        "title": f"Issue {num}",
        "status": status,
        "priority": prio,
        "children": children or [],
    }


def themes(rows: list, summary: dict, source: str = "owner/repo", **extra) -> dict:
    data = {
        "source": source,
        "summary": summary,
        "next": None,
        "themes": [
            {"id": "T-1", "title": "Alpha", "status": "open", "priority": "P1",
             "children": rows}
        ],
    }
    data.update(extra)
    return data


def test_banner_full_grammar_with_all_keys_present() -> None:
    data = themes(
        [
            row(1, "done", children=[row(2, "open", prio="P2")]),
            row(3, "dropped"),
            row(4, "open"),
        ],
        {"themes": 1, "issues": 4, "total": 301, "cap": 300,
         "lookback": 365, "asOfEpoch": EPOCH},
        filter=FILTER_STR,
    )
    [rec] = node_render([{"data": data, "clickToggle": True}])
    assert rec["bannerHidden"] is False
    assert rec["bannerText"] == (
        f"4 of ≥301 issues · cap 300 · created within 365 days · as of {AS_OF} "
        f"· excludes drafts · filter: {FILTER_STR} · closed: 2 shown"
    )
    assert rec["toggleHidden"] is False
    assert rec["footGen"] == GITHUB_FOOTER
    assert rec["count"] == "showing 4 of 4 issues"
    # Toggle works: dropped row hidden, closed parent kept as context.
    assert rec["countAfterClick"] == "showing 2 of 4 issues (filtered)"
    assert rec["togglePressed"] == "true"
    assert rec["rows"]["0003"] == {"hidden": True, "context": False}
    assert rec["rows"]["0001"] == {"hidden": False, "context": True}


def test_banner_omits_absent_segments_and_withholds_toggle_at_k_zero() -> None:
    # Github keys, zero closed rows (cap crowd-out): no closed clause AND
    # no toggle - never promise a control that is not there (§1.6/G-F.1).
    crowdout = themes(
        [row(1, "open"), row(2, "open")],
        {"themes": 1, "issues": 300, "total": 5000, "cap": 300,
         "lookback": 365, "asOfEpoch": EPOCH},
        filter="is:issue",
    )
    # Partial keys: no lookback/as-of/filter segments at all.
    partial = themes(
        [row(1, "open")],
        {"themes": 1, "issues": 12, "total": 40, "cap": 300},
    )
    [a, b] = node_render([{"data": crowdout}, {"data": partial}])
    assert a["bannerHidden"] is False
    assert a["bannerText"] == (
        f"300 of ≥5000 issues · cap 300 · created within 365 days · "
        f"as of {AS_OF} · excludes drafts · filter: is:issue"
    )
    assert "closed:" not in a["bannerText"]
    assert a["toggleHidden"] is True
    assert b["bannerHidden"] is False
    assert b["bannerText"] == "12 of ≥40 issues · cap 300"
    assert b["toggleHidden"] is True
    # Filter absent -> local footer wording untouched.
    assert b["footGen"] == LOCAL_FOOTER
    assert b["footSep"] == "LOCAL-SEP-MARKER"


def test_banner_stays_hidden_in_local_mode_even_with_closed_rows() -> None:
    minimal = themes(
        [row(1, "open")],
        {"themes": 1, "issues": 1},
        source="repo/.issues/tree.md",
    )
    with_closed = themes(
        [row(1, "done"), row(2, "open")],
        {"themes": 1, "issues": 2},
        source="repo/.issues/tree.md",
    )
    [a, b] = node_render([{"data": minimal}, {"data": with_closed}])
    # No snapshot inputs -> banner hidden in both, local mode unchanged
    # even when local data happens to contain closed rows (K > 0).
    assert a["bannerHidden"] is True
    assert b["bannerHidden"] is True
    # Toggle follows K alone: withheld at K = 0, offered (and harmless) at K > 0.
    assert a["toggleHidden"] is True
    assert b["toggleHidden"] is False
    assert a["count"] == "showing 1 of 1 issues"
    assert b["count"] == "showing 2 of 2 issues"
    assert a["footGen"] == LOCAL_FOOTER


def test_banner_shown_count_branches_when_total_or_issues_missing() -> None:
    no_issues = themes([row(1, "open")], {"themes": 1, "total": 40, "cap": 300})
    no_total = themes([row(1, "open")], {"themes": 1, "issues": 5, "cap": 300})
    [a, b] = node_render([{"data": no_issues}, {"data": no_total}])
    assert a["bannerText"] == "of ≥40 issues · cap 300"
    assert b["bannerText"] == "5 issues · cap 300"
