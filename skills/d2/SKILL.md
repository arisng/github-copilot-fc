---
name: d2
description: "Author, verify, and export D2 (d2lang) diagram-as-code, and package the output as self-contained HTML for web apps. Covers declarative syntax for shapes, connections, and containers; drill-down composition with layers/scenarios/steps and link attributes (link: layers.x, link: _); animated connections (style.animated); tooltips, themes, and vars.d2-config; bundled layout engines (dagre/elk/tala); deterministic d2 fmt; compile verification plus a post-render geometry lint (header overlap, label inside a node rect, buried arrow, re-ranked board, grid row-wrap); and one-file HTML packaging for single-board, drill-down, and auto-cycling boards (--animate-interval). Use when creating, editing, reviewing, or debugging .d2 files, embedding D2 into HTML or web apps, or wiring a D2 build/verify step into an agent workflow. Not for Mermaid, PlantUML, Graphviz, or draw.io."
metadata:
  version: 1.1.0
  author: arisng
---

# D2: author, verify, package self-contained HTML

Run the pipeline **author -> format -> verify -> export -> package**. Every claim below is
verified against the d2 v0.9.0 CLI; re-verify with `d2 --help` when the pinned version differs.

## 1. Author

Write declarative diagram-as-code. This pattern covers drill-down (layers + links) and flow
animations in one file:

```d2
vars: {
  d2-config: {
    layout-engine: tala
  }
}

direction: right

client: Web Client {
  shape: person
}

gateway: API Gateway {
  tooltip: "Click to inspect internal routing"
  link: layers.gateway_detail
}

worker: Background Worker {
  link: layers.worker_detail
}

client -> gateway: HTTPS Request {
  style.animated: true
}

gateway -> worker: Enqueue Job {
  style.animated: true
  style.stroke: "#2563eb"
}

layers: {
  gateway_detail: {
    direction: right
    auth: Auth Middleware
    router: Reverse Proxy
    rate_limit: Rate Limiter

    auth -> router -> rate_limit: {
      style.animated: true
    }

    back: "<- Back to System" {
      link: _
    }
  }

  worker_detail: {
    queue: Redis Queue { shape: cylinder }
    processor: Job Runner
    queue -> processor: Poll { style.animated: true }
  }
}
```

Semantics that matter:

- `layers` declares drill-down boards (no inheritance); `scenarios` inherit the base board;
  `steps` inherit the previous step. Use `layers` for architecture drill-down.
- `link: layers.<name>` navigates to a child board **from the root board**; from inside another
  board use `root.layers.<name>` (or `_.layers.<name>`) - a bare `layers.<name>` is silently
  dropped. `link: _` navigates to the parent board; `tooltip:` adds a hover hint. External
  `link: https://...` works too.
- `style.animated: true` animates a connection's flow via CSS (survives SVG export).

Full syntax: [references/d2-syntax.md](references/d2-syntax.md). For interactive authoring use
`d2 -w file.d2` (watch mode, live reload) or `d2 play file.d2` (opens the online playground).

## 2. Format deterministically

After generating or editing any `.d2` file:

```bash
d2 fmt file.d2          # rewrite with canonical indentation and block order
d2 fmt --check file.d2  # gate: exit 1 when unformatted (use in CI / agent verification)
```

## 3. Verify with a full compile - never `d2 validate` alone

`d2 validate` only checks parser syntax: unknown shape names and invalid style values pass
validate and fail at render time. Verify with a real compile; exit code 0 is the contract:

```bash
d2 --target '' file.d2 NUL          # Windows
d2 --target '' file.d2 /dev/null    # macOS / Linux
```

`--target ''` compiles **every** board (layers/scenarios/steps included) but renders only the
root board to the null device - so this one command works for single- and multi-board sources
on every platform. (Plain `d2 file.d2 NUL` breaks for multi-board sources: their output is a
directory.) Pass the same `--layout`/`--theme` flags the export will use, so compile-time
layout errors surface here. See [references/html-packaging.md](references/html-packaging.md)
for the failure modes validate cannot see.

### Then lint the rendered geometry

A full compile proves D2 *understood* the source; it does not prove the picture is readable.
Four defects below were found **by eye** on a real diagram and were invisible to `d2 validate`
**and** to a full compile - all four exit 0. Lint the render:

```bash
python3 scripts/lint_svg.py system.d2 --layout tala    # renders, then checks geometry
python3 scripts/lint_svg.py build/system.svg           # checks an existing SVG
```

Exit 0 clean, 1 findings (each naming the offending node/label), 2 could not lint. Checks:

| Check | Defect it catches | Fix |
|---|---|---|
| `header-overlap` | two `near: top-center` floating nodes share one anchor | one `\|md` node (heading + paragraph) |
| `label-on-node` | edge label straddles a gutter narrower than itself | line-break the label, widen `grid-gap`, shrink `label-container` |
| `arrow-hidden` | label eats the whole connector run (zero rect overlap is not enough) | shorten/line-break the label, widen the gutter |
| `edge-crosses-node` | connector passes through a node it does not touch | boustrophedon (snake) declaration order |
| `cyclic-edge` | a backward edge re-ranks the whole board | route the loop on its own board/layer |
| `grid-wrap` | row-major grid declaration makes a hop wrap a whole row | boustrophedon (snake) declaration order |

The lint reads `<rect>` and `<text>`/`<tspan>` geometry out of the SVG, so it measures what a
reader sees. `scripts/build_html.py` runs it automatically and refuses to package a board with
visual defects (`D2_HTML_IGNORE_LINT=1` overrides). Measured evidence and the checklist that
produced each rule: [references/visual-defects.md](references/visual-defects.md).

## 4. Package self-contained HTML

SVG exports bundle everything (CSS, base64 fonts, icons, animations) - one portable asset per
board. Package with the bundled builder (Python 3, stdlib only; it runs fmt -> verify -> export
-> inline):

```bash
# Single-board diagram -> one .html file
python3 scripts/build_html.py system.d2 -o system.html

# Multi-board drill-down -> one .html with click-through boards + breadcrumb nav (default)
python3 scripts/build_html.py system.d2 -o system.html --layout tala

# Multi-board auto-cycling -> one .html, boards transition on a timer (pure CSS, no JS)
python3 scripts/build_html.py system.d2 -o system.html --animate-interval 2500
```

Key flags: `--layout {dagre,elk,tala}`, `--theme N`, `--dark-theme N`, `--pad N` (default 20),
`--salt NAME`, `--skip-fmt`, `--d2 PATH`. Manual recipes and embedding guidance (iframes,
multiple diagrams per page, dark mode): [references/html-packaging.md](references/html-packaging.md).

## Guardrails

1. **Verify by full compile, not `d2 validate`.** `d2 --target '' file.d2 NUL` (or
   `/dev/null`), exit code 0.
2. **Lint the rendered geometry.** A compile proves D2 understood the source, not that the
   diagram is readable - header overlap, a label inside a node rect, a buried arrow, and a
   diagonally re-ranked board all compile clean. Run
   `python3 scripts/lint_svg.py file.d2 --layout tala` (exit 0 = clean).
3. **Run `d2 fmt` after every generation.** Formatting drift makes agent diffs noisy.
4. **Prefer `elk` or `tala` for nested/layered diagrams.** The default `dagre` routes edges
   across container boundaries badly. All three engines are bundled (`d2 layout` lists them);
   select via `--layout`, `D2_LAYOUT`, or `vars.d2-config.layout-engine`.
5. **Never embed interactive SVG via `<img src="diagram.svg">`.** Browsers sandbox `<img>`,
   which disables `link` navigation and any scripting. Inline the SVG in HTML (the builder
   does) or serve it from an `<iframe>`.
6. **Multi-board output is a directory of board SVGs**, cross-linked with relative `href`s
   (`index.svg` is the root board; `link: _` emits the parent file). It cannot be written to
   stdout (`multiboard output cannot be written to stdout`). Single-file drill-down = the
   builder's nav shell; single-file auto-cycle = `--animate-interval`.
7. **Pass `--salt <unique>` when several diagrams share one HTML page**, so internal SVG IDs
   (clip paths, gradients, script targets) never collide.

## Bundled resources

- [scripts/lint_svg.py](scripts/lint_svg.py) - deterministic post-render geometry lint: six
  visual-defect checks over an SVG (or a `.d2` it renders itself), exit 1 with a message
  naming the offending node/label.
- [scripts/build_html.py](scripts/build_html.py) - deterministic build: fmt, verify, lint,
  export, package single-board / drill-down / auto-cycling diagrams into one HTML file.
- [references/d2-syntax.md](references/d2-syntax.md) - read when authoring or fixing `.d2`
  syntax: shapes, connections, containers, composition boards, links, config, themes.
- [references/html-packaging.md](references/html-packaging.md) - read when packaging without
  the script, embedding into a web app, or troubleshooting export/embedding failures.
- [references/visual-defects.md](references/visual-defects.md) - the four by-eye defects this
  lint encodes, with the measured numbers that set each threshold.
