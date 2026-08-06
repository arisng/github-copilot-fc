// Extension: {{EXTENSION_NAME}}
// {{EXTENSION_DESCRIPTION}}
// Adds a {{CANVAS_NAME}} interactive canvas

import http from "node:http";
import { createCanvas, joinSession, CanvasError } from "@github/copilot-sdk/extension";

// --- State Management ---
// Per-instance state, keyed by instanceId
const instances = new Map();

function getInstance(instanceId) {
    let inst = instances.get(instanceId);
    if (!inst) {
        inst = {
            state: { /* {{INITIAL_STATE}} */ },
            sseClients: new Set(),
            cleanup: [],
        };
        instances.set(instanceId, inst);
    }
    return inst;
}

function broadcast(entry, event, data) {
    for (const res of entry.sseClients) {
        res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    }
}

// --- HTTP Server ---
const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, "http://127.0.0.1");
    const instanceId = url.searchParams.get("instance");
    const entry = getInstance(instanceId);

    // SSE endpoint for real-time updates
    if (url.pathname === "/events") {
        res.writeHead(200, {
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            Connection: "keep-alive",
        });
        entry.sseClients.add(res);
        res.on("close", () => entry.sseClients.delete(res));
        return;
    }

    // API endpoint for user interactions
    if (url.pathname === "/api/action" && req.method === "POST") {
        let body = "";
        req.on("data", (chunk) => { body += chunk; });
        req.on("end", () => {
            // {{API_HANDLER_IMPLEMENTATION}}
            res.end(JSON.stringify({ ok: true }));
        });
        return;
    }

    // Serve HTML UI
    res.writeHead(200, { "Content-Type": "text/html" });
    res.end(`<!DOCTYPE html>
<html><head><title>{{CANVAS_NAME}}</title></head><body>
<div id="app">{{PLACEHOLDER_UI}}</div>
<script>
// SSE connection for live updates
const evtSource = new EventSource("/events?instance=${instanceId}");
evtSource.addEventListener("update", (e) => {
    const data = JSON.parse(e.data);
    // {{SSE_UPDATE_HANDLER}}
});
</script>
</body></html>`);
});

server.listen(0, "127.0.0.1"); // Random port
const port = server.address().port;

// --- Canvas Actions ---
const canvas = createCanvas({
    id: "{{CANVAS_ID}}",
    displayName: "{{CANVAS_NAME}}",
    description: "{{CANVAS_DESCRIPTION}}",
    inputSchema: {
        type: "object",
        properties: {
            // {{OPEN_INPUT_SCHEMA}}
        },
    },
    actions: [
        {
            name: "{{ACTION_NAME}}",
            description: "{{ACTION_DESCRIPTION}}",
            inputSchema: {
                type: "object",
                properties: {
                    // {{ACTION_INPUT_SCHEMA}}
                },
                required: [],
            },
            handler: async ({ instanceId, input }) => {
                const entry = getInstance(instanceId);
                // {{ACTION_HANDLER_IMPLEMENTATION}}
                broadcast(entry, "update", { /* data */ });
                return { /* result for agent */ };
            },
        },
    ],
    open: async (ctx) => {
        const entry = getInstance(ctx.instanceId);
        return {
            url: `http://127.0.0.1:${port}?instance=${ctx.instanceId}`,
            title: "{{CANVAS_NAME}}",
            status: "Ready",
        };
    },
    onClose: async (ctx) => {
        const entry = instances.get(ctx.instanceId);
        if (entry) {
            entry.cleanup.forEach((fn) => fn());
            instances.delete(ctx.instanceId);
        }
    },
});

const session = await joinSession({
    canvases: [canvas],
    requestCanvasRenderer: true,
});
