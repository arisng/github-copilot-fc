#!/usr/bin/env python3
"""Deterministic post-render geometry lint for D2 SVGs.

`d2 validate` is parser-only, and even a full compile only proves that D2
*understood* the source. Neither says the result is *readable*: labels print on
top of one another, an edge label lands inside a node rectangle, an arrow is
buried under its own label, a row-wrap edge sweeps diagonally across other
nodes, and a backward edge makes the layout engine re-rank a whole board. All
of those render clean and exit 0 - which is why they survive every gate except
looking at the picture.

This script reads the rendered SVG geometry (plus the `.d2` source for the
graph-shape checks) and exits non-zero with a message naming the offending
node or label.

    python lint_svg.py board.svg
    python lint_svg.py board.d2 --layout tala
    python lint_svg.py build/board.svg --source board.d2

Exit codes: 0 clean, 1 findings, 2 could not lint.
"""

from __future__ import annotations

import argparse
import base64
import html
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

SKIP_SUBTREES = {"mask", "marker", "defs", "style", "clipPath", "pattern",
                 "linearGradient", "radialGradient", "filter", "symbol",
                 "title", "desc"}

# ---------------------------------------------------------------------------
# Text metrics
# ---------------------------------------------------------------------------
# Rendered ink width decides whether two labels collide, so the lint needs a
# font model. It must stay stdlib-only and deterministic, so it reproduces the
# font d2 embeds (Source Sans Pro) from glyph advances CALIBRATED against d2
# v0.9.0 SVG output at font-size 16, then scales linearly by font_size / 16.
#
# Each advance was measured as (w(6 glyphs) - w(2 glyphs)) / 4 from d2's own
# label boxes. Agreement with d2's rendered boxes (both at 16px):
#   "Hello"               38.50 vs 38     "first label here"      99.00 vs 99
#   "task deploy:ec2"    106.50 vs 106    "third label ..."      151.25 vs 151
#   "DEPLOY_ENV=staging" 146.25 vs 146    "queue depth ..."      218.50 vs 218
_ADV_16 = {
    "0": 7.75, "1": 7.75, "2": 7.75, "3": 7.75, "4": 7.75, "5": 7.75,
    "6": 7.75, "7": 7.75, "8": 7.75, "9": 7.75,
    "a": 8.5, "b": 8.5, "c": 7.0, "d": 8.5, "e": 7.75, "f": 4.5, "g": 8.5,
    "h": 8.25, "i": 3.75, "j": 4.0, "k": 7.75, "l": 4.0, "m": 12.75,
    "n": 8.5, "o": 8.25, "p": 8.5, "q": 8.5, "r": 5.5, "s": 6.5, "t": 5.25,
    "u": 8.5, "v": 7.0, "w": 11.25, "x": 7.0, "y": 7.0, "z": 6.5,
    "A": 8.0, "B": 9.25, "C": 8.75, "D": 9.5, "E": 8.0, "F": 7.5, "G": 9.5,
    "H": 10.0, "I": 4.0, "J": 7.25, "K": 9.0, "L": 7.25, "M": 11.25,
    "N": 10.0, "O": 10.0, "P": 8.75, "Q": 10.0, "R": 9.0, "S": 8.0, "T": 8.0,
    "U": 10.0, "V": 8.0, "W": 12.0, "X": 8.0, "Y": 7.25, "Z": 8.0,
    "!": 4.5, "#": 7.75, "$": 7.75, "%": 12.75, "&": 9.25, "'": 4.0,
    "(": 4.75, ")": 4.75, "*": 6.5, "+": 7.75, ",": 4.0, "-": 4.75,
    ".": 4.0, "/": 5.5, ":": 4.0, ";": 4.0, "<": 7.75, "=": 7.75, ">": 7.75,
    "?": 6.5, "@": 13.0, "[": 4.75, "]": 4.75, "^": 7.75, "_": 7.75,
    "`": 8.25, "|": 3.75, "~": 7.75, " ": 3.5,
}
_DEFAULT_ADV_16 = 8.0      # unknown glyph: average lowercase advance
_PAD_16 = 4.5              # d2 pads a label box ~2.25px per side at 16px
_ASCENT_16 = 16.0          # ink top sits this far above the baseline at 16px
_INK_H_16 = 21.0           # ink height of one line at 16px (measured 21, 37,
                           # 53, 69 for 1, 2, 3, 4 lines -> step 16)
_LINE_STEP_16 = 16.0

# Tolerances, named so this script and the docs cannot drift apart.
OVERLAP_TOL = 1.0          # px of ink overlap before a collision is reported
RECT_INSET = 2.0           # px of node-rect inset ignored (hairline rounding)
MIN_VISIBLE_RUN = 12.0     # px of connector that must stay visible by a label
ICON_MIN = 8.0             # a square rect in [ICON_MIN, ICON_MAX] is icon art
ICON_MAX = 34.0
THIN_DECOR = 4.0           # a rect thinner than this is a rule, not a shape
BACKGROUND_FRACTION = 0.7  # rect covering this share of the canvas is backdrop


def text_width(line: str, font: float) -> float:
    scale = font / 16.0
    adv = sum(_ADV_16.get(ch, _DEFAULT_ADV_16) for ch in line)
    return (adv + _PAD_16) * scale


@dataclass
class Box:
    x: float
    y: float
    w: float
    h: float

    @property
    def x2(self) -> float:
        return self.x + self.w

    @property
    def y2(self) -> float:
        return self.y + self.h

    def contains(self, px: float, py: float) -> bool:
        return self.x <= px <= self.x2 and self.y <= py <= self.y2

    def inset(self, d: float) -> "Box":
        return Box(self.x + d, self.y + d, self.w - 2 * d, self.h - 2 * d)


def ink_box(x: float, baseline: float, lines: "list[str]", font: float,
            anchor: str) -> Box:
    """Rendered ink box of a (possibly multi-line) label.

    THE RENDERED WIDTH IS THE WIDEST TSPAN, NOT THE CONCATENATED STRING. d2
    emits one `<tspan>` per source line, so a checker that sums every line's
    advances answers a question the renderer never asked - and it produced
    false passes before this rule was written down. Measured on d2 v0.9.0:
    "mmmmmmmmmmmm\\niii" renders 157px wide (the `m` line), while the
    concatenation "mmmmmmmmmmmmiii" renders 169px.
    """
    lines = lines or [""]
    scale = font / 16.0
    widest = max(text_width(ln, font) for ln in lines)
    height = _INK_H_16 * scale + (len(lines) - 1) * _LINE_STEP_16 * scale
    top = baseline - _ASCENT_16 * scale
    if anchor == "middle":
        left = x - widest / 2.0
    elif anchor == "end":
        left = x - widest
    else:
        left = x
    return Box(left, top, widest, height)


def overlap(a: Box, b: Box) -> "tuple[float, float]":
    return (min(a.x2, b.x2) - max(a.x, b.x), min(a.y2, b.y2) - max(a.y, b.y))


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------

@dataclass
class Node:
    ident: str
    box: Box
    container: bool = False


@dataclass
class Label:
    owner: str
    lines: "list[str]"
    font: float
    box: Box
    baseline: float

    @property
    def flat(self) -> str:
        return " / ".join(self.lines)


@dataclass
class Edge:
    ident: str
    src: str
    dst: str
    points: "list[tuple[float, float]]" = field(default_factory=list)


@dataclass
class Board:
    name: str
    width: float
    height: float
    nodes: "list[Node]" = field(default_factory=list)
    edges: "list[Edge]" = field(default_factory=list)
    labels: "list[Label]" = field(default_factory=list)
    floating: "list[Label]" = field(default_factory=list)


# ---------------------------------------------------------------------------
# SVG primitives
# ---------------------------------------------------------------------------

_TOKEN = re.compile(
    r"[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")


def _cubic(p0, p1, p2, p3, steps=10):
    out = []
    for k in range(1, steps + 1):
        t = k / steps
        mt = 1 - t
        out.append((
            mt ** 3 * p0[0] + 3 * mt * mt * t * p1[0]
            + 3 * mt * t * t * p2[0] + t ** 3 * p3[0],
            mt ** 3 * p0[1] + 3 * mt * mt * t * p1[1]
            + 3 * mt * t * t * p2[1] + t ** 3 * p3[1],
        ))
    return out


def sample_path(d: str) -> "list[tuple[float, float]]":
    """Flatten an SVG path (M/L/H/V/C/S/Q/T/A) into a polyline."""
    toks = _TOKEN.findall(d or "")
    idx = [0]

    def num() -> float:
        v = float(toks[idx[0]])
        idx[0] += 1
        return v

    def more() -> bool:
        return idx[0] < len(toks) and not toks[idx[0]].isalpha()

    pts: "list[tuple[float, float]]" = []
    cur = (0.0, 0.0)
    start = (0.0, 0.0)
    last_ctrl = None
    cmd = None
    while idx[0] < len(toks):
        tok = toks[idx[0]]
        if tok.isalpha():
            cmd = tok
            idx[0] += 1
            if cmd in "Zz":
                cur = start
                pts.append(cur)
                continue
            continue
        if cmd is None:
            break
        rel = cmd.islower()
        kind = cmd.upper()
        if kind == "M":
            x, y = num(), num()
            if rel:
                x += cur[0]; y += cur[1]
            cur = (x, y); start = cur; pts.append(cur); last_ctrl = None
            cmd = "l" if rel else "L"
        elif kind == "L":
            x, y = num(), num()
            if rel:
                x += cur[0]; y += cur[1]
            cur = (x, y); pts.append(cur); last_ctrl = None
        elif kind == "H":
            x = num()
            if rel:
                x += cur[0]
            cur = (x, cur[1]); pts.append(cur); last_ctrl = None
        elif kind == "V":
            y = num()
            if rel:
                y += cur[1]
            cur = (cur[0], y); pts.append(cur); last_ctrl = None
        elif kind == "C":
            x1, y1, x2, y2, x, y = (num(), num(), num(), num(), num(), num())
            if rel:
                x1 += cur[0]; y1 += cur[1]; x2 += cur[0]; y2 += cur[1]
                x += cur[0]; y += cur[1]
            pts.extend(_cubic(cur, (x1, y1), (x2, y2), (x, y)))
            last_ctrl = (x2, y2); cur = (x, y)
        elif kind == "S":
            x2, y2, x, y = num(), num(), num(), num()
            if rel:
                x2 += cur[0]; y2 += cur[1]; x += cur[0]; y += cur[1]
            c1 = ((2 * cur[0] - last_ctrl[0], 2 * cur[1] - last_ctrl[1])
                  if last_ctrl else cur)
            pts.extend(_cubic(cur, c1, (x2, y2), (x, y)))
            last_ctrl = (x2, y2); cur = (x, y)
        elif kind == "Q":
            x1, y1, x, y = num(), num(), num(), num()
            if rel:
                x1 += cur[0]; y1 += cur[1]; x += cur[0]; y += cur[1]
            c1 = (cur[0] + 2 / 3 * (x1 - cur[0]), cur[1] + 2 / 3 * (y1 - cur[1]))
            c2 = (x + 2 / 3 * (x1 - x), y + 2 / 3 * (y1 - y))
            pts.extend(_cubic(cur, c1, c2, (x, y)))
            last_ctrl = None; cur = (x, y)
        elif kind == "T":
            x, y = num(), num()
            if rel:
                x += cur[0]; y += cur[1]
            pts.append((x, y)); cur = (x, y); last_ctrl = None
        elif kind == "A":
            for _ in range(5):
                num()
            x, y = num(), num()
            if rel:
                x += cur[0]; y += cur[1]
            pts.append((x, y)); cur = (x, y); last_ctrl = None
        else:  # pragma: no cover - unknown command, skip its operands
            if not more():
                idx[0] += 1
            else:
                num()
    return pts


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _style_prop(style: str, name: str) -> "str | None":
    m = re.search(rf"(?:^|;)\s*{re.escape(name)}\s*:\s*([^;]+)", style or "")
    return m.group(1).strip() if m else None


def decode_class(cls: str) -> "str | None":
    """D2 encodes each node/edge key as the base64 of the D2 key.

    Edge groups are `(a -> b)[0]`, and the SVG carries it HTML-escaped, so the
    decoded text reads `(a -&gt; b)[0]`. Unescape before matching, or every
    edge silently classifies as a shape - the first version of this script did
    exactly that and cheerfully reported "0 edges".
    """
    token = (cls or "").strip()
    if not token or not re.fullmatch(r"[A-Za-z0-9+/]+={0,2}", token):
        return None
    padded = token + "=" * (-len(token) % 4)
    try:
        raw = base64.b64decode(padded)
        text = raw.decode("utf-8")
    except Exception:
        return None
    # Round-trip guard: plain class names such as 'shape' and 'd2-svg' are also
    # valid base64 alphabets, and re-encoding is what tells them apart.
    if base64.b64encode(raw).decode().rstrip("=") != token.rstrip("="):
        return None
    if not text or not all(ch.isprintable() for ch in text):
        return None
    return html.unescape(text)


def canvas_size(root) -> "tuple[float, float]":
    """Canvas size of a board scope.

    d2 wraps a board in a nested `<svg width= height=>`; a `--animate-interval`
    board wrapper carries the same attributes on its `<g>` instead.
    """
    def from_attrs(el) -> "tuple[float, float] | None":
        try:
            if el.get("width") and el.get("height"):
                return float(el.get("width")), float(el.get("height"))
        except ValueError:
            pass
        vb = el.get("viewBox")
        if vb:
            parts = re.split(r"[\s,]+", vb.strip())
            if len(parts) == 4:
                return float(parts[2]), float(parts[3])
        return None

    own = from_attrs(root)
    if own:
        return own
    for el in root.iter():
        if el is root or _local(el.tag) != "svg":
            continue
        found = from_attrs(el)
        if found:
            return found
    return 0.0, 0.0


def _num(el, name: str, default: float = 0.0) -> float:
    try:
        return float(el.get(name, default) or default)
    except (TypeError, ValueError):
        return default


def _texts(el, ox: float, oy: float, out):
    """Absolute (x, baseline, lines, font-size, anchor) for every <text>."""
    for child in el:
        tag = _local(child.tag)
        if tag in SKIP_SUBTREES:
            continue
        if tag == "svg":
            _texts(child, ox + _num(child, "x"), oy + _num(child, "y"), out)
            continue
        if tag == "text":
            x = ox + _num(child, "x")
            y = oy + _num(child, "y")
            style = child.get("style", "") or ""
            raw_font = (child.get("font-size")
                        or _style_prop(style, "font-size") or "16")
            digits = re.sub(r"[^0-9.]", "", raw_font)
            font = float(digits) if digits else 16.0
            anchor = _style_prop(style, "text-anchor") or "start"
            tspans = [ts for ts in child.iter() if _local(ts.tag) == "tspan"]
            lines = (["".join(ts.itertext()) for ts in tspans] if tspans
                     else ["".join(child.itertext())])
            out.append((x, y, lines, font, anchor))
            continue
        _texts(child, ox, oy, out)


def _rects(el, out: "list[Box]"):
    for child in el:
        tag = _local(child.tag)
        if tag in SKIP_SUBTREES:
            continue
        if tag == "rect":
            w = _num(child, "width")
            h = _num(child, "height")
            if w > 0 and h > 0:
                out.append(Box(_num(child, "x"), _num(child, "y"), w, h))
        _rects(child, out)


EDGE_ID_RE = re.compile(
    r"^(?:[^()]*\.)?\((?P<src>.+?)\s*(?:->|<-|<->|--)\s*(?P<dst>.+?)\)\[\d+\]$")
SHAPE_GROUP = "shape"


def parse_svg(path: Path) -> Board:
    """The first board of an SVG (single-board sources have exactly one)."""
    boards = parse_svg_boards(path, quiet=True)
    if not boards:
        raise SystemExit(f"error: no d2 board found in {path}")
    return boards[0]


ANIMATION_GROUP = re.compile(r"animation\s*:\s*d2Transition")


def parse_svg_boards(path: Path, quiet: bool = True) -> "list[Board]":
    """Build one Board per rendered board in the SVG.

    d2's shape group is the identity: `<g class="<b64 key>"><g class="shape">`
    holds the node rect (plus icon art), and `<g class="<b64 edge key>">` holds
    the connection path and its label. Grouping on `class="shape"` rather than
    "any base64 class" is what keeps an icon's own `<rect>` and a `|md` block's
    sub-`<svg>` from being mistaken for nodes.

    A `--animate-interval` export stacks EVERY board into one SVG, each wrapped
    in `<g style="animation: d2Transition-...">` with its own backdrop and
    coordinate space. Parsing that as a single board reports every cross-board
    overlap as a defect (boards occupy the same coordinates by construction),
    so each animation wrapper becomes its own board.
    """
    import xml.etree.ElementTree as ET

    raw = path.read_text(encoding="utf-8", errors="replace")
    raw = re.sub(r"<\?xml[^>]*\?>", "", raw)
    raw = re.sub(r"<style\b.*?</style>", "", raw, flags=re.S)
    root = ET.fromstring(raw)

    panels = [el for el in root.iter()
              if _local(el.tag) == "g"
              and ANIMATION_GROUP.search(el.get("style", "") or "")]
    boards: "list[Board]" = []
    for index, panel in enumerate(panels or [None]):
        scope = panel if panel is not None else root
        name = path.stem if panel is None else f"{path.stem}#{index + 1}"
        boards.append(_build_board(scope, name, root))
    return boards


def _build_board(scope, name: str, root) -> Board:
    width, height = canvas_size(scope)
    if not (width and height):
        width, height = canvas_size(root)
    board = Board(name, width, height)
    canvas_area = width * height

    backdrop: "Box | None" = None
    for el in scope.iter():
        if _local(el.tag) != "rect":
            continue
        w, h = _num(el, "width"), _num(el, "height")
        if canvas_area and w * h >= BACKGROUND_FRACTION * canvas_area:
            backdrop = Box(_num(el, "x"), _num(el, "y"), w, h)
            break

    def is_icon(b: Box) -> bool:
        return (ICON_MIN <= b.w <= ICON_MAX and ICON_MIN <= b.h <= ICON_MAX)

    def is_decor(b: Box) -> bool:
        # A `|md` heading's underline is a 309x1 rect inside the shape group;
        # left in, it becomes a 1px-tall "node" that every label overlaps.
        return b.w < THIN_DECOR or b.h < THIN_DECOR

    def emit(ident: str, group) -> None:
        texts: "list[tuple[float,float,list[str],float,str]]" = []
        rects: "list[Box]" = []
        _texts(group, 0.0, 0.0, texts)
        _rects(group, rects)
        m = EDGE_ID_RE.match(ident)
        if m:
            edge = Edge(ident, m.group("src").strip(), m.group("dst").strip())
            for el in group.iter():
                if (_local(el.tag) == "path"
                        and "connection" in (el.get("class") or "")):
                    edge.points = sample_path(el.get("d", ""))
                    break
            board.edges.append(edge)
            for x, y, lines, font, anchor in texts[:1]:
                board.labels.append(
                    Label(ident, lines, font,
                          ink_box(x, y, lines, font, anchor), y))
            return
        shapes = [b for b in rects
                  if b is not backdrop and not is_icon(b) and not is_decor(b)]
        if not shapes:
            # Free-floating label (`shape: text`, or a `|md` block). A
            # multi-block `|md` node emits ONE <text> PER MARKDOWN BLOCK, so
            # each block is its own ink box - that is what measures the
            # heading-to-paragraph gap after the header fix.
            for x, y, lines, font, anchor in texts:
                board.floating.append(
                    Label(ident, lines, font,
                          ink_box(x, y, lines, font, anchor), y))
            return
        board.nodes.append(Node(ident, max(shapes, key=lambda b: b.w * b.h)))

    def walk(el) -> None:
        for child in el:
            tag = _local(child.tag)
            if tag in SKIP_SUBTREES or tag != "g":
                walk(child)
                continue
            ident = decode_class(child.get("class", ""))
            if ident is None:
                walk(child)
                continue
            is_shape = any(_local(g.tag) == "g"
                           and g.get("class") == SHAPE_GROUP for g in child)
            if is_shape or EDGE_ID_RE.match(ident):
                emit(ident, child)
                continue
            walk(child)

    walk(scope)

    idents = [n.ident for n in board.nodes]
    for node in board.nodes:
        node.container = any(other.startswith(node.ident + ".")
                             for other in idents)
    return board


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

@dataclass
class Finding:
    check: str
    owner: str
    message: str
    fix: str


def check_header_overlap(board: Board) -> "list[Finding]":
    """DEFECT 1: two `near: top-center` floating nodes share an anchor.

    Measured on a real render: title at (1016, -28) and subtitle at (1016, -24)
    - 4px apart, so the subtitle printed across the title. Nothing in the
    source looks wrong: both are well-formed `shape: text` nodes.
    """
    out = []
    items = board.floating
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            a, b = items[i], items[j]
            ox, oy = overlap(a.box, b.box)
            if ox > OVERLAP_TOL and oy > OVERLAP_TOL:
                out.append(Finding(
                    "header-overlap", f"{a.owner} + {b.owner}",
                    f"'{a.flat}' ({a.font:g}px) and '{b.flat}' ({b.font:g}px) "
                    f"print on top of each other - baselines "
                    f"{abs(a.baseline - b.baseline):.1f}px apart, ink boxes "
                    f"overlap {ox:.1f}px x {oy:.1f}px",
                    "use ONE `|md` node for the heading + paragraph: a `#` "
                    "heading and its paragraph land 32-62px apart",
                ))
    return out


def check_label_on_node(board: Board) -> "list[Finding]":
    """DEFECT 2: an edge label straddles a gutter narrower than itself.

    Measured on a real `grid-*` board with `grid-gap: 100`: a 3-line label
    ('task deploy:ec2\\nDEPLOY_ENV=staging', ~150px half-width) put 6 of 13
    labels 20-258px INSIDE node rectangles, because a label straddling a gutter
    needs half its width on each side.
    """
    out = []
    solids = [n for n in board.nodes if not n.container]
    for label in board.labels:
        for node in solids:
            box = node.box.inset(RECT_INSET)
            if box.w <= 0 or box.h <= 0:
                continue
            ox, oy = overlap(label.box, box)
            if ox > RECT_INSET and oy > RECT_INSET:
                out.append(Finding(
                    "label-on-node", label.owner,
                    f"label '{label.flat}' "
                    f"({label.box.w:.0f}x{label.box.h:.0f}px) sits "
                    f"{min(ox, oy):.1f}px inside node rect {node.ident!r} "
                    f"({node.box.w:.0f}x{node.box.h:.0f} at "
                    f"{node.box.x:.0f},{node.box.y:.0f})",
                    "line-break the label, widen `grid-gap`, or shrink "
                    "`label-container`",
                ))
    return out


def _resample(points, step: float = 1.0):
    out = []
    for (x1, y1), (x2, y2) in zip(points, points[1:]):
        dist = ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
        n = max(1, int(dist / step))
        for k in range(n):
            t = k / n
            out.append((x1 + (x2 - x1) * t, y1 + (y2 - y1) * t))
    if points:
        out.append(points[-1])
    return out


def check_arrow_hidden(board: Board) -> "list[Finding]":
    """DEFECT 3: label covers the whole connector run.

    Zero rect overlap is not enough. When a label eats the gutter, the visible
    connector shrinks to nothing and the arrow reads as a stray label between
    two boxes.
    """
    out = []
    labels = {l.owner: l for l in board.labels}
    for edge in board.edges:
        label = labels.get(edge.ident)
        if label is None or len(edge.points) < 2:
            continue
        samples = _resample(edge.points)
        if len(samples) < 2:
            continue
        total = hidden = 0.0
        for (x1, y1), (x2, y2) in zip(samples, samples[1:]):
            seg = ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
            total += seg
            if label.box.contains((x1 + x2) / 2, (y1 + y2) / 2):
                hidden += seg
        visible = total - hidden
        if total > 0 and visible < MIN_VISIBLE_RUN:
            out.append(Finding(
                "arrow-hidden", edge.ident,
                f"label '{label.flat}' "
                f"({label.box.w:.0f}x{label.box.h:.0f}px) leaves only "
                f"{visible:.1f}px of the {total:.1f}px connector visible "
                f"(minimum {MIN_VISIBLE_RUN:.0f}px) for "
                f"{edge.src!r} -> {edge.dst!r}",
                "shorten/line-break the label, or widen the gutter so a "
                "connector run stays visible on both sides of it",
            ))
    return out


def check_edge_crosses_node(board: Board) -> "list[Finding]":
    """DEFECT 4a: a connector passes through a node it does not touch."""
    out = []
    solids = [n for n in board.nodes if not n.container]
    for edge in board.edges:
        if len(edge.points) < 2:
            continue
        worst = 0.0
        hit: "Node | None" = None
        for px, py in _resample(edge.points, 2.0):
            for node in solids:
                if node.ident in (edge.src, edge.dst):
                    continue
                box = node.box.inset(RECT_INSET)
                if box.w <= 0 or box.h <= 0:
                    continue
                if box.contains(px, py):
                    depth = min(px - box.x, box.x2 - px,
                                py - box.y, box.y2 - py)
                    if depth > worst:
                        worst, hit = depth, node
                    break
        if hit is not None:
            out.append(Finding(
                "edge-crosses-node", edge.ident,
                f"connector {edge.src!r} -> {edge.dst!r} passes {worst:.1f}px "
                f"through node rect {hit.ident!r} "
                f"({hit.box.w:.0f}x{hit.box.h:.0f} at "
                f"{hit.box.x:.0f},{hit.box.y:.0f})",
                "inside a `grid-*` board this is a row-wrap edge: declare "
                "nodes in boustrophedon (snake) order so every hop is a grid "
                "neighbour",
            ))
    return out


# ---------------------------------------------------------------------------
# Source (.d2) checks: graph cycles and grid declaration order
# ---------------------------------------------------------------------------

IDENT = r"[A-Za-z0-9_][A-Za-z0-9_.\-]*"
EDGE_RE = re.compile(rf"(?P<chain>{IDENT}(?:\s*(?:->|<-|<->|--)\s*{IDENT})+)")
GRID_ROWS_RE = re.compile(r"^\s*grid-rows\s*:\s*(\d+)")
GRID_COLS_RE = re.compile(r"^\s*grid-columns\s*:\s*(\d+)")
DECL_RE = re.compile(rf"^\s*(?P<id>{IDENT})\s*:")

# Block-level keys that read like a declaration but are attributes or
# sub-scopes, never grid children. Without this list `grid-gap` and
# `label-container` occupy a cell and shift every node's row-major index.
RESERVED_KEYS = {
    "direction", "shape", "icon", "near", "label", "width", "height", "link",
    "tooltip", "class", "classes", "vars", "layers", "scenarios", "steps",
    "style", "grid-rows", "grid-columns", "grid-gap", "label-container",
    "label-position", "top", "left", "constraint", "source-arrowhead",
    "target-arrowhead", "d2-config",
}
RESERVED_PREFIXES = ("style.", "grid-", "label-", "source-arrowhead.",
                     "target-arrowhead.", "vars.", "classes.")


def _is_reserved(name: str) -> bool:
    return name in RESERVED_KEYS or name.startswith(RESERVED_PREFIXES)


@dataclass
class Block:
    path: str
    rows: "int | None" = None
    cols: "int | None" = None
    children: "list[str]" = field(default_factory=list)


def _strip_comment(line: str) -> str:
    out = []
    in_str = False
    for ch in line:
        if ch == '"':
            in_str = not in_str
        if ch == "#" and not in_str:
            break
        out.append(ch)
    return "".join(out)


def parse_source(path: Path) -> "tuple[dict[str, Block], list[tuple[str, str]]]":
    """Minimal indentation/brace-aware scan of a `.d2` file.

    Only two facts are needed: the edge list (for cycles) and each block's
    child declaration order plus `grid-rows`/`grid-columns` (for row-major
    placement). `d2 fmt` output - which the skill requires - is the common
    input, so values are read from the raw lines before brace handling.
    """
    blocks: "dict[str, Block]" = {"": Block("")}
    edges: "list[tuple[str, str]]" = []
    stack = [""]
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = _strip_comment(raw)
        stripped = line.strip()
        if not stripped:
            continue
        if stripped in ("}", "};"):
            if len(stack) > 1:
                stack.pop()
            continue
        head = stripped[:-1].strip() if stripped.endswith("{") else stripped
        cur = blocks[stack[-1]]
        if stripped.endswith("{"):
            m = GRID_ROWS_RE.match(head)
            if m:
                cur.rows = int(m.group(1))
                continue
            m = GRID_COLS_RE.match(head)
            if m:
                cur.cols = int(m.group(1))
                continue
            dm = DECL_RE.match(head)
            name = dm.group("id") if dm else ""
            if name and not _is_reserved(name):
                cur.children.append(name)
            key = f"{stack[-1]}.{name}" if stack[-1] else name
            blocks.setdefault(key, Block(key))
            stack.append(key)
            continue
        m = GRID_ROWS_RE.match(stripped)
        if m:
            cur.rows = int(m.group(1))
            continue
        m = GRID_COLS_RE.match(stripped)
        if m:
            cur.cols = int(m.group(1))
            continue
        em = EDGE_RE.search(stripped)
        if em and ":" not in em.group("chain"):
            parts = re.split(r"\s*(->|<-|<->|--)\s*", em.group("chain"))
            nodes = [p for p in parts if p and p not in ("->", "<-", "<->", "--")]
            ops = [p for p in parts if p in ("->", "<-", "<->", "--")]
            for k, op in enumerate(ops):
                a, b = nodes[k], nodes[k + 1]
                edges.append((b, a) if op == "<-" else (a, b))
            continue
        dm = DECL_RE.match(stripped)
        if dm and not _is_reserved(dm.group("id")):
            cur.children.append(dm.group("id"))
    return blocks, edges


def _short(ident: str) -> str:
    return ident.rsplit(".", 1)[-1]


def check_cyclic_edge(edges: "list[tuple[str, str]]") -> "list[Finding]":
    """DEFECT 4b: a backward edge re-ranks the whole board.

    Measured on a real 14-node release spine: adding `RELEASED -> ROLLED_BACK`
    plus `ROLLED_BACK -> PROD_VERIFIED` made `tala` lay the spine out
    diagonally (y non-monotonic, x spread 622px). The source is the only place
    the cycle is visible - the rendered SVG is just a graph that happens to be
    diagonal, and the compile exits 0 either way.
    """
    graph: "dict[str, set[str]]" = {}
    for a, b in edges:
        graph.setdefault(_short(a), set()).add(_short(b))
        graph.setdefault(_short(b), set())

    index: "dict[str, int]" = {}
    low: "dict[str, int]" = {}
    on_stack: "set[str]" = set()
    stack: "list[str]" = []
    sccs: "list[list[str]]" = []
    counter = [0]

    def strongconnect(v: str) -> None:
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        on_stack.add(v)
        for w in sorted(graph.get(v, ())):
            if w not in index:
                strongconnect(w)
                low[v] = min(low[v], low[w])
            elif w in on_stack:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = stack.pop()
                on_stack.discard(w)
                comp.append(w)
                if w == v:
                    break
            if len(comp) > 1:
                sccs.append(sorted(comp))

    sys.setrecursionlimit(max(20000, sys.getrecursionlimit()))
    for v in sorted(graph):
        if v not in index:
            strongconnect(v)

    def cycle_path(members: "set[str]") -> "list[str]":
        """One concrete cycle inside the component, as a node path."""
        for start in sorted(members):
            path: "list[str]" = []
            seen: "set[str]" = set()

            def dfs(v: str) -> "list[str] | None":
                path.append(v)
                seen.add(v)
                for w in sorted(graph.get(v, ())):
                    if w not in members:
                        continue
                    if w == start:
                        return path + [start]
                    if w not in seen:
                        found = dfs(w)
                        if found:
                            return found
                path.pop()
                return None

            found = dfs(start)
            if found:
                return found
        return sorted(members)

    out = []
    for comp in sccs:
        members = set(comp)
        path = cycle_path(members)
        loop = " -> ".join(path)
        extra = len(members) - (len(path) - 1)
        note = f" (+{extra} more node(s) in the same component)" if extra else ""
        out.append(Finding(
            "cyclic-edge", f"{len(comp)}-node cycle",
            f"cycle {loop}{note}; a backward edge makes the layout engine "
            f"re-rank the board, which lays a linear spine out diagonally",
            "route the loop explicitly (its own board/layer), or split it into "
            "a forward spine plus a labelled return edge that no spine node "
            "depends on",
        ))
    return out


def check_grid_wrap(blocks: "dict[str, Block]",
                    edges: "list[tuple[str, str]]") -> "list[Finding]":
    """DEFECT 4c: grid boards fill row-major in declaration order.

    `grid-rows`/`grid-columns` place nodes ROW-MAJOR in DECLARATION order, so a
    straight 1..14 listing makes the wrap hop (last cell of row N -> first cell
    of row N+1) a full-row diagonal that crosses every node in between.
    Measured on a real board: 13 hops, 9 diagonal, 12 cell collisions before
    the fix; 0 diagonal, 0 collisions after boustrophedon (snake) order.
    """
    out = []
    for key, block in sorted(blocks.items()):
        if not block.rows or not block.cols or len(block.children) < 2:
            continue
        cell: "dict[str, tuple[int, int]]" = {}
        for i, child in enumerate(block.children):
            cell.setdefault(_short(child), (i // block.cols, i % block.cols))
        bad = 0
        example = ""
        for a, b in edges:
            sa, sb = _short(a), _short(b)
            if sa not in cell or sb not in cell:
                continue
            (ra, ca), (rb, cb) = cell[sa], cell[sb]
            jump = abs(ra - rb) + abs(ca - cb)
            if jump > 1:
                bad += 1
                if not example:
                    example = (f"{sa!r} at row {ra} col {ca} -> {sb!r} at "
                               f"row {rb} col {cb}")
        if bad:
            out.append(Finding(
                "grid-wrap", f"'{key or '<root>'}' ({block.rows}x{block.cols})",
                f"{bad} edge(s) are not grid neighbours: {example}"
                f" (row-major, declaration order)",
                "declare the nodes in boustrophedon (snake) order so every "
                "hop is a grid neighbour, or drop the grid and let the layout "
                "engine place them",
            ))
    return out


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def find_d2(explicit: "str | None") -> "str | None":
    if explicit:
        return explicit
    for name in ("d2", "d2.exe"):
        found = shutil.which(name)
        if found:
            return found
    return None


def render(d2: str, src: Path, workdir: Path, layout, pad, theme) -> "list[Path]":
    """Render every board to SVG.

    Multi-board sources (layers/scenarios/steps) export a DIRECTORY: passing
    `out/board.svg` produces `out/board/index.svg` plus one file per board, so
    the directory check must strip the `.svg` suffix d2 discards.
    """
    out = workdir / "board.svg"
    args = [d2]
    if pad is not None:
        args += ["--pad", str(pad)]
    if layout:
        args += ["--layout", layout]
    if theme is not None:
        args += ["--theme", str(theme)]
    args += [str(src), str(out)]
    proc = subprocess.run(args, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout or "")
        sys.stderr.write(proc.stderr or "")
        sys.exit(f"error: d2 could not render {src}")
    if out.is_file():
        return [out]
    for candidate in (out.with_suffix(""), out):
        if candidate.is_dir():
            found = sorted(candidate.rglob("*.svg"))
            if found:
                return found
    sys.exit(f"error: d2 produced no SVG for {src}")


def lint_board(svg: Path, source: "Path | None", quiet: bool) -> "list[Finding]":
    boards = parse_svg_boards(svg)
    findings: "list[Finding]" = []
    source_findings: "list[Finding]" = []
    if source is not None:
        blocks, edges = parse_source(source)
        source_findings = (check_cyclic_edge(edges)
                           + check_grid_wrap(blocks, edges))
    for board in boards:
        board_findings = (check_header_overlap(board)
                          + check_label_on_node(board)
                          + check_arrow_hidden(board)
                          + check_edge_crosses_node(board))
        if len(boards) > 1:
            for f in board_findings:
                f.owner = f"{board.name}: {f.owner}"
        findings += board_findings
        if not quiet:
            print(f"  {board.name}: {len(board.nodes)} nodes, "
                  f"{len(board.edges)} edges, {len(board.labels)} edge labels, "
                  f"{len(board.floating)} floating labels")
    return findings + source_findings


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Post-render geometry lint for D2 diagrams: catches "
                    "visual defects that `d2 validate` and a full compile "
                    "both miss.")
    ap.add_argument("input", help=".svg to lint, or .d2 to render then lint")
    ap.add_argument("--d2", help="path to the d2 binary (default: PATH)")
    ap.add_argument("--layout", choices=["dagre", "elk", "tala"],
                    help="layout engine when rendering a .d2 (default: source)")
    ap.add_argument("--pad", type=int,
                    help="padding when rendering a .d2 (d2 default is 100)")
    ap.add_argument("--theme", type=int, help="theme id when rendering")
    ap.add_argument("--source", help=".d2 file for the graph checks when "
                                     "linting a bare .svg")
    ap.add_argument("--svg-only", action="store_true",
                    help="skip the .d2 graph checks (cyclic-edge, grid-wrap)")
    ap.add_argument("--max-findings", type=int, default=50)
    ap.add_argument("--quiet", action="store_true", help="no per-board banner")
    args = ap.parse_args()

    target = Path(args.input)
    if not target.is_file():
        sys.stderr.write(f"error: input not found: {target}\n")
        return 2
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    with tempfile.TemporaryDirectory(prefix="d2lint-") as tmp:
        source: "Path | None" = None
        if target.suffix.lower() == ".d2":
            d2 = find_d2(args.d2)
            if d2 is None:
                sys.exit("error: d2 CLI not found on PATH (pass --d2), or lint "
                         "an already-rendered .svg")
            svgs = render(d2, target, Path(tmp), args.layout, args.pad,
                          args.theme)
            source = target
        else:
            svgs = [target]
            candidate = (Path(args.source) if args.source
                         else target.with_suffix(".d2"))
            source = candidate if candidate.is_file() else None
        if args.svg_only:
            source = None
        if source is None and not args.quiet:
            print("note: no .d2 source found - geometry checks only "
                  "(pass --source for cyclic-edge/grid-wrap)")

        if not args.quiet:
            print(f"d2-lint  {target.name}")
        findings: "list[Finding]" = []
        for svg in svgs:
            board_findings = lint_board(svg, source, args.quiet)
            if len(svgs) > 1:
                tag = svg.relative_to(Path(tmp)).as_posix()
                for f in board_findings:
                    f.owner = f"{tag}: {f.owner}"
            findings += board_findings

    if not findings:
        print(f"PASS  {target.name}: no visual defects "
              f"(header-overlap, label-on-node, arrow-hidden, "
              f"edge-crosses-node, cyclic-edge, grid-wrap)")
        return 0

    counts: "dict[str, int]" = {}
    for f in findings[:args.max_findings]:
        counts[f.check] = counts.get(f.check, 0) + 1
        print(f"FAIL {f.check:<17} {f.owner}")
        print(f"     {f.message}")
        print(f"     fix: {f.fix}")
    if len(findings) > args.max_findings:
        print(f"... {len(findings) - args.max_findings} more finding(s) "
              f"suppressed (--max-findings)")
    summary = ", ".join(f"{n} {k}" for k, n in sorted(counts.items()))
    print(f"\n{len(findings)} finding(s) in {target.name}: {summary}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
