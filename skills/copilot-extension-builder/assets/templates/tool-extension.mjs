// Extension: {{EXTENSION_NAME}}
// {{EXTENSION_DESCRIPTION}}
// Adds a {{TOOL_NAME}} tool for Copilot

import { joinSession } from "@github/copilot-sdk/extension";

const session = await joinSession({
    tools: [
        {
            name: "{{TOOL_NAME}}",
            description: "{{TOOL_DESCRIPTION}}",
            skipPermission: false,  // true skips per-call prompts (one-time grant) — read-only tools only
            defer: "never",              // Always visible to agent
            parameters: {
                type: "object",
                properties: {
                    // {{PARAMETERS_DEFINITION}}
                },
                required: [],
            },
            handler: async (args, invocation) => {
                // {{HANDLER_IMPLEMENTATION}}
                // args contains the parameter values
                // invocation contains { sessionId, toolCallId, toolName }
                return "{{RESULT_MESSAGE}}";
            },
        },
    ],
});

// Event subscriptions (optional)
// session.on("tool.execution_start", (event) => { ... });
// session.on("tool.execution_complete", (event) => { ... });
