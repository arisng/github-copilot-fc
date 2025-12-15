#!/usr/bin/env python3
"""
Agent Evaluation Tool for Copilot FC
Performs deterministic agent evaluation based on query analysis.
"""

import json
import sys
import re
from typing import Dict, List, Tuple

class AgentEvaluator:
    def __init__(self):
        self.agents = {
            "Diataxis-Documentation-Expert": {
                "description": "Specialized agent for creating and organizing documentation using the Diátaxis framework",
                "keywords": ["documentation", "docs", "diataxis", "tutorial", "guide", "readme", "api docs"],
                "relevance_score": 0
            },
            "Generic-Research-Agent": {
                "description": "Expert researcher delivering validated, implementation-ready findings across any domain using available tools",
                "keywords": ["research", "investigate", "find", "analyze", "study", "explore", "discover"],
                "relevance_score": 0
            },
            "Git-Committer": {
                "description": "Analyzes all changes (staged and unstaged), groups them into logical commits, and guides you through committing with conventional messages",
                "keywords": ["commit", "git", "version control", "changes", "staging", "push", "merge"],
                "relevance_score": 0
            },
            "Instruction-Writer": {
                "description": "Creates path-specific GitHub Copilot `*.instructions.md` files that follow the official frontmatter (`applyTo`) format, include examples, and validate common glob targets",
                "keywords": ["instruction", "guideline", "rule", "coding standard", "best practice", "copilot", "instruction file"],
                "relevance_score": 0
            },
            "Issue-Writer": {
                "description": "Drafts punchy, one-page technical documents (Issues, Features, RFCs, ADRs, Work Items) in the _docs/issues/ folder",
                "keywords": ["issue", "feature", "rfc", "adr", "work item", "bug", "task", "documentation"],
                "relevance_score": 0
            },
            "Knowledge-Graph-Agent": {
                "description": "Generic sub-agent for Knowledge Graph memory management - handles entity resolution, relation mapping, and context retrieval for any parent agent",
                "keywords": ["knowledge", "graph", "memory", "entity", "relation", "context", "data structure"],
                "relevance_score": 0
            },
            "Mermaid-Agent": {
                "description": "Generate, validate, and render Mermaid diagrams from natural language descriptions",
                "keywords": ["diagram", "mermaid", "flowchart", "chart", "graph", "visual", "uml"],
                "relevance_score": 0
            },
            "Meta-Agent": {
                "description": "Expert architect for creating VS Code Custom Agents (.agent.md files)",
                "keywords": ["agent", "create", "custom agent", "persona", "tool", "meta", "architecture"],
                "relevance_score": 0
            },
            "PM-Changelog": {
                "description": "Generates monthly changelog summaries for non-tech stakeholders from weekly raw changelogs",
                "keywords": ["changelog", "release", "summary", "monthly", "stakeholder", "communication"],
                "relevance_score": 0
            }
        }

    def evaluate_query(self, query: str) -> Dict:
        """
        Evaluate all agents against the query using keyword matching and scoring.
        Returns structured evaluation results.
        """
        query_lower = query.lower()

        evaluations = {}
        activated_agents = []

        for agent_name, agent_data in self.agents.items():
            # Keyword matching
            keyword_matches = 0
            for keyword in agent_data["keywords"]:
                if keyword.lower() in query_lower:
                    keyword_matches += 1

            # Calculate relevance score (0-10)
            base_score = min(keyword_matches * 2, 6)  # Max 6 from keywords

            # Boost for exact phrase matches
            for keyword in agent_data["keywords"]:
                if re.search(r'\b' + re.escape(keyword.lower()) + r'\b', query_lower):
                    base_score += 2

            # Context-aware scoring
            if "create" in query_lower and agent_name in ["Meta-Agent", "Instruction-Writer", "Issue-Writer"]:
                base_score += 2
            if "document" in query_lower and agent_name == "Diataxis-Documentation-Expert":
                base_score += 2
            if "research" in query_lower or "find" in query_lower and agent_name == "Generic-Research-Agent":
                base_score += 2

            relevance_score = min(base_score, 10)
            agent_data["relevance_score"] = relevance_score

            # Determine YES/NO based on threshold
            is_relevant = relevance_score >= 5  # Threshold for activation

            evaluations[agent_name] = {
                "yes_no": "YES" if is_relevant else "NO",
                "reasoning": self._generate_reasoning(agent_name, relevance_score, keyword_matches),
                "relevance_score": relevance_score,
                "keyword_matches": keyword_matches
            }

            if is_relevant:
                activated_agents.append(agent_name)

        return {
            "query": query,
            "evaluations": evaluations,
            "activated_agents": activated_agents,
            "total_agents_evaluated": len(self.agents),
            "activation_count": len(activated_agents)
        }

    def _generate_reasoning(self, agent_name: str, score: int, keyword_matches: int) -> str:
        """Generate deterministic reasoning based on scoring."""
        if score >= 8:
            return f"High relevance ({score}/10) - strong keyword match ({keyword_matches}) and contextual fit"
        elif score >= 5:
            return f"Moderate relevance ({score}/10) - keyword match ({keyword_matches}) detected"
        else:
            return f"Low relevance ({score}/10) - minimal keyword overlap ({keyword_matches})"

def main():
    """Main entry point for the evaluation tool."""
    if len(sys.argv) < 2:
        print(json.dumps({
            "error": "Query required",
            "usage": "python agent_evaluator.py 'your query here'"
        }))
        sys.exit(1)

    query = sys.argv[1]
    evaluator = AgentEvaluator()
    result = evaluator.evaluate_query(query)

    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()