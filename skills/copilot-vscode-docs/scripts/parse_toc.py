#!/usr/bin/env python3
"""
Script to parse VS Code documentation TOC from GitHub and generate LLM-friendly markdown.
"""

import json
import re
import sys
import urllib.request
from pathlib import Path

TOC_URL = "https://raw.githubusercontent.com/microsoft/vscode-docs/main/docs/toc.json"
BASE_URL = "https://code.visualstudio.com"


def parse_toc_json(text):
    """Parse TOC JSON, tolerating trailing commas that upstream occasionally ships."""
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # Strict parse failed; strip trailing commas before ] or } and retry.
        return json.loads(re.sub(r",(\s*[\]}])", r"\1", text))


def fetch_toc():
    """Fetch the TOC JSON from GitHub."""
    try:
        with urllib.request.urlopen(TOC_URL, timeout=30) as response:
            return parse_toc_json(response.read().decode("utf-8"))
    except Exception as e:
        print(f"Error fetching TOC: {e}", file=sys.stderr)
        sys.exit(1)

def parse_topics(topics, level=0):
    """Recursively parse topics into markdown lines."""
    lines = []
    indent = "  " * level

    for topic in topics:
        if isinstance(topic, list):
            if len(topic) == 3 and topic[0] == "" and topic[1] == "" and isinstance(topic[2], dict):
                # Nested ["", "", {dict}] format
                nested = topic[2]
                name = nested.get("name", "")
                if name:
                    header = "#" * (level + 2)  # ## for level 0, ### for level 1, etc.
                    lines.append(f"{header} {name}")
                if "topics" in nested:
                    lines.extend(parse_topics(nested["topics"], level + 1))
            elif len(topic) in (2, 3) and isinstance(topic[0], str) and isinstance(topic[1], str) \
                    and (len(topic) == 2 or isinstance(topic[2], dict)):
                # [title, url] or [title, url, {options}] format (options: secondary, etc.)
                title, url = topic[0], topic[1]
                if title.strip() and url.strip():  # Skip empty titles/urls
                    full_url = BASE_URL + url
                    lines.append(f"{indent}- [{title}]({full_url})")
        elif isinstance(topic, dict):
            # Direct nested section
            name = topic.get("name", "")
            if name:
                header = "#" * (level + 2)
                lines.append(f"{header} {name}")
            if "topics" in topic:
                lines.extend(parse_topics(topic["topics"], level + 1))
        elif isinstance(topic, str):
            # Sometimes topics might be strings, skip
            continue

    return lines

def generate_markdown(toc_data):
    """Generate markdown from TOC data."""
    lines = ["# VS Code Documentation TOC\n"]

    for section in toc_data:
        name = section.get("name", "")
        if name:
            lines.append(f"## {name}")
        topics = section.get("topics", [])
        lines.extend(parse_topics(topics))
        lines.append("")  # Empty line between sections

    return "\n".join(lines)

def main():
    """Main function."""
    toc_data = fetch_toc()
    markdown = generate_markdown(toc_data)

    # Write to assets/toc.md
    output_path = Path(__file__).parent.parent / "assets" / "toc.md"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(markdown)

    print(f"TOC markdown generated at {output_path}")

if __name__ == "__main__":
    main()