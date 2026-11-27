# Visual defects a compile cannot see

Four defects found **by eye** on a real diagram, all invisible to `d2 validate` **and** to a
full compile (`d2 --target '' file.d2 NUL`, exit 0). Each became a deterministic check in
[../scripts/lint_svg.py](../scripts/lint_svg.py). Numbers below are measured on d2 v0.9.0
renders from the session that produced them.

Workflow context: [../SKILL.md](../SKILL.md). Packaging: [html-packaging.md](html-packaging.md).

## Contents

- [Why a compile is not enough](#why-a-compile-is-not-enough)
- [1. Header overlap](#1-header-overlap)
- [2. Edge label on top of a node rect](#2-edge-label-on-top-of-a-node-rect)
- [3. Arrow hidden behind its own label](#3-arrow-hidden-behind-its-own-label)
- [4. One backward edge re-ranks the board](#4-one-backward-edge-re-ranks-the-board)
- [How the geometry is read](#how-the-geometry-is-read)
- [Thresholds and where they come from](#thresholds-and-where-they-come-from)

## Why a compile is not enough

`d2 validate` is a parser check. A full compile adds "D2 understood every shape and style
value". Neither says anything about the picture: every defect here is a well-formed source
that renders, exits 0, and looks wrong. The only other gate is a human looking at the SVG, so
the checks read the rendered geometry directly:

```bash
python3 scripts/lint_svg.py board.d2 --layout tala     # renders, then measures
python3 scripts/lint_svg.py build/board.svg             # an existing render
```

Exit 0 clean, 1 findings, 2 could not lint. `scripts/build_html.py` runs it on every board
before packaging and refuses to write the HTML on a finding.

## 1. Header overlap

Two separate `x: { shape: text; near: top-center }` nodes anchor at the SAME point.

| measured | value |
|---|---|
| title baseline | (1016, -28) |
| subtitle baseline | (1016, -24) |
| separation | **4px** - the subtitle prints across the title |

Both nodes are individually correct D2; nothing about either declaration is wrong. The
renderer simply gives both the same anchor.

**Fix:** ONE `|md` node - a `#` heading and its paragraph land 32-62px apart. Measured on the
fixed node: heading baseline to paragraph baseline is **53.6px** (ink gap 27.6px) for `#`,
49.2px for `##`, 39.0px for `###`; never below the 32px floor.

```d2
header: |md
  # Deployment Board

  Environments, release train, and rollback path
| {
  near: top-center
}
```

Check `header-overlap`: any two floating-label ink boxes that overlap by more than 1px on both
axes, reported with the baseline delta.

## 2. Edge label on top of a node rect

A `grid-*` board with `grid-gap: 100` gives only 100px of gutter, but a label straddling that
gutter needs half its width on each side.

| measured | value |
|---|---|
| label | `"task deploy:ec2\nDEPLOY_ENV=staging"` |
| label ink width | **146px** (widest tspan), so ~73px per side |
| gutter | 100px on a 3x3 grid |
| result | **6 of 13** edge labels sat **20-258px INSIDE** node rectangles |

Line-breaking the label helps only if it shortens the widest line: a two-line label's width is
the wider of the two lines, never their sum (see [how the geometry is read](#how-the-geometry-is-read)).

**Fix:** line-break the label, widen `grid-gap`, or shrink `label-container`.

Check `label-on-node`: a label ink box overlapping a *solid* node rect (containers excluded)
by more than 2px on both axes.

## 3. Arrow hidden behind its own label

Zero rectangle overlap is not enough. A label can consume the whole gutter and leave no
visible connector run, so the arrow reads as a stray word between two boxes.

**Fix:** shorten or line-break the label, or widen the gutter so a run stays visible on both
sides of it.

## 4. One backward edge re-ranks the board

`RELEASED -> ROLLED_BACK` plus `ROLLED_BACK -> PROD_VERIFIED` made `tala` lay a 14-node
release spine out **diagonally**.

| measured | value |
|---|---|
| y coordinates of the 14 nodes | **non-monotonic** |
| x spread | **622px** |
| nodes with identical y in the broken variant | 9 distinct values for 14 nodes |

The cycle exists only in the `.d2` source; the SVG is just a graph that happens to be
diagonal, and the compile exits 0 either way. Check `cyclic-edge` reports one concrete cycle
path from hill-climbing the strongly connected component.

**Fix:** route the loop explicitly (its own board/layer), or split it into a forward spine plus
a labelled return edge that no spine node depends on.

### 4b. Grid boards fill row-major in declaration order

`grid-rows`/`grid-columns` place nodes **ROW-MAJOR in DECLARATION order**. A straight 1..14
listing therefore makes the wrap hop (last cell of row N -> first cell of row N+1) a full-row
diagonal that crosses every node in between.

| measured | straight listing | boustrophedon (snake) |
|---|---|---|
| hops that are not grid neighbours | 9 of 13 | 0 |
| hops that are diagonal | 9 | 0 |
| cell collisions | 12 | 0 |

**Fix:** declare the nodes in boustrophedon order so every hop is a grid neighbour.

```d2
board: Release Board {
  grid-rows: 3
  grid-columns: 3
  # visual snake: row 0 L->R, row 1 R->L, row 2 L->R
  n1: Intake
  n2: Triage
  n3: Design
  n6: Build      # row 1 col 2 -> the neighbour of n3 above it
  n5: Test
  n4: Stage
  n7: Canary
  n8: Deploy
  n9: Verify
  n1 -> n2: go
  n2 -> n3: go
  n3 -> n4: go   # down one row, same column
  # ...
}
```

Checks `grid-wrap` (declaration index vs `grid-columns`) and `edge-crosses-node` (a rendered
connector passing through a node it does not touch) both target this.

## How the geometry is read

- **Shapes** are `<rect x y width height>` inside `<g class="<b64 key>"><g class="shape">`.
  The identity key is the **base64 of the D2 key**, and edge keys are container-qualified:
  `board.(n1 -> n2)[0]`. They arrive HTML-escaped, so they must be unescaped before matching
  (`&gt;` -> `>`), or every edge silently classifies as a shape.
- **The full-board background rect** (covering >=70% of the canvas) is excluded, as is any
  square rect in 8-34px - that is icon art (`shape: image`, inline SVG glyphs) and a
  `|md` heading's 1px underline rule. Without those exclusions an icon node reads as an
  empty node at the origin and every label "overlaps" it.
- **Labels** are `<text x y text-anchor:middle>`, one `<tspan>` per source line.
- **THE RENDERED WIDTH IS THE WIDEST TSPAN, NOT THE CONCATENATED STRING.** This is the bug
  that produced false passes before it was written down: summing every line's advances
  describes a box the renderer never drew. Measured: `"mmmmmmmmmmmm\niii"` renders **157px**
  (the `m` line) while the concatenated `"mmmmmmmmmmmmiii"` renders **169px**.
- A `|md` node emits **one `<text>` per markdown block**, which is exactly what makes the
  heading-to-paragraph gap measurable after the [header fix](#1-header-overlap).
- A `--animate-interval` export stacks **every board into ONE SVG**, each board in its own
  `<g style="animation: d2Transition-...">` wrapper with its own backdrop and coordinates.
  The lint parses one board per wrapper; parsing the stack as a single board reports
  cross-board overlaps that are true by construction.

## Thresholds and where they come from

| Threshold | Value | Source |
|---|---|---|
| ink overlap before a collision | 1px | label boxes are padded; sub-pixel overlap is rounding |
| node-rect inset ignored | 2px | hairline stroke rounding |
| minimum visible connector run | 12px | arrowheads plus a readable stub |
| icon rect range | 8-34px square | 32px and 46px icon art in real renders |
| backdrop threshold | 70% of canvas | the board background covers the canvas, nothing else |
| font advances | measured table, 16px basis | calibrated against d2's own label boxes; agreement 0.25-1.5px |
| ink height per extra line | 16px at 16px font | measured 21, 37, 53, 69px for 1-4 lines |

## Regression tests

`skills/d2/tests/test_lint_svg.py` (27 cases, no d2 CLI needed) pins every check in both
directions - the broken fixture must fail, the fixed fixture must pass:

```bash
python3 -m pytest skills/d2/tests -q
```
