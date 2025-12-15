# Claude Code Skills Activation Research: Hierarchical Agent Activation for GitHub Copilot

## Document Metadata

- **Title**: Claude Code Skills Activation Research: Hierarchical Agent Activation for GitHub Copilot
- **Date**: December 15, 2025
- **Authors**: GitHub Copilot FC Team
- **Purpose**: Research analysis and implementation of hierarchical agent/skill activation mechanisms
- **Scope**: Two-tier activation system (Copilot agents → Claude skills)
- **Related Files**:
  - `instructions/agent-forced-eval.instructions.md`
  - `agents/agent-evaluator.agent.md`
  - `agents/agent-evaluator-tool.agent.md`
  - `scripts/agent_evaluator.py`
  - Article: https://scottspence.com/posts/how-to-make-claude-code-skills-activate-reliably

## Executive Summary

This research analyzes Scott Spence's article on Claude Code skills activation and adapts the proven "Forced Eval Hook" approach for a **hierarchical activation system** in GitHub Copilot. While the original work focused on Claude skills, our implementation creates a two-tier architecture:

**Tier 1**: GitHub Copilot Custom Agent Activation (current work)
**Tier 2**: Claude Skills Activation by Activated Copilot Agents (future work)

This hierarchical approach ensures that the appropriate Copilot agent is first activated, then that agent can intelligently activate relevant Claude skills for specialized task execution.

## Hierarchical Activation Architecture

### Two-Tier System Design

**Tier 1: Copilot Agent Activation (Current Implementation)**
- **Purpose**: Ensure the right Copilot custom agent is activated for the user's query
- **Mechanism**: Forced evaluation hooks, tool-enhanced agents, instruction-based guidance
- **Scope**: 9 available Copilot agents (Diataxis, Generic-Research, Git-Committer, etc.)
- **Activation Methods**: 
  - Global instructions (`agent-forced-eval.instructions.md`)
  - Manual agent invocation (`@agent-evaluator`, `@agent-evaluator-tool`)
  - Tool-enhanced deterministic evaluation

**Tier 2: Claude Skills Activation (Future Implementation)**
- **Purpose**: Once appropriate Copilot agent is activated, enable it to call relevant Claude skills
- **Mechanism**: Copilot agent evaluates and activates Claude skills using similar forced eval patterns
- **Scope**: Claude Code skills (as documented in original article)
- **Integration**: Copilot agents become "skill orchestrators" that manage Claude skill activation

### Architecture Benefits

1. **Intelligent Orchestration**: Copilot agents make smart decisions about which Claude skills to activate
2. **Context Preservation**: Copilot agents maintain conversation context when calling Claude skills
3. **Fallback Mechanisms**: If Claude skills fail, Copilot agents can provide alternatives
4. **Unified Interface**: Users interact with Copilot agents, which transparently manage Claude skill activation

## Original Article Analysis

### Article Overview

**Title**: "How to Make Claude Code Skills Activate Reliably"
**Author**: Scott Spence
**Publication Date**: November 16, 2025
**URL**: https://scottspence.com/posts/how-to-make-claude-code-skills-activate-reliably

### Core Problem Statement

Claude Code skills are designed to activate autonomously based on their descriptions, but in practice, Claude often ignores them entirely. The author found that simple instruction-based approaches yielded only 20% activation rates, essentially a coin flip.

### Research Methodology

The author conducted rigorous testing with:
- **Test Harness**: SQLite database tracking results, synthetic and manual testing
- **Skills Tested**: 4 SvelteKit-specific skills (runes, data flow, structure, remote functions)
- **Test Prompts**: 5 common development scenarios, run 10 times each
- **Hook Types**: 4 different activation approaches compared

### Key Findings

#### Performance Results

| Hook Type          | Activation Rate | Cost     | Latency  | Notes                 |
| ------------------ | --------------- | -------- | -------- | --------------------- |
| No Hook            | 20%             | Baseline | Baseline | Passive approach      |
| Simple Instruction | 20%             | $0.29    | 6.7s     | Coin flip reliability |
| Forced Eval Hook   | 84%             | $0.34    | 7.2s     | Most consistent       |
| LLM Eval Hook      | 80%             | $0.30    | 6.0s     | Cheaper, variable     |

#### Hook Analysis

**Simple Instruction (20% success)**:
- Passive suggestion: "If prompt matches keywords, use Skill(skill-name)"
- Claude acknowledges but ignores the instruction
- Fails completely on multi-skill prompts

**Forced Eval Hook (84% success)**:
- Three-step commitment mechanism:
  1. **EVALUATE**: Explicit YES/NO for each skill with reasoning
  2. **ACTIVATE**: Use Skill() tool calls
  3. **IMPLEMENT**: Only then proceed with response
- Uses aggressive language ("MANDATORY", "CRITICAL", "WORTHLESS")
- Creates psychological commitment once evaluation is stated

**LLM Eval Hook (80% success)**:
- Pre-evaluates skills using Claude API
- 10% cheaper, 17% faster than forced eval
- Can fail spectacularly on complex prompts (0% on multi-skill scenarios)

### Critical Insights

1. **Commitment Mechanism**: Passive suggestions fail; explicit evaluation + commitment succeeds
2. **Multi-skill Complexity**: Simple approaches break down with complex, multi-domain prompts
3. **Cost-Reliability Trade-off**: Forced eval prioritizes consistency over cost
4. **Language Matters**: Aggressive terminology prevents instruction dismissal

## Adaptation Analysis for GitHub Copilot

### Sequential Thinking Analysis Results

Using the `mcp_sequentialthi_sequentialthinking` tool, we analyzed the adaptation requirements:

#### Key Differences Identified

- **Activation Mechanism**: Claude uses explicit `Skill()` tool calls; Copilot relies on implicit description matching and instruction guidance
- **Architecture**: Claude has direct tool integration; Copilot agents provide contextual knowledge through descriptions
- **Commitment Creation**: Need to translate tool-based activation to instruction-based incorporation

#### Proposed Solution Architecture

- **Global Instruction**: `agent-forced-eval.instructions.md` with `applyTo: '**'`
- **Three-Step Process**: Adapted for Copilot's agent system
- **Agent List**: All 9 available agents included for evaluation

#### Implementation Challenges

- **No Explicit Activation**: "Activation" is implicit through referencing agent expertise
- **Performance Impact**: Global application may increase response verbosity
- **Compliance Uncertainty**: Copilot may not follow instructions as rigidly as Claude

#### Alternative Approaches Considered

1. **Dedicated Agent**: Create "Agent-Evaluator" agent for evaluation
2. **Selective Application**: Apply to specific file patterns rather than global
3. **LLM-Style Pre-evaluation**: Use subagents for pre-evaluation

### Recommended Approach

**Primary**: Global forced eval instruction (consistency with proven Claude approach)
**Backup**: Agent-Evaluator agent for complex scenarios

## Implementation Details

### Created Files
- **Instruction File**: `instructions/agent-forced-eval.instructions.md`
- **Published**: Via `publish-instructions.ps1` script to VS Code synced settings

### Instruction Structure
```markdown
---
name: agent-forced-eval
description: 'Forces GitHub Copilot to evaluate and activate relevant custom agents before responding to queries'
applyTo: '**'
---

# Agent Forced Evaluation Hook

## ⚠️ LIMITATION NOTICE: NON-DETERMINISTIC ENFORCEMENT

**IMPORTANT**: Unlike Claude Code hooks which are deterministically executed, Copilot instructions are guidance only. This implementation provides strong behavioral incentives but cannot guarantee 100% compliance. For deterministic enforcement, consider VS Code extension development.

## CRITICAL INSTRUCTION - MANDATORY COMPLIANCE REQUIRED

**BEFORE responding to ANY user query or request, you MUST follow this exact three-step process.**

### Step 1 - EVALUATE: Agent Relevance Assessment
For EACH available agent, state YES/NO with brief reasoning...

### Step 2 - ACTIVATE: Agent Incorporation
For each YES agent, explicitly reference and incorporate their expertise...

### Step 3 - IMPLEMENT: Execute Response
Only AFTER Steps 1-2 may you proceed...
```

### Fundamental Limitation Discovered

**Non-Deterministic Enforcement**: The core limitation is that Copilot instructions are guidance, not enforced rules. While Claude Code hooks execute as code and can intercept/modify behavior deterministically, Copilot instructions rely on the AI model's compliance with contextual hints.

**Expected Compliance Rate**: Based on the Claude research (84% for forced eval), we anticipate 60-80% compliance, but this cannot be guaranteed like the Claude implementation.

### Alternative: Tool-Enhanced Deterministic Agent-Based Approach

To address the non-deterministic limitation, we created an enhanced version using **custom evaluation tools**:

- **Agent-Evaluator v2.0**: Tool-enhanced agent with mandatory tool usage
- **Custom Evaluation Tool**: `scripts/agent_evaluator.py` - Python script performing rule-based evaluation
- **Deterministic Logic**: Keyword matching, scoring algorithms, threshold-based decisions
- **Tool-First Protocol**: Agent MUST use the tool before any evaluation, making it deterministic

**Key Advantages**:
- **Code-Based Evaluation**: Rule-based scoring rather than LLM interpretation
- **Consistency**: Same query always produces identical results
- **Auditability**: Structured reasoning and scoring metrics
- **Tool Enforcement**: Agent is instructed to ALWAYS use the tool first

**Test Results**: Tool correctly identifies Mermaid-Agent and Meta-Agent for "Create a flowchart for my application architecture" query.

## Testing Setup: Parallel Agent Evaluation

To enable rigorous comparison testing, we created separate agent implementations:

### Available Test Agents

1. **agent-forced-eval.instructions.md**: Global instruction-based enforcement (automatic)
2. **agent-evaluator.agent.md**: Original agent-based evaluation (manual, instruction-following)
3. **agent-evaluator-tool.agent.md**: Pure tool-enhanced evaluation (manual, deterministic)

### Testing Protocol

- **Query Set**: Standardized test queries covering different agent domains
- **Parallel Execution**: Run same query through all three approaches
- **Metrics**: Activation accuracy, consistency, response quality
- **Comparison**: Determinism levels, reliability, usability

This setup allows systematic evaluation of enforcement approaches across the determinism spectrum.

## Enforcement Solutions by Deterministic Level (Ascending)

### 1. **Custom-Instruction-Based Enforcement** (Non-Deterministic)
- **Implementation**: `agent-forced-eval.instructions.md` with global `applyTo: '**'`
- **Mechanism**: Behavioral guidance and psychological incentives
- **Determinism Level**: Low (~60-80% compliance based on AI model adherence)
- **Activation**: Automatic on all queries
- **Pros**: Zero overhead, always applied
- **Cons**: Cannot guarantee compliance, relies on AI following instructions

### 2. **Custom-Agent-Based Enforcement** (Deterministic When Invoked)
- **Implementation**: `agent-evaluator.agent.md` v1.0
- **Mechanism**: Direct agent invocation with instruction-based evaluation
- **Determinism Level**: Medium (guaranteed execution, but evaluation relies on LLM following instructions)
- **Activation**: Manual invocation required
- **Pros**: Guaranteed execution when called, structured output
- **Cons**: Evaluation still depends on LLM instruction compliance

### Tool-Enhanced Custom-Agent-Based Enforcement (High Determinism)
- **Implementation**: `agent-evaluator-tool.agent.md` + `scripts/agent_evaluator.py`
- **Mechanism**: Pure tool-based evaluation with mandatory tool usage, zero LLM interpretation
- **Determinism Level**: High (code-based evaluation with algorithmic scoring)
- **Activation**: Manual invocation with strict tool enforcement
- **Pros**: Perfect consistency, full audit trail, algorithmic transparency
- **Cons**: Requires explicit invocation, tool dependency, no LLM flexibility

### 4. **Extension-Based Enforcement** (Fully Deterministic - Theoretical)
- **Implementation**: VS Code extension with code interception
- **Mechanism**: Native code execution that can intercept and modify Copilot behavior
- **Determinism Level**: 100% (like Claude Code hooks)
- **Activation**: Automatic via extension lifecycle
- **Pros**: True enforcement, can modify behavior before display
- **Cons**: Requires extension development, installation, maintenance

### Agent Coverage
The instruction evaluates all 9 available agents:
1. Diataxis-Documentation-Expert
2. Generic-Research-Agent
3. Git-Committer
4. Instruction-Writer
5. Issue-Writer
6. Knowledge-Graph-Agent
7. Mermaid-Agent
8. Meta-Agent
9. PM-Changelog

## Expected Outcomes

### Success Metrics

- **Agent Reference Rate**: Percentage of responses that reference relevant agents
- **Task Completion**: Success rate on agent-appropriate tasks
- **Response Relevance**: Quality of agent-specific guidance in responses

### Realistic Performance Expectations

- **Baseline**: ~20% (estimated based on Claude findings for passive approaches)
- **Target Range**: 60-80% (accounting for non-deterministic enforcement)
- **Best Case**: 84% (matching Claude forced eval results if compliance is high)
- **Measurement**: Compare responses with/without the instruction active, track over time

## Lessons Learned

### Technical Insights

1. **Commitment Psychology**: Explicit evaluation creates binding decisions
2. **Non-Deterministic Enforcement**: Copilot instructions provide guidance, not guarantees - unlike Claude's deterministic hooks
3. **Architecture Translation**: Tool-based systems can be adapted to instruction-based ones, but with reduced reliability
4. **Language Engineering**: Aggressive terminology prevents passive dismissal but cannot enforce compliance

### Implementation Lessons

1. **YAML Frontmatter**: Critical for Copilot instruction recognition
2. **Publishing Process**: Requires explicit publishing to synced settings
3. **Testing Strategy**: Need systematic measurement of activation rates
4. **Iterative Refinement**: Monitor performance and adjust scope/severity

### Research Methodology

1. **Tool Utilization**: `mcp_sequentialthi_sequentialthinking` enabled structured analysis
2. **Cross-Platform Learning**: Claude insights successfully adapted to Copilot
3. **Empirical Validation**: Testing framework approach should be replicated

## Future Directions

### Immediate Next Steps

1. **Testing Campaign**: Run systematic tests with various query types
2. **Performance Monitoring**: Track activation rates and response quality
3. **User Feedback**: Gather developer experience with the new workflow

### Potential Enhancements

1. **Selective Application**: Implement pattern-based activation for performance
2. **LLM Pre-evaluation**: Add API-based pre-filtering for cost optimization
3. **Agent-Evaluator Agent**: Create dedicated evaluation agent for complex scenarios
4. **Dynamic Agent Discovery**: Automatically detect and include new agents

### Research Extensions

1. **Cross-Platform Comparison**: Compare activation reliability across AI coding assistants
2. **Longitudinal Study**: Track activation rates over time as agents evolve
3. **User Experience Impact**: Study effects on developer productivity and satisfaction
4. **Optimization Research**: Explore more efficient evaluation mechanisms

## Conclusion

This research successfully adapted the proven Forced Eval Hook approach from Claude Code to establish a **hierarchical activation system** in GitHub Copilot. The implementation creates a two-tier architecture that first ensures appropriate Copilot agent activation, then enables those agents to intelligently orchestrate Claude skill activation.

**Current Status**: Tier 1 (Copilot Agent Activation) is fully implemented with multiple enforcement approaches:
- Instruction-based incentives (60-80% compliance)
- Agent-based evaluation (manual, medium determinism)
- Tool-enhanced evaluation (manual, high determinism)

**Future Vision**: Tier 2 (Claude Skills Activation) will extend this pattern where activated Copilot agents become skill orchestrators, applying the same forced evaluation principles to Claude skill activation.

The work demonstrates both the value of cross-platform learning and the power of hierarchical agent architectures. The hybrid approach (instruction incentives + tool-based guarantees) provides a robust foundation within Copilot's current limitations, with clear pathways for extending deterministic control to Claude skill orchestration.

## References

1. Spence, S. (2025). *How to Make Claude Code Skills Activate Reliably*. Retrieved from https://scottspence.com/posts/how-to-make-claude-code-skills-activate-reliably
2. GitHub Copilot FC Workspace Documentation
3. VS Code Custom Instructions Format Specification

---

*This document serves as a comprehensive reference for the Claude skills activation research and its Copilot adaptation. Use this for future iterations, agent development, and cross-platform AI assistant research.*
