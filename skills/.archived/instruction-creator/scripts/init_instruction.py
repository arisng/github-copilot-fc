import os
import argparse
import platform

def detect_environment():
    """Detect the current environment and return the appropriate skills base path."""
    return os.path.expanduser('~/.copilot/skills')

def create_instruction(name, description, apply_to, skills_path, output_dir='instructions'):
    if not name.endswith('.instructions.md'):
        name += '.instructions.md'

    path = os.path.join(output_dir, name)

    if os.path.exists(path):
        print(f"Error: File {path} already exists.")
        return

    content = f"""---
description: '{description}'
applyTo: '{apply_to}'
---

# {name.replace('.instructions.md', '').replace('-', ' ').title()}

## Overview
Brief introduction and context.

## Workflow
1. **Detect Environment**: Set `skills_source` based on environment.
   ```python
   import os
   skills_source = os.path.expanduser('~/.copilot/skills')
   ```

2. **Analyze Input**: Understand the requirements.

3. **Execute Skill**: Run the appropriate skill from `{skills_path}/<skill-name>/SKILL.md`.

4. **Verify Output**: Validate results against requirements.

## Rules & Constraints
- Rule 1
- Rule 2

## Best Practices
- Specific practice 1

## Code Standards
### Naming Conventions
- Rule 1

## Common Patterns
### Pattern 1
Description and example

```language
code example
```

## Validation
- Build command: `npm run build`
"""
    
    os.makedirs(output_dir, exist_ok=True)
    with open(path, 'w') as f:
        f.write(content)

    print(f"Created {path}")

def main():
    parser = argparse.ArgumentParser(
        description='Initialize a new instruction file. Auto-detects environment for skills path.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Create in current directory
    python init_instruction.py my-rules --description "My custom rules" --applyTo "**/*.py"

    # Create in specific output directory
    python init_instruction.py my-rules -o ./custom-instructions

    # Use specific skills base path
    python init_instruction.py my-rules --skills-path ~/.codex/skills
        """
    )
    parser.add_argument('name', help='Name of the instruction file (e.g., react-best-practices)')
    parser.add_argument('--description', default='Brief description of purpose', help='Description for frontmatter')
    parser.add_argument('--applyTo', default='**', help='Glob pattern for applyTo')
    parser.add_argument('-o', '--output', default='instructions', help='Output directory (default: instructions)')
    parser.add_argument('--skills-path', default=None, help='Override skills base path (default: auto-detect)')

    args = parser.parse_args()

    # Auto-detect skills path if not provided
    if args.skills_path is None:
        args.skills_path = detect_environment()
        print(f"Auto-detected environment: {platform.system()}")
        print(f"Skills path: {args.skills_path}")

    create_instruction(args.name, args.description, args.applyTo, args.skills_path, args.output)

if __name__ == "__main__":
    main()
