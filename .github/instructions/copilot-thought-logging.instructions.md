---
applyTo: '**'
description: 'See process Copilot is following where you can edit this to reshape the interaction or save when follow up may be needed'
---

# Copilot Process tracking Instructions

**ABSOLUTE MANDATORY RULES:**
- You must review these instructions in full before executing any steps to understand the full instructions guidelines.
- You must follow these instructions exactly as specified without deviation.
- Do not keep repeating status updates while processing or explanations unless explicitly required. This is bad and will flood Copilot session context.
- NO phase announcements (no "# Phase X" headers in output)
- Phases must be executed one at a time and in the exact order specified.
- NO combining of phases in one response
- NO skipping of phases
- NO verbose explanations or commentary
- Only output the exact text specified in phase instructions

# Phase 1: Initialization

- Get current time in UTC+7 using the mcp_time_get_current_time tool with parameter timezone set to 'UTC+7'
- From the returned time, extract year (4 digits), month (1-12), day (1-31), hour (0-23), minute (0-59)
- Format the filename as: f"{year % 100:02d}{month:02d}{day:02d}_{hour:02d}{minute:02d}_Copilot-Processing.md"
- Create file `.copilot-logging\\${filename}` in workspace root (note: use the absolute path, and the directory will be created if it does not exist)
- Populate the created file with user request details
- Work silently without announcements until complete.
- When this phase is complete keep mental note of this that <Phase 1> is done and does not need to be repeated.

# Phase 2: Planning

- Generate an action plan into the processing file.
- Generate detailed and granular task specific action items to be used for tracking each action plan item with todo/complete status in the processing file.
- This should include:
  - Specific tasks for each action item in the action plan as a phase.
  - Clear descriptions of what needs to be done
  - Any dependencies or prerequisites for each task
  - Ensure tasks are granular enough to be executed one at a time
- Work silently without announcements until complete.
- When this phase is complete keep mental note of this that <Phase 2> is done and does not need to be repeated.

# Phase 3: Execution

- Execute action items from the action plan in logical groupings/phases
- Work silently without announcements until complete.
- Update the processing file and mark the action item(s) as complete in the tracking.
- When a phase is complete keep mental note of this that the specific phase from the processing file is done and does not need to be repeated.
- Repeat this pattern until all action items are complete

# Phase 4: Summary

- Add summary to the processing file
- Work silently without announcements until complete.
- Execute only when ALL actions complete
- Inform user: "Added final summary to the processing file."
- Remind user to review the summary and confirm completion of the process then to remove the file when done so it is not added to the repository.

**ENFORCEMENT RULES:**
- NEVER write "# Phase X" headers in responses
- NEVER repeat the word "Phase" in output unless explicitly required
- NEVER provide explanations beyond the exact text specified
- NEVER combine multiple phases in one response
- NEVER continue past current phase without user input
- If you catch yourself being verbose, STOP and provide only required output
- If you catch yourself about to skip a phase, STOP and go back to the correct phase
- If you catch yourself combining phases, STOP and perform only the current phase
