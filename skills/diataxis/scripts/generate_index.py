#!/usr/bin/env python3
"""
Script to generate index.md for Diátaxis-organized documentation.

Scans the specified docs root (default .docs) for subfolders: tutorials, how-to, reference, explanation.
Recursively renders nested sub-category folders (e.g., reference/ralph/, how-to/copilot/cli/).
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


def has_visible_content(directory):
    """Return True when the directory contains visible files or subdirectories."""
    for entry in directory.iterdir():
        if entry.name == '.gitkeep':
            return True
        if not entry.name.startswith('.'):
            return True
    return False


def render_directory(directory, docs_root, heading_level):
    """Render a directory and any nested subdirectories recursively."""
    direct_files = sorted(
        f for f in directory.iterdir()
        if f.is_file() and f.suffix == '.md'
    )
    child_dirs = sorted(
        d for d in directory.iterdir()
        if d.is_dir() and not d.name.startswith('.')
    )
    visible_children = [d for d in child_dirs if has_visible_content(d)]
    has_keep_marker = any(entry.name == '.gitkeep' for entry in directory.iterdir())

    if not direct_files and not visible_children and not has_keep_marker:
        return ""

    heading = directory.name.replace('-', ' ').title()
    content = f"{'#' * heading_level} {heading}\n\n"

    for file in direct_files:
        title = get_title(str(file))
        link = f"{directory.relative_to(docs_root).as_posix()}/{file.name}"
        content += f"- [{title}]({link})\n"

    if direct_files and visible_children:
        content += "\n"

    if not direct_files and not visible_children:
        content += "- _No documents yet._\n\n"

    for child_dir in visible_children:
        child_content = render_directory(child_dir, docs_root, heading_level + 1)
        if child_content:
            content += child_content

    return content


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

    docs_root_path = Path(docs_root)

    for folder, section in categories.items():
        cat_path = docs_root_path / folder
        if not cat_path.is_dir():
            continue

        root_files = sorted(
            f for f in cat_path.iterdir()
            if f.is_file() and f.suffix == '.md'
        )
        subdirs = sorted(
            d for d in cat_path.iterdir()
            if d.is_dir() and not d.name.startswith('.')
        )
        visible_subdirs = [d for d in subdirs if has_visible_content(d)]

        if not root_files and not visible_subdirs:
            continue

        index_content += f"## {section}\n\n"

        for file in root_files:
            title = get_title(str(file))
            link = f"{folder}/{file.name}"
            index_content += f"- [{title}]({link})\n"

        if root_files and visible_subdirs:
            index_content += "\n"

        for subdir in visible_subdirs:
            index_content += render_directory(subdir, docs_root_path, 3)
            if not index_content.endswith("\n\n"):
                index_content += "\n"

        if not root_files:
            index_content += "\n"

    index_path = os.path.join(docs_root, 'index.md')
    index_content = index_content.rstrip() + "\n"
    with open(index_path, 'w', encoding='utf-8') as f:
        f.write(index_content)
    print(f"Generated {index_path}")

if __name__ == '__main__':
    docs_root = sys.argv[1] if len(sys.argv) > 1 else '.docs'
    main(docs_root)
