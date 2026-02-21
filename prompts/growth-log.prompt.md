---
agent: 'agent'
tools: ['read/terminalSelection', 'read/terminalLastCommand', 'read/problems', 'read/readFile', 'sequentialthinking/*', 'time/*', 'google-calendar/*']
description: 'Maintain a Growth Log using Google Calendar All-Day events as a searchable database'
model: Raptor mini (Preview) (copilot)
metadata:
  version: 1.0.0
  author: arisng
---

Process the user's input to create or schedule Growth Log entries in Google Calendar.

## Requirements
- Taxonomy: Select the single most relevant [TAG] from the table below. **Note: This taxonomy table is continuously evolving. If no appropriate tag fits the content during analysis, dynamically create a new tag. The new tag will only be used in the calendar event title for this entry and will not be immediately added to this table. Taxonomy refinement based on historical events is handled through a separate process outside the scope of current process.**

| Tag   | Priority      | Description |
|-------|---------------|-------------|
| [AI]  | High Priority | AI Engineering, RAG, Agents, .NET, Coding, Deep Tech, Work Goals |
| [Baby]| High Priority | Parenting, Infant milestones, Health, supporting Wife, Family Travel |
| [SaaS]| Medium Priority | Micro-SaaS ideas, Vietnam SME Market, Business Strategy, Solopreneurship |
| [VF7] | Low Priority  | Car maintenance/charging, Leisure Travel, General Life/News |

- Extract a 3-5 word "Key Insight" or "Action" from the context to summarize the main point of the entry.
- Title Format: [TAG] Topic - Key Insight
- Description: One-paragraph executive summary

## Actions
- If input contains "log this": Use '#tool:google-calendar/create-event' to create a new All-Day event with the formatted title and description
- If input contains "followup this": Use '#tool:google-calendar/create-event' to create the primary event plus a duplicate All-Day event exactly 1 week later for progressive follow-up

## Instructions
1. Analyze the context for the main topic and insight
2. Select/create the most appropriate taxonomy tag based on content relevance
3. Condense the context into a 3-5 word key insight or action
4. Generate the event title using [TAG] Topic - Key Insight format
5. Create a concise one-paragraph executive description summarizing the entry
6. Use the '#tool:google-calendar/create-event' to create the all-day event(s) with the generated title and description

## Output Format
- **Selected Tag:** [TAG]
- **Key Insight:** 3-5 word phrase
- **Event Title:** [TAG] Topic - Key Insight
- **Description:** One-paragraph executive summary
- **Event Creation Status:** Confirmation of created events
