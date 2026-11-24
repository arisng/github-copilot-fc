# D2 syntax reference

Concise reference for authoring `.d2` files. Verified against d2 v0.9.0. For the
author-verify-package workflow see [../SKILL.md](../SKILL.md).

## Contents

- [Anatomy](#anatomy)
- [Shapes and attributes](#shapes-and-attributes)
- [Connections](#connections)
- [Composition: layers, scenarios, steps](#composition-layers-scenarios-steps)
- [Links and tooltips](#links-and-tooltips)
- [Configuration: vars.d2-config](#configuration-varsd2-config)
- [Layout engines](#layout-engines)
- [Themes and sketch mode](#themes-and-sketch-mode)
- [Common errors](#common-errors)

## Anatomy

A diagram is a set of declarations. A line is a shape (`id: Label`), a connection
(`a -> b: Label`), an attribute block (`{ ... }`), or a map (`layers: { ... }`).

```d2
direction: right          # board-level: right | left | up | down

server: API Server {      # shape with label
  shape: cylinder         # attribute block
}
db: Database
server -> db: SQL         # connection with label
```

Every board (root, each layer, each scenario, step) has its own scope and its own `direction`.

## Shapes and attributes

- `id: Label` - labels support `"quoted strings"` and `\n` line breaks.
- `shape: <name>` - `rectangle` (default), `person`, `cylinder`, `diamond`, `circle`,
  `hexagon`, `oval`, `queue`, `step`, `stored_data`, `package`, `text`, ...
  Invalid names **fail at compile, not at validate** (see [common errors](#common-errors)).
- `icon: https://...` - hosted icons (e.g. `https://icons.d2lang.com/...`) are bundled into
  the SVG at export (`--bundle` is on by default).
- `style.fill`, `style.stroke`, `style.font-color`, `style.bold`, `style.italic`,
  `style.opacity`, `style.shadow`, `style.border-radius`, `style.stroke-dash` (**a width in px,
  e.g. `4`** — there is no `style.dashed`), `style.stroke-width`, `style.animated`, `style.3d` -
  named colors, hex (`"#2563eb"`), or `linear-gradient(a, b)` for fill.
- `near: top-center | top-left | bottom-right | ...` - free-floating label placement.
- `width`, `height` - fixed dimensions when layout needs them.

## Connections

```d2
a -> b: forwards
a <- b: backwards
a <-> b: both
a -- b: no arrowhead
```

- `source-arrowhead` / `target-arrowhead`: `shape: arrow | triangle | diamond`, `style.filled`.
- Label and style: `a -> b: label { style.animated: true; style.stroke: "#2563eb" }`.
- Chained: `a -> b -> c` is two connections.
- `style.animated: true` renders the flow animation with CSS (`stroke-dashoffset`
  keyframes) and survives SVG export.
- **Container endpoints need dotted paths.** To connect nodes inside containers
  (e.g. swimlanes), write `lane_a.p -> lane_b.q`. A bare `p -> q` at the parent scope does
  NOT reach into containers - it silently **creates new sibling nodes** `p` and `q` beside
  the containers. (Also avoid reserved words like `left`, `right`, `top`, `bottom` as
  container IDs - they are prohibited in edge paths.)
- Cross-container edges are where the layout engine matters - see [layout engines](#layout-engines).

## Composition: layers, scenarios, steps

Three board keywords with different inheritance:

| Keyword | Board inherits |
|---|---|
| `layers` | nothing - a new base board (use for drill-down) |
| `scenarios` | the base board (use for what-if variants) |
| `steps` | the previous step (use for sequences) |

**Boards must be declared under `layers:` (or `scenarios:`/`steps:`).** A bare
`name: { ... }` map inside a board is a plain **container shape**, not a board: no board file
is exported, `link:` targets pointing at it are silently dropped, and the full compile still
passes - only rendering reveals the mistake.

```d2
layers: {
  detail: {
    inner: Inner Component
    # ... child board content
  }
}
```

- Boards nest: a layer may contain its own `layers`/`scenarios`/`steps`.
- Board keys become board names in exports and navigation (e.g. `layers.detail` -> `detail`).
- Keep every board **self-describing** (`shape: text` legend + tooltips): board SVGs are also
  exported standalone (multi-board export emits one file per board), where the packaging
  shell's breadcrumb and navigation chrome does not exist.
- Drill-down authoring pattern: put `link: layers.<name>` + `tooltip:` on the parent shape,
  and a `back: "<- Back" { link: _ }` shape in the child board (exports also cross-link
  parent/child boards automatically from these links).
- Keep board keys stable and slug-safe (`[a-z0-9_-]`): they become export file names
  (`detail.svg`, nested boards get `<dir>/<name>.svg` plus `index.svg` per parent board).
- Swimlane pattern: model each lane as a container and wire flows with dotted paths
  (`lane_a.x -> lane_b.y`); `elk`/`tala` route the cross-lane edges cleanly.

## Links and tooltips

```d2
node: Node {
  tooltip: "hover hint"
  link: https://example.com      # external link
  link: layers.detail            # drill into a layer
  link: scenarios.opt_a          # jump to a scenario/step
  link: _                        # parent board
}
```

Exports render `link` as a real `<a href>` around the shape. In multi-board exports the hrefs
are **relative board files** (`detail.svg`, `index.svg`); in one-file packages they must be
rewritten - [../scripts/build_html.py](../scripts/build_html.py) does this.

**Link scope rules (verified):** a bare `link: layers.x` resolves against the *current* board's
own layers - it works from the root board, but from inside another board it is **silently
dropped** (no compile error, no anchor). To link across boards from inside a board use the
absolute `link: root.layers.x` or parent-relative `link: _.layers.x`.

## Configuration: vars.d2-config

Set export defaults inside the source (equivalent CLI flag in parentheses):

```d2
vars: {
  d2-config: {
    layout-engine: tala    # --layout (dagre | elk | tala)
    theme-id: 0            # --theme
    dark-theme-id: -1      # --dark-theme
    sketch: true           # --sketch
    isometric: true        # native isometric rendering
    pad: 20                # --pad
  }
}
```

Use `vars` also for reusable constants (`${myvar}` interpolation).

## Layout engines

All three engines are bundled in the CLI (`d2 layout` lists them, `d2 layout <name>` details
each):

| Engine | Use for |
|---|---|
| `dagre` | default; simple flat graphs |
| `elk` | nested containers; deterministic layered routing |
| `tala` | nested architecture diagrams; best edge routing around containers |

**Prefer `elk` or `tala` whenever containers nest or edges cross boundaries.** Select with
`--layout=tala`, `D2_LAYOUT=tala`, or `vars.d2-config.layout-engine: tala`.

## Themes and sketch mode

- `--theme N` (or `theme-id`) - diagram theme; run `d2 themes` to list available IDs
  (0 = neutral default).
- `--dark-theme N` (or `dark-theme-id`) - separate theme when the viewer is in dark mode
  (SVG-only behavior).
- `--sketch` (or `sketch: true`) - hand-drawn look.

## Common errors

| Symptom | Cause | Fix |
|---|---|---|
| `unknown shape "x"` at compile; `validate` said valid | `shape:` name typo | fix the shape name; **always verify by full compile** |
| `expected "fill" to be a valid named color ...` | invalid `style.*` color value | named color, `#hex`, or gradient |
| `invalid style keyword: "dashed"` at compile | `style.dashed` does not exist (a plausible-looking name that never worked) | set a **width**, not a boolean: `style.stroke-dash: 4` on the shape or the connection |
| `unexpected text after map` | a `{ ... }` block closed early or stray text after it | check braces/quotes; run `d2 fmt` to normalize |
| `link:` silently drops, no board file exported for a sub-diagram | the board was declared as a bare `name: { }` container instead of under `layers:` | wrap it in `layers: { ... }` inside its parent board |
| `multiboard output cannot be written to stdout` | layers/scenarios/steps with output `-` | export to a directory or one-file package (see [html-packaging.md](html-packaging.md)) |
| `mkdir ... nul` / cannot create output when verifying multi-board to `NUL` | multi-board output is a directory; the null device cannot receive it | verify with `d2 --target '' file.d2 NUL` |
| links dead inside HTML | embedded via `<img src=...>` | inline the SVG (browser sandboxes `<img>`) |
