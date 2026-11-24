#!/usr/bin/env python3
"""Package a .d2 diagram as one self-contained HTML file.

Deterministic pipeline: d2 fmt -> full-compile verification -> export -> inline.

Modes (picked automatically):
- single board            -> static shell around the one SVG
- multi-board             -> drill-down shell: all boards inlined, board hrefs rewritten
                             to #anchors, hash routing + breadcrumb nav (~25 lines of JS)
- --animate-interval MS   -> one auto-cycling SVG (pure CSS), static shell

Stdlib only. Requires the d2 CLI (https://github.com/d2lang/d2) on PATH,
or --d2 PATH / D2_BIN.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import posixpath
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HREF_RE = re.compile(
    r"(?P<prefix>\b(?:xlink:)?href\s*=\s*)(?P<q>[\"'])(?P<target>[^\"']*)(?P=q)"
)
EXTERNAL_PREFIXES = ("http:", "https:", "mailto:", "data:", "#", "//")
RESOURCE_REF_RE = re.compile(
    r"<(?:img|script|link)\b[^>]*\b(?:src|href)\s*=\s*[\"']https?://", re.IGNORECASE
)


def fail(msg: str) -> "None":
    sys.exit("error: " + msg)


def find_d2(explicit: "str | None") -> str:
    cand = explicit or os.environ.get("D2_BIN")
    if cand:
        return cand
    for name in ("d2", "d2.exe"):
        found = shutil.which(name)
        if found:
            return found
    fail("d2 CLI not found on PATH (install: https://github.com/d2lang/d2/releases, "
         "or pass --d2 / set D2_BIN)")
    return ""


def run_d2(d2: str, args: "list[str]", *, quiet: bool = False) -> "subprocess.CompletedProcess[str]":
    proc = subprocess.run([d2, *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    if not quiet and (proc.stdout or proc.stderr):
        sys.stderr.write(proc.stdout or "")
        sys.stderr.write(proc.stderr or "")
    return proc


def strip_xml_decl(svg: str) -> str:
    return re.sub(r"^\s*<\?xml[^>]*\?>\s*", "", svg)


def inject_size(svg: str) -> str:
    """Give the outer <svg> intrinsic width/height from its viewBox.

    D2 emits viewBox-only outer <svg> elements; with width/height `auto` a
    replaced element has no intrinsic size and collapses to 0x0 (clipped,
    unclickable) in several layout contexts."""
    m = re.match(r"(<svg\b[^>]*>)", svg)
    if not m:
        return svg
    tag = m.group(1)
    if re.search(r"\bwidth\s*=", tag) or re.search(r"\bheight\s*=", tag):
        return svg
    vb = re.search(r'\bviewBox\s*=\s*["\']0 0 ([\d.]+) ([\d.]+)["\']', tag)
    if not vb:
        return svg
    sized = tag.replace("<svg", f'<svg width="{vb.group(1)}" height="{vb.group(2)}"', 1)
    return sized + svg[len(tag):]


# --- board registry (multi-board output tree) --------------------------------

def board_key(rel: str) -> str:
    """'outer/index.svg' -> 'outer/index'; 'index.svg' -> 'index'."""
    key = rel.replace(os.sep, posixpath.sep)
    if key.endswith(".svg"):
        key = key[: -len(".svg")]
    return key


def parent_key(key: str) -> "str | None":
    if key == "index":
        return None
    if key.endswith("/index"):
        d = key[: -len("/index")]
        return d.rsplit("/", 1)[0] + "/index" if "/" in d else "index"
    d = key.rsplit("/", 1)[0] if "/" in key else ""
    return (d + "/index") if d else "index"


def board_id(key: str) -> str:
    if key == "index":
        slug = "root"
    elif key.endswith("/index"):
        slug = key[: -len("/index")].replace("/", "-")
    else:
        slug = key.replace("/", "-")
    return "board-" + re.sub(r"[^A-Za-z0-9_-]", "_", slug)


def board_label(key: str, root_label: str) -> str:
    if key == "index":
        return root_label
    last = key.split("/")[-1]
    return key[: -len("/index")].split("/")[-1] if last == "index" else last


def build_registry(boards_dir: Path, root_label: str) -> "dict[str, dict]":
    reg: "dict[str, dict]" = {}
    for p in sorted(boards_dir.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(boards_dir).as_posix()
        key = board_key(rel)
        reg[key] = {
            "file": p,
            "rel": rel,
            "id": board_id(key),
            "label": board_label(key, root_label),
            "parent": parent_key(key),
        }
    for key, meta in reg.items():
        chain = []
        k: "str | None" = key
        while k is not None and k in reg:
            chain.append([reg[k]["id"], reg[k]["label"]])
            k = reg[k]["parent"]
        meta["chain"] = list(reversed(chain))
    return reg


def rewrite_links(text: str, rel_dir: str, key_to_id: "dict[str, str]") -> str:
    def repl(m: "re.Match[str]") -> str:
        # d2 emits Windows backslashes in nested-board hrefs on Windows
        # (e.g. "configure_and_supply\index.svg"); normalize before resolving.
        target = m.group("target").replace("\\", "/")
        if target.startswith(EXTERNAL_PREFIXES) or "://" in target:
            return m.group(0)
        resolved = posixpath.normpath(posixpath.join(rel_dir, target))
        if resolved.endswith(".svg"):
            resolved = resolved[: -len(".svg")]
        bid = key_to_id.get(resolved)
        if bid:
            return f'{m.group("prefix")}{m.group("q")}#{bid}{m.group("q")}'
        return m.group(0)

    return HREF_RE.sub(repl, text)


# --- HTML shells -------------------------------------------------------------

SHELL_CSS = """\
    html, body { margin: 0; padding: 0; min-height: 100%; background: #ffffff; }
    body { display: flex; flex-direction: column; align-items: center;
           font-family: system-ui, -apple-system, "Segoe UI", sans-serif; }
    #d2-stage { flex: 1; display: flex; justify-content: center; align-items: flex-start;
                width: 100%; box-sizing: border-box; padding: 16px; }
    .d2-board { max-width: 100%; }
    .d2-board > svg { display: block; max-width: 100%; height: auto; margin: 0 auto; }"""

NAV_CSS = """
    #d2-nav { position: sticky; top: 0; z-index: 10; width: 100%; box-sizing: border-box;
              padding: 8px 16px; background: rgba(255, 255, 255, 0.92);
              border-bottom: 1px solid #e5e7eb; }
    #d2-crumbs { list-style: none; display: flex; flex-wrap: wrap; gap: 8px;
                 margin: 0; padding: 0; font-size: 14px; color: #374151; }
    #d2-crumbs li + li::before { content: "\\203A"; margin-right: 8px; color: #9ca3af; }
    #d2-crumbs a { color: #2563eb; text-decoration: none; }
    #d2-crumbs a:hover { text-decoration: underline; }
    #d2-crumbs .current { font-weight: 600; color: #111827; }"""

NAV_JS = """\
  (function () {
    var boards = document.querySelectorAll('.d2-board');
    var crumbs = document.getElementById('d2-crumbs');
    function show(id) {
      var target = document.getElementById(id);
      if (!target || !target.classList.contains('d2-board')) {
        id = 'board-root';
        target = document.getElementById(id);
      }
      boards.forEach(function (b) { b.hidden = b.id !== id; });
      var chain = JSON.parse(target.getAttribute('data-chain'));
      crumbs.innerHTML = '';
      chain.forEach(function (c, i) {
        var li = document.createElement('li');
        if (i === chain.length - 1) {
          li.textContent = c[1];
          li.className = 'current';
        } else {
          var a = document.createElement('a');
          a.href = '#' + c[0];
          a.textContent = c[1];
          li.appendChild(a);
        }
        crumbs.appendChild(li);
      });
    }
    window.addEventListener('hashchange', function () {
      show(location.hash.replace(/^#/, ''));
    });
    show(location.hash.replace(/^#/, ''));
  })();"""


def render_html(title: str, css_extra: str, body: str, js: "str | None" = None) -> str:
    script = f"\n<script>\n{js}\n</script>" if js else ""
    return (
        "<!DOCTYPE html>\n"
        '<html lang="en">\n'
        "<head>\n"
        '  <meta charset="UTF-8" />\n'
        '  <meta name="viewport" content="width=device-width, initial-scale=1.0" />\n'
        f"  <title>{html.escape(title)}</title>\n"
        "  <style>\n"
        f"{SHELL_CSS}{css_extra}\n"
        "  </style>\n"
        "</head>\n"
        "<body>\n"
        f"{body}{script}\n"
        "</body>\n"
        "</html>\n"
    )


def wrap_static(svg: str, title: str) -> str:
    body = ('  <div id="d2-stage">\n    <div class="d2-board">\n'
            + inject_size(svg) + "\n    </div>\n  </div>")
    return render_html(title, "", body)


def wrap_nav(reg: "dict[str, dict]", title: str) -> str:
    key_to_id = {k: m["id"] for k, m in reg.items()}
    parts = ['  <nav id="d2-nav"><ol id="d2-crumbs"></ol></nav>', '  <div id="d2-stage">']
    for key in sorted(reg, key=lambda k: (k != "index", k.count("/"), k)):
        meta = reg[key]
        rel_dir = posixpath.dirname(meta["rel"])
        svg = strip_xml_decl(meta["file"].read_text(encoding="utf-8", errors="replace"))
        svg = inject_size(rewrite_links(svg, rel_dir, key_to_id))
        chain = json.dumps(meta["chain"], ensure_ascii=False)
        hidden = "" if key == "index" else " hidden"
        parts.append(
            f'    <div class="d2-board" id="{meta["id"]}"'
            f' data-chain="{html.escape(chain, quote=True)}"{hidden}>\n'
            f"{svg}\n"
            "    </div>"
        )
    parts.append("  </div>")
    return render_html(title, NAV_CSS, "\n".join(parts), NAV_JS)


# --- main --------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="source .d2 file")
    ap.add_argument("-o", "--output", help="output .html (default: <input stem>.html beside input)")
    ap.add_argument("--d2", help="path to the d2 binary (default: PATH, or D2_BIN)")
    ap.add_argument("--layout", choices=["dagre", "elk", "tala"],
                    help="layout engine (default: whatever the source/config selects)")
    ap.add_argument("--theme", type=int, help="theme id")
    ap.add_argument("--dark-theme", type=int, help="dark-mode theme id")
    ap.add_argument("--pad", type=int, default=20, help="padding in px (default 20)")
    ap.add_argument("--salt", help="salt for unique SVG ids (needed for 2+ diagrams per page)")
    ap.add_argument("--animate-interval", type=int, metavar="MS",
                    help="package multi-board output as one auto-cycling SVG (ms per board)")
    ap.add_argument("--skip-fmt", action="store_true", help="do not run d2 fmt on the source")
    args = ap.parse_args()

    src = Path(args.input)
    if not src.is_file():
        fail(f"input not found: {src}")
    d2 = find_d2(args.d2)
    out = Path(args.output) if args.output else src.with_suffix(".html")

    render_flags: "list[str]" = []
    if args.layout:
        render_flags += ["--layout", args.layout]
    if args.theme is not None:
        render_flags += ["--theme", str(args.theme)]
    if args.dark_theme is not None:
        render_flags += ["--dark-theme", str(args.dark_theme)]

    if not args.skip_fmt:
        proc = run_d2(d2, ["fmt", str(src)], quiet=True)
        if proc.returncode != 0:
            sys.stderr.write(proc.stdout or "")
            sys.stderr.write(proc.stderr or "")
            fail("d2 fmt failed")
        print(f"formatted {src}")

    # Sync contract: embed a hash of the post-fmt source so any consumer
    # (manifest check, CI gate, diff review) can detect a source edit whose
    # HTML was never rebuilt. Line endings are normalized to LF first: `d2 fmt`
    # writes CRLF on Windows, so hashing raw bytes made the contract
    # platform-dependent and a fresh clone (LF in the repository) could never
    # match it - every set then reported "source edited after the last build".
    _src_bytes = src.read_bytes().replace(b"\r\n", b"\n")
    source_sha = hashlib.sha256(_src_bytes).hexdigest()

    # Guardrail: full compile - d2 validate is parser-only and misses unknown shapes
    # and invalid style values. --target '' compiles every board (layers/scenarios/
    # steps included) but renders only the root board, so the null device works for
    # single- and multi-board sources on every platform (multiboard output is a
    # directory and cannot target NUL//dev/null directly).
    proc = run_d2(d2, ["--target", "", *render_flags, str(src), os.devnull], quiet=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout or "")
        sys.stderr.write(proc.stderr or "")
        fail(f"verification compile failed for {src} (fix the errors above)")
    print(f"verified {src} (full compile, exit 0)")

    export_flags = ["--no-xml-tag", "--pad", str(args.pad), *render_flags]
    if args.salt:
        export_flags += ["--salt", args.salt]
    if args.animate_interval:
        export_flags += ["--animate-interval", str(args.animate_interval)]

    with tempfile.TemporaryDirectory(prefix="d2html-") as tmp:
        out_base = Path(tmp) / "boards.svg"
        proc = run_d2(d2, [*export_flags, str(src), str(out_base)], quiet=True)
        if proc.returncode != 0:
            sys.stderr.write(proc.stdout or "")
            sys.stderr.write(proc.stderr or "")
            fail("export failed")

        boards_dir = Path(tmp) / "boards"
        title = src.stem
        if args.animate_interval and out_base.is_file():
            html_doc = wrap_static(strip_xml_decl(out_base.read_text(encoding="utf-8",
                                                                   errors="replace")),
                                  title)
            mode = f"auto-cycle ({args.animate_interval} ms/board)"
        elif boards_dir.is_dir():
            reg = build_registry(boards_dir, title)
            if not reg:
                fail("multi-board export produced no board files")
            html_doc = wrap_nav(reg, title)
            mode = f"drill-down nav ({len(reg)} boards)"
        elif out_base.is_file():
            html_doc = wrap_static(strip_xml_decl(out_base.read_text(encoding="utf-8",
                                                                    errors="replace")),
                                   title)
            mode = "single board"
        else:
            fail("export produced neither boards.svg nor a boards/ directory")

    if RESOURCE_REF_RE.search(html_doc):
        print("warning: output references an external resource (img/script/link with http(s))")

    html_doc = html_doc.replace(
        "<!DOCTYPE html>\n",
        f"<!DOCTYPE html>\n<!-- d2-source-sha256:{source_sha} -->\n",
        1,
    )

    out.write_text(html_doc, encoding="utf-8")
    print(f"wrote {out} [{mode}, {out.stat().st_size} bytes]")


if __name__ == "__main__":
    main()
