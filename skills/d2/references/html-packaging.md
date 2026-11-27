# Packaging D2 as self-contained HTML

How D2 exports become one portable HTML file, and how to embed it in a web app. Verified
against d2 v0.9.0. Workflow context: [../SKILL.md](../SKILL.md).

## Contents

- [What "self-contained" means](#what-self-contained-means)
- [The `<img>` trap](#the-img-trap)
- [Export shapes: what d2 actually emits](#export-shapes-what-d2-actually-emits)
- [Mode A - single board, one HTML file (manual)](#mode-a---single-board-one-html-file-manual)
- [Mode B - multi-board drill-down, one HTML file](#mode-b---multi-board-drill-down-one-html-file)
- [Mode C - multi-board auto-cycling, one HTML file](#mode-c---multi-board-auto-cycling-one-html-file)
- [Embedding in a web app](#embedding-in-a-web-app)
- [Geometry lint in the packaging pipeline](#geometry-lint-in-the-packaging-pipeline)
- [Troubleshooting](#troubleshooting)

## What "self-contained" means

One SVG export = one portable asset: CSS is injected, fonts are embedded as base64
`data:application/font-woff` `@font-face` rules, hosted icons are inlined (`--bundle` is on by
default), and `style.animated` connections carry CSS `stroke-dashoffset` animations. No
network, no font files, no JS libraries required at view time.

Two flags matter for HTML packaging:

- `--no-xml-tag` - omits the `<?xml ...?>` prolog so the `<svg>` injects cleanly into an HTML
  DOM (and into `srcdoc` iframes).
- `--salt <name>` - appends a salt to internal IDs (clip paths, gradients). **Required when
  several diagrams (or identical copies) share one HTML page**, otherwise duplicate IDs make
  the page invalid and CSS targeting collides.

## The `<img>` trap

Do **not** embed interactive D2 SVGs with `<img src="diagram.svg">`. Browsers sandbox `<img>`,
which disables `link` navigation and any embedded scripting. Inline the `<svg>` element in the
HTML (all modes below) or load the diagram from an `<iframe>`, where interaction works.

## Export shapes: what d2 actually emits

| Source | Output |
|---|---|
| single board -> `out.svg` | one file `out.svg` |
| `layers`/`scenarios`/`steps` -> `out.svg` | one directory `out/` with `index.svg` (root board) + one SVG per board; nested boards add `<dir>/index.svg` per parent |
| multi-board -> `-` (stdout) | **error**: `multiboard output cannot be written to stdout` |
| multi-board + `--animate-interval=N` | one file `out.svg` containing all boards, auto-cycling every N ms (CSS animation) |

Board links become real anchors: `link: layers.x` -> `href="x.svg"` (relative board file),
`link: _` -> `href="index.svg"` (parent board), external links stay absolute. So a multi-board
directory is already click-navigable when served as files - but it is **not** a single file
until the boards are inlined and the hrefs rewritten (Mode B).

## Mode A - single board, one HTML file (manual)

```bash
{
  cat <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Diagram</title>
  <style>
    html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #ffffff; }
    body { display: flex; justify-content: center; align-items: center; }
    svg { display: block; width: 100%; max-width: 1200px; height: auto; margin: 0 auto; }
  </style>
</head>
<body>
EOF
  d2 --no-xml-tag --pad=20 system.d2 -
  cat <<'EOF'
</body>
</html>
EOF
} > system.html
```

Sizing gotcha: D2's outer `<svg>` is **viewBox-only** (no `width`/`height` attributes), so CSS
`width: auto` can collapse it to a zero-size, clipped, unclickable box. Either set an explicit
CSS size as above (`width: 100%` + `height: auto` uses the viewBox ratio), or add
`width`/`height` attributes copied from the viewBox - the bundled builder injects them so the
diagram renders at natural size and scales down responsively.

PowerShell equivalent (no heredocs):

```powershell
$head = Get-Content shell-head.html -Raw   # the same <head> block as above
$tail = '</body></html>'
$svg  = d2 --no-xml-tag --pad=20 system.d2 -
Set-Content system.html ($head + "`n" + $svg + "`n" + $tail) -Encoding utf8
```

Single-board stdout export works; multi-board does not - use Mode B or C. The bundled
[../scripts/build_html.py](../scripts/build_html.py) runs this mode automatically (and also
runs `d2 fmt` + full-compile verification first).

## Mode B - multi-board drill-down, one HTML file

Mechanics (what the builder automates):

1. Export the multi-board directory: `d2 --no-xml-tag --pad=20 system.d2 build/boards.svg`
   -> `build/boards/` with `index.svg` + one SVG per board.
2. Inline every board SVG in its own `<div class="d2-board">`.
3. Rewrite board hrefs to in-page anchors: `href="x.svg"` -> `href="#board-x"`
   (a board file `<dir>/index.svg` maps to the id of `<dir>`; `index.svg` maps to root).
4. Add hash-based navigation: `hashchange` shows the target board and rebuilds a breadcrumb
   bar (`root > layer > sublayer`) whose entries link to their board ids. Anchors are plain
   `#id` hrefs, so navigation is pure hash routing - no click handlers needed.

The result keeps everything the exports provide: animated connections (CSS), tooltips
(appendix + `title`-less SVG hover), clickable `link:` shapes (rewritten anchors), and the
`link: _` back link (parent anchor). Browser support: any evergreen browser; no external
resources.

Run it with:

```bash
python3 scripts/build_html.py system.d2 -o system.html --layout tala
```

## Mode C - multi-board auto-cycling, one HTML file

`--animate-interval=N` packages all boards into **one** SVG that transitions through boards
every N ms (default transition 750ms, pure CSS, loops). Wrap that SVG in the Mode A shell
(the builder does it with `--animate-interval 2500`).

Limitation: board `link:` hrefs inside an auto-cycling SVG point at board *paths*
(`root.layers.x`) that only a D2-aware host resolves - click drill-down is inert there. Use
Mode B when the reader needs click-through navigation; use Mode C for kiosks/slides/motion
previews.

## Embedding in a web app

- **Static asset / iframe (recommended):** serve the generated `.html` and embed
  `<iframe src="diagram.html" ...>` - interaction works, styles cannot leak either way.
- **Inline into a page:** paste the shell's `<svg>` into your template. Then:
  - run the build with `--salt <page-unique-id>` when the page holds more than one diagram;
  - keep the shell's `svg { max-width: 100%; height: auto; }` so diagrams scale responsively;
  - note the builder's nav shell assumes one diagram per document (its breadcrumb bar is
    page-level).
- **Sizing:** `--pad N` controls whitespace (20 suits HTML embeds; the CLI default is 100).
  `--center` centers the SVG in its viewbox; `--scale 1` disables the default fit-to-screen
  behavior (default scale fits the SVG to the containing view).
- **Dark mode:** `--dark-theme N` bakes a dark theme that applies when the viewer reports dark
  mode (explicit `style.*` colors always win - avoid hard-coding fills if you want theme
  switching).
- **Tooltips in non-interactive exports:** `--force-appendix` prints the tooltips/links
  appendix into SVG too (it is automatic for PNG/PDF).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `err: ... multiboard output cannot be written to stdout` | layers/scenarios/steps + output `-` | Mode B (nav shell) or Mode C (`--animate-interval`); the builder picks automatically |
| verification `d2 multi.d2 NUL` fails with `mkdir ... nul` / cannot create output | multi-board output is a directory; the null device cannot receive it | verify with `d2 --target '' file.d2 NUL` (compiles every board, renders root only) |
| Clicks/links do nothing in the browser | SVG embedded via `<img>` | inline the SVG or use an `<iframe>` |
| Wrong colors/shapes between environments | verify step skipped invalid `style.*` or `shape:` | full compile gate: `d2 file.d2 NUL` must exit 0 |
| Diagram clipped, invisible, or clicks do nothing | viewBox-only `<svg>` sized `auto` collapses to 0x0 | set explicit CSS size (`width: 100%; height: auto`) or inject `width`/`height` attrs from the viewBox (the builder does) |
| Duplicate-ID breakage with 2+ diagrams on one page | missing salt | `--salt <unique>` per diagram |
| Board links go to `404`/blank in one-file output | board hrefs not rewritten to anchors | use Mode B builder (rewrites `x.svg` -> `#board-x`) |
| Nested-board hrefs fail to resolve into anchors on Windows | d2 emits backslashes in nested hrefs (`dir\file.svg`) | normalize `\` to `/` before path resolution (the builder does) |
| Diagram clipped or too small | `--pad`/`--scale`/shell CSS | set `--pad 20`, keep `svg { max-width: 100%; height: auto; }` |
| Diagram compiles and packages, but a label prints on another label / sits inside a node | a visual defect a compile cannot see | run `python3 scripts/lint_svg.py board.d2 --layout tala`; see [visual-defects.md](visual-defects.md) |
| `error: visual defects in boards.svg` from the builder | `build_html.py` gates on the geometry lint | fix the reported node/label, or set `D2_HTML_IGNORE_LINT=1` to package anyway |

## Geometry lint in the packaging pipeline

`build_html.py` runs [../scripts/lint_svg.py](../scripts/lint_svg.py) on every rendered board
**before** it writes the HTML, so a diagram that compiles but looks wrong never ships:

```text
formatted system.d2
verified system.d2 (full compile, exit 0)
lint clean: boards.svg (no visual defects)
wrote system.html [single board, 20049 bytes]
```

A finding aborts the build with the offending node/label named and a fix, because the defects
it encodes (two floating headers on one anchor, an edge label inside a node rect, a buried
arrow, a diagonally re-ranked board) are invisible to every other gate. Escape hatch:
`D2_HTML_IGNORE_LINT=1` packages anyway, with a warning.

The lint needs no d2 CLI for an existing SVG; `--animate-interval` output is split into one
board per animation wrapper so stacked boards are not compared against each other. Details and
the measured numbers: [visual-defects.md](visual-defects.md).
