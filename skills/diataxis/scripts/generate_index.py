#!/usr/bin/env python3
"""
Script to generate index.md for Diátaxis-organized documentation.

Scans the specified docs root (default .docs) for subfolders: tutorials, how-to, reference, explanation.
Supports nested sub-category folders (e.g., reference/ralph/, how-to/copilot/).
Extracts titles from .md files and generates an index.md file with links organized by category
and sub-category.
"""

import os
import sys
from pathlib import Path


def get_title(filepath):
    """Extract the title from the first line of a markdown file."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            first_line = f.readline().strip()
            if first_line.startswith('# '):
                return first_line[2:].strip()
            else:
                return os.path.basename(filepath).replace('.md', '').replace('-', ' ').title()
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return os.path.basename(filepath).replace('.md', '').replace('-', ' ').title()


def main(docs_root='.docs'):
    """Generate the index.md file."""
    categories = {
        'tutorials': 'Tutorials',
        'how-to': 'How-to Guides',
        'reference': 'Reference',
        'explanation': 'Explanation'
    }

    index_content = """# Copilot Workspace Documentation Index

This index links Diátaxis-organized documentation for the workspace.

"""

    for folder, section in categories.items():
        cat_path = Path(docs_root) / folder
        if not cat_path.is_dir():
            continue

        # Collect root-level files (not in sub-categories)
        root_files = sorted(f.name for f in cat_path.iterdir()
                            if f.is_file() and f.suffix == '.md')

        # Collect sub-category folders
        subcats = sorted(d.name for d in cat_path.iterdir()
                         if d.is_dir() and not d.name.startswith('.'))

        if not root_files and not subcats:
            continue

        index_content += f"## {section}\n\n"

        # Root-level files first
        for file in root_files:
            filepath = cat_path / file
            title = get_title(str(filepath))
            link = f"{folder}/{file}"
            index_content += f"- [{title}]({link})\n"

        if root_files and subcats:
            index_content += "\n"

        # Sub-category sections
        for subcat in subcats:
            subcat_path = cat_path / subcat
            subcat_files = sorted(f.name for f in subcat_path.iterdir()
                                  if f.is_file() and f.suffix == '.md')
            if not subcat_files:
                continue

            subcat_title = subcat.replace('-', ' ').title()
            index_content += f"### {subcat_title}\n\n"

            for file in subcat_files:
                filepath = subcat_path / file
                title = get_title(str(filepath))
                link = f"{folder}/{subcat}/{file}"
                index_content += f"- [{title}]({link})\n"

            index_content += "\n"

        if not subcats:
            index_content += "\n"

    index_path = os.path.join(docs_root, 'index.md')
    with open(index_path, 'w', encoding='utf-8') as f:
        f.write(index_content)
    print(f"Generated {index_path}")

if __name__ == '__main__':
    docs_root = sys.argv[1] if len(sys.argv) > 1 else '.docs'
    main(docs_root)