// Extension: {{EXTENSION_NAME}}
// {{EXTENSION_DESCRIPTION}}
// Mixed extension with tools, commands, and canvases

import http from "node:http";
import { createCanvas, joinSession, CanvasError } from "@github/copilot-sdk/extension";

// --- Shared State ---
const state = {
    // {{SHARED_STATE}}
    toolCount: 0,
    values: new Map(),
};

// --- HTTP / SSE Server (for canvas UI) ---
const instances = new Map();

function getInstance(instanceId) {
    let inst = instances.get(instanceId);
    if (!inst) {
        inst = { state: {}, sseClients: new Set() };
        instances.set(instanceId, inst);
    }
    return inst;
}

const server = http.createServer((req, res) => {
    // {{HTTP_SERVER_IMPLEMENTATION}}
    res.end("{{PLACEHOLDER}}");
});
server.listen(0, "127.0.0.1");
const port = server.address().port;

// --- Canvas ---
const canvas = createCanvas({
    id: "{{CANVAS_ID}}",
    displayName: "{{CANVAS_NAME}}",
    description: "{{CANVAS_DESCRIPTION}}",
    actions: [
        // {{CANVAS_ACTIONS}}
    ],
    open: async (ctx) => ({
        url: `http://127.0.0.1:${port}?instance=${ctx.instanceId}`,
        title: "{{CANVAS_NAME}}",
        status: "Ready",
    }),
});

const session = await joinSession({
    tools: [
        {
            name: "{{TOOL_NAME}}",
            description: "{{TOOL_DESCRIPTION}}",
            skipPermission: true,
            parameters: {
                type: "object",
                properties: {
                    // {{TOOL_PARAMETERS}}
                },
                required: [],
            },
            handler: async (args) => {
                state.toolCount++;
                // {{TOOL_HANDLER}}
                return "{{RESULT_MESSAGE}}";
            },
        },
    ],
    commands: [
        {
            name: "{{COMMAND_NAME}}",
            description: "{{COMMAND_DESCRIPTION}}",
            handler: async (ctx) => {
                const arg = (ctx.args ?? "").trim();
                // {{COMMAND_HANDLER}}
                await session.log("{{MESSAGE}}", { level: "info" });
            },
        },
    ],
    canvases: [canvas],
    requestCanvasRenderer: true,
});
