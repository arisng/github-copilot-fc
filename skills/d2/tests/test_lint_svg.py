#!/usr/bin/env python3
"""Unit tests for lint_svg.py (post-render D2 geometry lint).

Run:  python3 -m unittest discover -s skills/d2/tests -v

The fixtures are inline SVG fragments built to reproduce the four defects
found by eye on a real diagram, because each one compiles clean and exits 0.
No d2 CLI is required: the geometry checks read an SVG, and the graph checks
read a `.d2` parsed as text.
"""
import base64
import importlib.util
import io
import sys
import tempfile
import unittest
from pathlib import Path

_LINT = Path(__file__).resolve().parents[1] / "scripts" / "lint_svg.py"
_spec = importlib.util.spec_from_file_location("d2_lint_svg", _LINT)
lint = importlib.util.module_from_spec(_spec)
sys.modules["d2_lint_svg"] = lint
_spec.loader.exec_module(lint)


def b64(key: str) -> str:
    return base64.b64encode(key.encode()).decode()


def svg_doc(body: str, width: int = 600, height: int = 400) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">'
        f'<svg class="d2-x d2-svg" width="{width}" height="{height}">'
        f'<rect x="-20" y="-20" width="{width}" height="{height}" fill="#FFFFFF" />'
        f"{body}</svg></svg>"
    )


def node(key: str, x, y, w, h, label="", font=16) -> str:
    text = ""
    if label:
        text = (f'<text x="{x + w / 2}" y="{y + h / 2 + 5}" '
                f'style="text-anchor:middle;font-size:{font}px">{label}</text>')
    return (f'<g class="{b64(key)}"><g class="shape">'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" />'
            f'</g>{text}</g>')


def float_text(key: str, x, y, label, font=16) -> str:
    return (f'<g class="{b64(key)}"><g class="shape"></g>'
            f'<text x="{x}" y="{y}" '
            f'style="text-anchor:middle;font-size:{font}px">{label}</text></g>')


def edge(key: str, d, label=None, lx=0, ly=0, font=16,
         tspans=None) -> str:
    body = (f'<g class="{b64(key)}">'
            f'<path d="{d}" fill="none" class="connection stroke-B1" />')
    if label is not None or tspans:
        inner = (tspans if tspans is not None else label)
        body += (f'<text x="{lx}" y="{ly}" '
                 f'style="text-anchor:middle;font-size:{font}px">{inner}</text>')
    return body + "</g>"


class BoardFixture(unittest.TestCase):
    def write(self, content: str, suffix: str) -> Path:
        tmp = tempfile.NamedTemporaryFile("w", suffix=suffix, delete=False,
                                          encoding="utf-8")
        tmp.write(content)
        tmp.close()
        self.addCleanup(Path(tmp.name).unlink)
        return Path(tmp.name)

    def board(self, body: str, width=600, height=400):
        return lint.parse_svg(self.write(svg_doc(body, width, height), ".svg"))


class TextMetricsTest(unittest.TestCase):
    def test_width_matches_d2_rendered_boxes(self):
        # Measured from d2 v0.9.0 SVG output; see the calibration table.
        cases = {"Hello": 38.0, "task deploy:ec2": 106.0,
                 "DEPLOY_ENV=staging": 146.0, "first label here": 99.0}
        for text, measured in cases.items():
            self.assertAlmostEqual(lint.text_width(text, 16), measured,
                                   delta=1.5, msg=text)

    def test_widest_tspan_wins_over_concatenation(self):
        """The lesson that produced false passes: render width is the WIDEST
        tspan, not the concatenation of all of them."""
        wide = lint.ink_box(100, 100, ["mmmmmmmmmmmm", "iii"], 16, "middle")
        concat = lint.ink_box(100, 100, ["mmmmmmmmmmmmiii"], 16, "middle")
        self.assertLess(wide.w, concat.w)
        # d2 renders 157px for the two-line label and 169px for the joined one.
        self.assertAlmostEqual(wide.w, 157, delta=3)

    def test_multiline_height(self):
        # Measured: 21, 37, 53, 69 px for 1..4 lines at 16px.
        heights = [lint.ink_box(0, 100, ["x"] * n, 16, "middle").h
                   for n in (1, 2, 3, 4)]
        self.assertEqual(heights, [21.0, 37.0, 53.0, 69.0])


class HeaderOverlapTest(BoardFixture):
    def test_two_near_top_center_nodes_fail(self):
        # Measured on a real render: baselines 4px apart at the same x anchor.
        body = (float_text("title", 300, 40, "Deployment Board", 32)
                + float_text("subtitle", 300, 44,
                             "Environments, release train, and rollback path", 18))
        findings = lint.check_header_overlap(self.board(body))
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].check, "header-overlap")
        self.assertIn("title", findings[0].owner)
        self.assertIn("subtitle", findings[0].owner)

    def test_stacked_header_blocks_pass(self):
        # The fix: one `|md` node emits a heading <text> and a paragraph <text>
        # whose baselines are 53.6px apart (ink gap 27.6px).
        body = (float_text("header", 300, 40, "Deployment Board", 32)
                + float_text("header", 300, 93.6,
                             "Environments, release train, and rollback path", 16))
        self.assertEqual(lint.check_header_overlap(self.board(body)), [])


class LabelOnNodeTest(BoardFixture):
    def test_label_straddling_a_narrow_gutter_fails(self):
        # grid-gap 100: a 3-line label is ~146px wide, so half of it (73px)
        # cannot fit on either side of the 100px gutter.
        body = (node("board.n1", 100, 100, 94, 66, "Node 1")
                + node("board.n2", 294, 100, 93, 66, "Node 2")
                + edge("board.(n1 -> n2)[0]", "M 195 133 L 290 133",
                       tspans='<tspan x="244" dy="0">task deploy:ec2</tspan>'
                              '<tspan x="244" dy="18.5">DEPLOY_ENV=staging</tspan>',
                       lx=244, ly=131))
        findings = lint.check_label_on_node(self.board(body))
        self.assertGreaterEqual(len(findings), 1)
        self.assertEqual(findings[0].check, "label-on-node")
        self.assertIn("task deploy:ec2", findings[0].message)

    def test_label_clear_of_both_nodes_passes(self):
        body = (node("board.n1", 60, 100, 94, 66, "Node 1")
                + node("board.n2", 434, 100, 94, 66, "Node 2")
                + edge("board.(n1 -> n2)[0]", "M 155 133 L 433 133",
                       "go", lx=294, ly=128))
        self.assertEqual(lint.check_label_on_node(self.board(body)), [])

    def test_container_rect_is_not_a_solid(self):
        # A container background covers its children; a label inside it is fine.
        body = (node("board", 0, 0, 600, 300)
                + node("board.n1", 100, 100, 94, 66, "Node 1")
                + node("board.n2", 294, 100, 93, 66, "Node 2")
                + edge("board.(n1 -> n2)[0]", "M 195 133 L 290 133",
                       "go", lx=244, ly=128))
        board = self.board(body)
        self.assertTrue([n for n in board.nodes if n.ident == "board"][0].container)
        self.assertEqual(lint.check_label_on_node(board), [])


class ArrowHiddenTest(BoardFixture):
    def test_label_covering_the_connector_fails(self):
        body = (node("board.a", 30, 46, 87, 66, "Alpha")
                + node("board.b", 147, 46, 77, 66, "Beta")
                + edge("board.(a -> b)[0]", "M 110 79 L 145 79",
                       "queue depth threshold exceeded", lx=127, ly=74))
        findings = lint.check_arrow_hidden(self.board(body))
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].check, "arrow-hidden")

    def test_short_label_leaves_a_visible_run(self):
        body = (node("board.a", 30, 46, 87, 66, "Alpha")
                + node("board.b", 400, 46, 77, 66, "Beta")
                + edge("board.(a -> b)[0]", "M 118 79 L 399 79",
                       "go", lx=258, ly=74))
        self.assertEqual(lint.check_arrow_hidden(self.board(body)), [])


class EdgeCrossesNodeTest(BoardFixture):
    def test_row_wrap_edge_through_a_third_node_fails(self):
        # The measured case: a 2x7 straight listing put the wrap hop on a
        # diagonal that crossed node 9.
        body = (node("board.n7", 1010, 60, 102, 66, "Node 7")
                + node("board.n8", 60, 186, 93, 66, "Node 8")
                + node("board.n9", 213, 186, 93, 66, "Node 9")
                + edge("board.(n7 -> n8)[0]",
                       "M 1008 100 L 156 212"))
        findings = lint.check_edge_crosses_node(self.board(body))
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].check, "edge-crosses-node")
        self.assertIn("n9", findings[0].message)

    def test_orthogonal_hop_passes(self):
        body = (node("board.n1", 60, 60, 93, 66, "Node 1")
                + node("board.n2", 213, 60, 93, 66, "Node 2")
                + edge("board.(n1 -> n2)[0]", "M 154 93 L 209 93"))
        self.assertEqual(lint.check_edge_crosses_node(self.board(body)), [])


class CyclicEdgeTest(unittest.TestCase):
    def test_backward_edge_is_reported_with_a_cycle_path(self):
        edges = [("n0", "n1"), ("n1", "n2"), ("n2", "n3"),
                 ("n3", "n1"), ("n3", "n4")]
        findings = lint.check_cyclic_edge(edges)
        self.assertEqual(len(findings), 1)
        self.assertIn("n1", findings[0].message)
        self.assertIn("->", findings[0].message)

    def test_forward_spine_passes(self):
        edges = [(f"n{i}", f"n{i + 1}") for i in range(13)]
        self.assertEqual(lint.check_cyclic_edge(edges), [])


class GridWrapTest(unittest.TestCase):
    def blocks(self, rows, cols, children):
        block = lint.Block("board", rows=rows, cols=cols, children=children)
        return {"board": block}

    def test_straight_listing_wraps_diagonally(self):
        # 2 rows x 7 cols, declared 1..14: n7 (row 0, col 6) -> n8 (row 1,
        # col 0) is a seven-cell sweep, which is the measured defect.
        children = [f"n{i}" for i in range(1, 15)]
        edges = [(f"n{i}", f"n{i + 1}") for i in range(1, 14)]
        findings = lint.check_grid_wrap(self.blocks(2, 7, children), edges)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].check, "grid-wrap")
        self.assertIn("n7", findings[0].message)

    def test_boustrophedon_order_passes(self):
        # 2 rows x 3 cols. Cells fill row-major in declaration order, so a
        # snake VISUAL path (1 2 3 / 6 5 4 with 3 above 4) needs declarations
        # 1,2,3,6,5,4 - cell (1,0) holds n6. Every hop is then adjacent.
        children = ["n1", "n2", "n3", "n6", "n5", "n4"]
        edges = [(f"n{i}", f"n{i + 1}") for i in range(1, 6)]
        self.assertEqual(lint.check_grid_wrap(self.blocks(2, 3, children), edges), [])

    def test_grid_attributes_are_not_children(self):
        """`grid-gap` and `label-container` must not occupy a grid cell."""
        src = ("board: B {\n  grid-rows: 2\n  grid-columns: 3\n"
               "  grid-gap: 100\n  label-container: 60\n"
               "  n1: N1\n  n2: N2\n  n3: N3\n  n4: N4\n"
               "  n1 -> n2\n  n2 -> n3\n  n3 -> n4\n}\n")
        tmp = tempfile.NamedTemporaryFile("w", suffix=".d2", delete=False,
                                          encoding="utf-8")
        tmp.write(src)
        tmp.close()
        self.addCleanup(Path(tmp.name).unlink)
        blocks, edges = lint.parse_source(Path(tmp.name))
        # An unfiltered scan makes grid-gap child 0, shifting n3 to row 1.
        self.assertEqual(blocks["board"].children, ["n1", "n2", "n3", "n4"])
        findings = lint.check_grid_wrap(blocks, edges)
        self.assertEqual(len(findings), 1)
        self.assertIn("'n3' at row 0 col 2", findings[0].message)


class SourceScanTest(unittest.TestCase):
    def parse(self, src: str):
        tmp = tempfile.NamedTemporaryFile("w", suffix=".d2", delete=False,
                                          encoding="utf-8")
        tmp.write(src)
        tmp.close()
        self.addCleanup(Path(tmp.name).unlink)
        return lint.parse_source(Path(tmp.name))

    def test_reverse_arrow_records_edge_in_flow_direction(self):
        _, edges = self.parse("a <- b\n")
        self.assertEqual(edges, [("b", "a")])

    def test_chain_and_label_are_parsed(self):
        _, edges = self.parse('a -> b -> c: label\n')
        self.assertEqual(edges, [("a", "b"), ("b", "c")])

    def test_comments_are_ignored(self):
        _, edges = self.parse("# a -> b\na -> c\n")
        self.assertEqual(edges, [("a", "c")])


class ParseSvgTest(BoardFixture):
    def test_icon_and_thin_rects_are_not_nodes(self):
        body = ('<g class="' + b64("svc") + '"><g class="shape">'
                '<rect x="0" y="0" width="123" height="92" />'
                '<rect x="38" y="23" width="46" height="46" fill="black" />'
                "</g></g>"
                '<g class="' + b64("hdr") + '"><g class="shape"></g>'
                '<svg x="-30" y="-111" width="300" height="90">'
                '<text x="0" y="31" class="md-text" font-size="32">T</text>'
                '<rect x="0" y="50" width="309" height="1" />'
                "</svg></g>")
        board = self.board(body)
        self.assertEqual([n.ident for n in board.nodes], ["svc"])
        self.assertAlmostEqual(board.nodes[0].box.w, 123)

    def test_horizontal_and_vertical_paths_flatten(self):
        pts = lint.sample_path("M 10 20 H 40 V 60")
        self.assertEqual(pts, [(10, 20), (40, 20), (40, 60)])

    def test_auto_cycle_panels_are_separate_boards(self):
        """`--animate-interval` stacks every board into one SVG in the same
        coordinate space; parsing that as one board reports cross-board
        overlaps that are true by construction."""
        panel = ('<g style="animation: d2Transition-d2-x-0 5000ms infinite" '
                 'width="200" height="150" viewBox="0 0 200 150">'
                 '<rect x="0" y="0" width="200" height="150" fill="#FFFFFF" />'
                 + node("a", 20, 40, 90, 66, "A") + "</g>")
        panel2 = ('<g style="animation: d2Transition-d2-x-1 5000ms infinite" '
                  'width="200" height="150" viewBox="0 0 200 150">'
                  '<rect x="0" y="0" width="200" height="150" fill="#FFFFFF" />'
                  + node("a", 20, 40, 90, 66, "A") + "</g>")
        # Identical coordinates in both panels: must NOT collide.
        boards = lint.parse_svg_boards(self.write(svg_doc(panel + panel2), ".svg"))
        self.assertEqual(len(boards), 2)
        for board in boards:
            self.assertEqual(len(board.nodes), 1)
            self.assertEqual(lint.check_header_overlap(board), [])
            self.assertEqual(lint.check_label_on_node(board), [])

    def test_relative_path_and_curve(self):
        pts = lint.sample_path("M 0 0 l 10 0 c 5 0 5 10 10 10")
        self.assertAlmostEqual(pts[1][0], 10)
        self.assertAlmostEqual(pts[-1][0], 20)
        self.assertAlmostEqual(pts[-1][1], 10)


class EndToEndExitCodeTest(BoardFixture):
    """The contract callers depend on: exit 0 clean, 1 findings, 2 no input."""

    def run_lint(self, argv):
        old_argv, old_out, old_err = sys.argv, sys.stdout, sys.stderr
        sys.argv = ["lint_svg.py", *argv]
        sink = io.StringIO()
        sys.stdout = sys.stderr = sink
        try:
            return lint.main()
        finally:
            sys.argv, sys.stdout, sys.stderr = old_argv, old_out, old_err

    def test_findings_exit_1(self):
        path = self.write(svg_doc(
            float_text("title", 300, 40, "Deployment Board", 32)
            + float_text("subtitle", 300, 44, "Sub", 18)), ".svg")
        self.assertEqual(self.run_lint([str(path), "--quiet"]), 1)

    def test_clean_exits_0(self):
        path = self.write(svg_doc(node("a", 100, 100, 94, 66, "A")), ".svg")
        self.assertEqual(self.run_lint([str(path), "--quiet"]), 0)

    def test_missing_input_exits_2(self):
        self.assertEqual(self.run_lint(["/nonexistent/board.svg"]), 2)


if __name__ == "__main__":
    unittest.main()
