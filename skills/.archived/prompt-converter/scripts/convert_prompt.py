import os
import argparse
import yaml
import re
from pathlib import Path

def kebab_case(s):
    """Convert string to kebab-case."""
    s = re.sub(r'[^\w\s-]', '', s)
    s = re.sub(r'\s+', '-', s)
    return s.lower()

def extract_sections(content):
    """Extract frontmatter and main content."""
    frontmatter = {}
    main_content = ""
    
    if content.startswith('---'):
        parts = content.split('---', 2)
        if len(parts) >= 3:
            try:
                frontmatter = yaml.safe_load(parts[1])
            except:
                pass
            main_content = parts[2].strip()
    else:
        main_content = content.strip()
        
    return frontmatter, main_content

def convert_to_copilot(src_path, output_dir):
    with open(src_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    frontmatter, main_content = extract_sections(content)
    
    name = frontmatter.get('name', Path(src_path).stem)
    description = frontmatter.get('description', '')
    
    # Use template if exists, else build manually
    template_path = Path(__file__).parent.parent / 'templates' / 'copilot.prompt.md.template'
    
    target_path = Path(output_dir) / f"{kebab_case(name)}.prompt.md"
    
    # Simple manual build for robustness
    copilot_content = f"""---
name: {kebab_case(name)}
agent: 'agent'
description: '{description}'
---

# {name.replace('-', ' ').title()}

{main_content}

## Context

$ARGUMENTS
"""
    
    os.makedirs(output_dir, exist_ok=True)
    with open(target_path, 'w', encoding='utf-8') as f:
        f.write(copilot_content)
        
    return target_path

def convert_to_claude(src_path, output_dir):
    with open(src_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    frontmatter, main_content = extract_sections(content)
    
    description = frontmatter.get('description', '')
    name = frontmatter.get('name', Path(src_path).stem.replace('.prompt', ''))
    
    # Clean main content from Copilot specifics
    main_content = main_content.replace('## Context\n\n$ARGUMENTS', '').strip()
    main_content = main_content.replace('$ARGUMENTS', '').strip()
    
    target_path = Path(output_dir) / f"{kebab_case(name)}.md"
    
    claude_content = f"""---
description: '{description}'
---

# {name.replace('-', ' ').title()}

{main_content}
"""
    
    os.makedirs(output_dir, exist_ok=True)
    with open(target_path, 'w', encoding='utf-8') as f:
        f.write(claude_content)
        
    return target_path

def main():
    parser = argparse.ArgumentParser(description='Convert between Claude and Copilot prompts.')
    parser.add_argument('--src', required=True, help='Source prompt file path')
    parser.add_argument('--to', choices=['copilot', 'claude'], required=True, help='Target format')
    parser.add_argument('-o', '--output', default='.', help='Output directory')
    
    args = parser.parse_args()
    
    if args.to == 'copilot':
        result = convert_to_copilot(args.src, args.output)
    else:
        result = convert_to_claude(args.src, args.output)
        
    print(f"Successfully converted to {result}")

if __name__ == "__main__":
    main()
