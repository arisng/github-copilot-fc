---
date: 2025-12-10
type: Retrospective
severity: N/A
status: Implemented

---

# Lesson: Lessons Learned from Creating Skills (issue-writer and git-committer)

## Context
Self-reflection on the process of creating skills, identifying successes, failures, and improvements for future skill development. This retrospective covers the efforts to build new skills based on custom agents (issue-writer.agent.md and git-committer.agent.md), highlighting tooling issues, encoding problems, and process improvements.

## What Went Well
- Successful Outcome: The skill was fully created, packaged, and integrated. It includes a functional Python script (create_issue.py) that generates issue documents in the correct format, references to templates, and proper documentation. The skills index was updated, and the skill is now available for use.
- Adherence to Process: I followed the skill-creator guidelines closely, including understanding the skill's purpose, planning reusable contents (scripts, references, assets), initializing the structure, editing for specificity, packaging, and iterating.
- Integration with Existing Agent: The skill accurately reflected the issue-writer.agent.md, incorporating its templates, naming conventions, and workflow (e.g., folder detection for _docs/issues or .docs/issues, YAML frontmatter, and metadata extraction).
- Tool Usage: I effectively used available tools like run_in_terminal for scripting, create_file for content, and replace_string_in_file for edits, ensuring the workspace was modified correctly.

## What Didn't Go Well
- Encoding and Unicode Errors in Initialization: The inti_skill.py script (misspelled as "inti" instead of "init") failed during SKILL.md creation due to a charmap codec error with Unicode characters (e.g., the arrow "→" in the template). This prevented automated file generation, requiring manual creation and population of files.
- Unicode Errors in Validation: The quick_validate.py script failed on Windows when validating the git-committer skill due to emoji characters (e.g., `1️⃣`) in the SKILL.md example output, causing a charmap codec decoding error. This was resolved by replacing emojis with plain numbered bullets.
- Script Naming and File Type Issues: inti_skill.py was named incorrectly, and quick_validate.md was a Markdown file containing Python code instead of a proper .py module. This caused import failures in package_skill.py, requiring manual fixes.
- Incomplete Automation: The skill-creator scripts assumed a fully functional environment but didn't handle real-world constraints (Windows console encoding, file naming), leading to partial failures and manual intervention.
- Markdown Lint Errors: Generated files had lint errors (e.g., missing blank lines around lists, headings), indicating templates weren't optimized for clean output.
- Lack of Validation Feedback: Early failures didn't provide clear guidance, and the process exposed gaps in error handling.
- Context Awareness: Didn't initially check for existing issues folders or validate script assumptions.

## Key Lessons Learned
- Prioritize Tool Reliability: Before relying on scripts, verify their completeness (e.g., file types, encoding handling). Scripts should include try-except blocks for encoding issues, provide clear error messages, and offer manual override options.
- Improve Documentation and Naming Conventions: Use consistent naming, version control for scripts, and include setup instructions (e.g., "Ensure UTF-8 encoding" or "Rename files as needed"). Document known limitations in the skill-creator README.
- Enhance Validation and Iteration: Integrate automated linting and testing into the skill creation pipeline. For example, after editing, run a quick check for markdown issues before packaging.
- Contextual Awareness and User Feedback: Gather more context upfront (e.g., check OS, encoding) and provide user-friendly feedback. In responses, explain workarounds clearly and suggest improvements to the underlying tools.
- Balance Automation with Manual Control: Automation is great, but when it fails, have clear manual steps. Document manual alternatives in the skill-creator instructions, and ensure the process can resume from failures.
- Content Generation Safety: When copying content from agents or other sources, sanitize for encoding compatibility; prefer ASCII-safe characters to avoid platform-specific decoding failures.

## Actions Taken

- Fixed the extract-issue-metadata.ps1 script to correctly detect and use the issues folder (_docs or .docs) and output the index to the same location.
- Manually created and populated skill files due to init script failures.
- Created quick_validate.py from the .md content to enable packaging.
- Updated the skills index to include the new skill.
- Corrected the typo in init_skill.py filename.
- Fixed encoding issues in init_skill.py by adding UTF-8 encoding to file writes and replacing Unicode characters with ASCII equivalents.
- Verified the init_skill.py script works without errors.
- Fixed Unicode issues in git-committer SKILL.md by removing emojis to ensure cross-platform compatibility.
- Updated quick_validate.py to use UTF-8 encoding for file reads, preventing charmap decoding errors on Windows.

## Future Prevention / Improvements

- [x] Fix the skill-creator scripts: Update inti_skill.py to handle Unicode properly (use encoding='utf-8'), correct the name to init_skill.py, and convert quick_validate.md to .py. Add Windows-specific testing.
- [ ] Add a Quick-Start Guide: Include a checklist in the skill-creator for common issues (e.g., "If init fails, manually create files from templates").
- [ ] Iterate on the Skill: Test the "issue-writer" skill in practice and refine based on real usage.
- [ ] General AI Improvement: In future tasks, proactively check for tool dependencies and simulate edge cases before executing multi-step processes.
- [x] Update validation scripts to specify UTF-8 encoding for file reads to handle Unicode properly and avoid charmap errors.
