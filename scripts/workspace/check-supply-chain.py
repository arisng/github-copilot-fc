#!/usr/bin/env python3
"""Supply-chain reference guard for checked-in content (plan W5.3).

Scans tracked + untracked-unignored markdown/json/html/yaml/sh/ps1 for:
  pipe      curl|wget piped into a shell (curl ... | bash)
  http      insecure http:// links (localhost / loopback / XML namespaces exempt)
  script    http(s)-sourced <script src=...> tags without an integrity attribute
  domain    https link domains not present in scripts/workspace/known-domains.txt

Severity policy (plan): every finding is WARN by default so the legacy backlog
never blocks unrelated work (shrink-only ratchet); flip findings to failures
with --strict once the backlog is clean. The gate maps WARN lines to WARN.

Modes:
  (default)              report [WARN]/[PASS] lines; exit 0 (exit 1 = tooling error)
  --strict               additionally exit 1 when any warning exists (ratchet target)
  --update-allowlist     regenerate known-domains.txt from the current tree

No third-party dependencies (stdlib only).
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ALLOWLIST = Path(__file__).resolve().parent / "known-domains.txt"

EXTS = (".md", ".json", ".html", ".htm", ".yml", ".yaml", ".sh", ".ps1")
DENY = re.compile(
    r"(^|/)(node_modules|\.archived|\.build|\.playwright-cli|\.ralph-sessions|"
    r"\.issues|workshops)(/|$)|^scripts/test/\.artifacts/"
    r"|^evals/[^/]+/(fixtures|results)/"
    # The supply-chain selftest embeds violation strings as fixtures by design.
    r"|^scripts/test/workspace-check-supply-chain\.tests\.ps1$"
)
PIPE = re.compile(r"\b(?:curl|wget)\b[^\n|]{0,240}?\|\s*(?:sudo\s+)?(?:ba|z|fi|c)?sh\b")
# Require an FQDN or IPv4 after the scheme: exempts nginx upstream names
# (proxy_pass http://tldraw_backend) and format placeholders (http://host:port).
HTTP = re.compile(
    r"http://(?!localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]|www\.w3\.org)"
    r"(?:(?:[a-z0-9-]+\.)+[a-z]{2,}|(?:\d{1,3}\.){3}\d{1,3})",
    re.I,
)
# xmlns="..." URIs are identifiers, never fetched — strip before scanning.
XMLNS = re.compile(r"\bxmlns(:[\w.-]+)?\s*=\s*[\"'][^\"']*[\"']", re.I)
SCRIPT_TAG = re.compile(r"<script\b[^>]*>", re.I)
SCRIPT_SRC = re.compile(r"\bsrc\s*=\s*[\"'](https?://[^\"']+)[\"']", re.I)
DOMAIN = re.compile(r"https://([a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,})(?::\d+)?", re.I)
VALID_DOMAIN = re.compile(r"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$")
# Inline code carries command material, not content links: a git config
# section name (credential.https://github.com.helper=...) is data nobody
# clicks, so code spans leave the domain scan (retro 2026-11-24).
CODE_SPAN = re.compile(r"`[^`\n]*`")


def discover() -> list[str]:
    try:
        raw = subprocess.run(
            ["git", "ls-files", "-co", "--exclude-standard", "-z"],
            cwd=REPO, capture_output=True, check=True,
        ).stdout.decode("utf-8", "replace")
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"[FAIL] tooling: cannot list files via git ({exc})")
        raise SystemExit(1)
    return [
        f for f in raw.split("\0")
        if f and f.endswith(EXTS) and not DENY.search(f)
    ]


def load_allowlist() -> set[str]:
    if not ALLOWLIST.exists():
        return set()
    out = set()
    for line in ALLOWLIST.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            out.add(line.lower())
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict", action="store_true",
                        help="exit 1 when any warning exists (future ratchet mode)")
    parser.add_argument("--update-allowlist", action="store_true",
                        help="regenerate known-domains.txt from the current tree")
    args = parser.parse_args()

    files = discover()
    findings: list[tuple[str, str, int, str]] = []  # kind, file, line, detail
    domains: set[str] = set()

    for rel in files:
        path = REPO / rel
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            if PIPE.search(line):
                findings.append(("pipe", rel, lineno, line.strip()[:100]))
            match = HTTP.search(XMLNS.sub("", line))
            if match:
                findings.append(("http", rel, lineno, line.strip()[:100]))
        for tag in SCRIPT_TAG.finditer(text):
            tag_text = tag.group(0)
            if SCRIPT_SRC.search(tag_text) and "integrity=" not in tag_text.lower():
                lineno = text.count("\n", 0, tag.start()) + 1
                findings.append(("script", rel, lineno, tag_text.strip()[:100]))
        for match in DOMAIN.finditer(CODE_SPAN.sub("", text)):
            host = match.group(1).lower()
            if VALID_DOMAIN.match(host):
                domains.add(host)

    if args.update_allowlist:
        header = (
            "# known-domains.txt — approved external domains for content links\n"
            "# Regenerate: python3 scripts/workspace/check-supply-chain.py --update-allowlist\n"
            "# Add a domain deliberately when a new trusted host enters the docs.\n"
        )
        ALLOWLIST.write_text(header + "\n".join(sorted(domains)) + "\n", encoding="utf-8")
        print(f"[PASS] known-domains.txt rewritten with {len(domains)} domain(s)")
        return 0

    allowlist = load_allowlist()
    unknown = sorted(d for d in domains if d not in allowlist)
    for host in unknown:
        findings.append(("domain", "(links)", 0, host))

    counts: dict[str, int] = {}
    for kind, rel, lineno, detail in findings:
        counts[kind] = counts.get(kind, 0) + 1
        where = f"{rel}:{lineno}" if lineno else rel
        print(f"[WARN] {kind} {where}: {detail}")

    if not findings:
        print(f"[PASS] supply-chain: {len(files)} file(s) scanned, no findings")
        return 0

    summary = ", ".join(f"{n} {k}" for k, n in sorted(counts.items()))
    print(f"check-supply-chain: {len(findings)} warning(s) ({summary}) across {len(files)} file(s)"
          + (" [strict]" if args.strict else " [warn-first, ratchet-pending]"))
    return 1 if args.strict else 0


if __name__ == "__main__":
    sys.exit(main())
