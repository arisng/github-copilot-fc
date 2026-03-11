#!/usr/bin/env python3
"""
Create MD Issue Script for md-issue-writer skill

Usage:
    python create_issue.py --type "Bug" --title "Fix login timeout" --description "Users are logged out after 5 minutes" --severity "High" --status "Investigating"

Required args:
    --type: One of Bug, Feature Plan, RFC, ADR, Task, Retrospective
    --title: Concise title for the issue

Optional args:
    --description: Description text
    --severity: Critical, High, Medium, Low, N/A
    --status: Appropriate status for the type
    --author: Author name <email>
    --reviewer: Reviewer name
    --id: Short identifier
    --related: Comma-separated list of related filenames
    --milestone: Release or milestone name
"""

import argparse
import os
import sys
from datetime import datetime
from pathlib import Path
import re

def kebab_case(s):
    """Convert string to kebab-case."""
    s = re.sub(r'[^\w\s-]', '', s)  # Remove special chars except - and space
    s = re.sub(r'\s+', '-', s)  # Replace spaces with -
    return s.lower()

def get_issues_folder():
    """Determine the issues folder.
    
    The new default location is the top‑level `.issues` directory, which is
    created if necessary.  All new documents are written there; legacy folders
    are no longer consulted.
    """
    repo_root = Path.cwd()
    dot_issues = repo_root / '.issues'

    # Always prefer `.issues`.  Create the directory if it doesn't exist so that
    # subsequent runs (and other tools) can rely on its presence.
    if not dot_issues.exists():
        # if any of the legacy folders exist, migrate their contents lazily by
        # leaving them alone; users can manually move files later.  But we still
        # use `.issues` as the target going forward.
        dot_issues.mkdir(parents=True, exist_ok=True)
    return dot_issues

def get_template_path(type_name):
    """Get the path to the template file for the given type."""
    type_to_filename = {
        'Bug': 'bug-report.md',
        'Feature Plan': 'feature-plan.md',
        'RFC': 'rfc.md',
        'ADR': 'adr.md',
        'Task': 'task.md',
        'Retrospective': 'retrospective.md'
    }
    
    filename = type_to_filename.get(type_name)
    if not filename:
        return None
    
    # Look for templates directory relative to this script
    script_dir = Path(__file__).parent
    templates_dir = script_dir.parent / 'templates'
    
    template_file = templates_dir / filename
    if template_file.exists():
        return template_file
    
    return None

def extract_template_section(template_content):
    """Extract the template markdown section from a template file.
    
    The template files contain a "## Template" section with triple backticks
    containing the raw markdown template.
    """
    # Find the template section - look for content between ```markdown and ```
    match = re.search(r'## Template\s*\n```markdown?\n(.*?)\n```', template_content, re.DOTALL)
    if match:
        return match.group(1)
    return ''

def get_template(type_name):
    """Get the template content for the given type.
    
    Loads templates from the templates/ directory to avoid duplication.
    """
    template_path = get_template_path(type_name)
    if not template_path:
        return ''
    
    try:
        with open(template_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Extract the template from the markdown code block
        template = extract_template_section(content)
        return template
    except Exception as e:
        print(f"Error reading template from {template_path}: {e}")
        return ''

def format_optional(field, value):
    """Format optional YAML field."""
    if value:
        return f'{field}: {value}\n'
    return ''

def prepare_template_for_substitution(template_str):
    """Prepare template for Python string formatting.
    
    Converts template placeholders to Python format strings:
    - YYYY-MM-DD → {date}
    - [Concise Title] → {title}
    - [What broke?...] → {description}
    - severity/status lines → {severity}/{status} placeholders
    """
    result = template_str
    
    # Replace date placeholder
    result = result.replace('YYYY-MM-DD', '{date}')
    
    # Replace field values in YAML frontmatter
    result = re.sub(r'severity: .*', 'severity: {severity}', result)
    result = re.sub(r'status: .*', 'status: {status}', result)
    
    # Replace common section placeholders with {title} and {description}
    # [Concise Title], [Feature Name], [Task Name], etc. → {title}
    result = re.sub(r'\[(?:Concise Title|Feature Name|Topic|Decision Title|Task Name|Title)\]', '{title}', result)
    
    # For description placeholders - look for the first occurrence in each section after the title
    # Handle various descriptive placeholders
    lines = result.split('\n')
    in_frontmatter = False
    first_description = True
    
    for i, line in enumerate(lines):
        if line.startswith('---'):
            in_frontmatter = not in_frontmatter
            continue
        
        if in_frontmatter:
            continue
        
        # Skip the title line
        if line.startswith('#'):
            continue
        
        # Replace the first substantial placeholder with {description}
        if first_description and '[' in line and ']' in line:
            # Replace opening bracket content with {description}
            lines[i] = re.sub(r'\[.*?\]', '{description}', line, count=1)
            first_description = False
            break
    
    result = '\n'.join(lines)
    
    # Handle optional fields that should be empty if not provided
    # author, reviewer, id, related, milestone
    result = result.replace('{author}', '')  # Will be filled by format_optional
    result = result.replace('{reviewer}', '')
    result = result.replace('{id}', '')
    result = result.replace('{related}', '')
    result = result.replace('{milestone}', '')
    
    return result

def main():
    parser = argparse.ArgumentParser(description='Create a new issue document.')
    parser.add_argument('--type', required=True, choices=['Bug', 'Feature Plan', 'RFC', 'ADR', 'Task', 'Retrospective'], help='Type of issue')
    parser.add_argument('--title', required=True, help='Title of the issue')
    parser.add_argument('--description', default='', help='Description')
    parser.add_argument('--severity', default='Medium', choices=['Critical', 'High', 'Medium', 'Low', 'N/A'], help='Severity')
    parser.add_argument('--status', default='Draft', help='Status')
    parser.add_argument('--author', help='Author name <email>')
    parser.add_argument('--reviewer', help='Reviewer name')
    parser.add_argument('--id', help='Short identifier')
    parser.add_argument('--related', help='Comma-separated related filenames')
    parser.add_argument('--milestone', help='Milestone name')

    args = parser.parse_args()

    # Get current date
    today = datetime.now().strftime('%Y-%m-%d')
    yy = datetime.now().strftime('%y%m%d')

    # Kebab case title
    kebab_title = kebab_case(args.title)

    # Filename
    filename = f'{yy}_{kebab_title}.md'

    # Issues folder
    issues_folder = get_issues_folder()
    issues_folder.mkdir(parents=True, exist_ok=True)

    filepath = issues_folder / filename

    # Get template
    template = get_template(args.type)
    if not template:
        print(f"Unknown type: {args.type}")
        return
    
    # Prepare template for substitution
    template = prepare_template_for_substitution(template)
    
    # Format optional fields
    author = format_optional('author', args.author)
    reviewer = format_optional('reviewer', args.reviewer)
    id_field = format_optional('id', args.id)
    milestone = format_optional('milestone', args.milestone)
    if args.related:
        related_list = '\n'.join(f'  - {r.strip()}' for r in args.related.split(','))
        related = f'related:\n{related_list}\n'
    else:
        related = ''

    # Fill template
    content = template.format(
        date=today,
        severity=args.severity,
        status=args.status,
        author=author,
        reviewer=reviewer,
        id=id_field,
        related=related,
        milestone=milestone,
        title=args.title,
        description=args.description
    )

    # Write file
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f"Created issue document: {filepath}")

    # Automatically run metadata extraction to keep the index fresh.
    # We use subprocess for better control and to report errors.
    script_dir = Path(__file__).parent
    script = script_dir / 'extract_issue_metadata.py'
    if script.exists():
        print("Running metadata extraction...")
        try:
            # Use the same Python interpreter, capture output for visibility
            import subprocess
            result = subprocess.run([sys.executable, str(script)], check=True)
            if result.returncode != 0:
                print(f"[ERROR] metadata script exited with {result.returncode}")
        except Exception as e:
            print(f"[ERROR] failed to run metadata extraction: {e}")

if __name__ == "__main__":
    main()