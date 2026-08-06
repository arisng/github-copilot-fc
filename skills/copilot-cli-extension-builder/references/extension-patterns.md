# Copilot CLI Extension Patterns

Real-world patterns from `github/awesome-copilot` extensions.

## Pattern Overview

| Pattern | Extension | Description |
|---|---|---|
| **Canvas + HTTP/SSE** | All 19 extensions | Serve HTML UI on loopback HTTP with SSE for real-time updates |
| **Session Bridging** | `work-hub` | Canvas instructs agent via `sessionRef.send()` |
| **Bidirectional Agent** | `diagram-viewer` | User clicks → server prompts agent → agent uses canvas actions |
| **Session Hooks** | `repo-actions-hub` | Track workingDirectory across session lifecycle |
| **Live Event Subscription** | `token-pacman` | Subscribe to `assistant.usage` for real-time UI updates |
| **Basic Tool** | `session_tool_time` (official tutorial) | Simple tool tracking session metrics |
| **Basic Command** | `tokencount` (official tutorial) | Simple slash command with `/start` sub-command |

## Pattern 1: Canvas + HTTP/SSE (All Extensions)

Every canvas extension follows this architecture:

```
extension.mjs
└── imports (http, @github/copilot-sdk/extension)
└── HTTP server on 127.0.0.1:0
    ├── GET / → serve HTML UI
    ├── GET /events → SSE stream
    └── POST /api/* → user interaction handlers
└── createCanvas({ id, displayName, description, inputSchema, actions, open, onClose })
└── joinSession({ canvases: [canvas] })
```

**State management:** Use `Map<string, InstanceState>` keyed by `instanceId`.

```javascript
const servers = new Map();

const entry = {
    state: createState(),
    server: null,
    sseClients: new Set(),
    intervals: new Set(),
};
servers.set(instanceId, entry);
```

**SSE broadcast pattern:**
```javascript
function broadcast(entry, event, data) {
    for (const res of entry.sseClients) {
        res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    }
}
```

## Pattern 2: Session Bridging (work-hub)

Canvas instructs the agent to perform complex operations by sending prompts.

```javascript
let sessionRef = null;

// In an action handler:
async ({ instanceId, input }) => {
    await sessionRef.send({
        prompt: `The user wants to jump to a session. Use the "open_session" tool to navigate to session ${sessionId}. Do NOT explain in chat.`,
    });
    return { ok: true };
};

// Store sessionRef after joinSession:
sessionRef = await joinSession({ canvases: [canvas] });
```

**Use case:** Complex multi-step operations the canvas can't do alone (e.g., "jump to session", "cleanup sessions", "assign issue").

## Pattern 3: Bidirectional Agent Communication (diagram-viewer)

User interacts with the canvas UI → server sends prompt to agent → agent responds via canvas actions.

```javascript
// In HTTP POST handler (user clicks in iframe):
server.post("/api/click", async (req, res) => {
    const { nodeId } = await parseBody(req);
    await session.send({
        prompt: `The user clicked on "${nodeId}". Do NOT explain in chat. Use the render_diagram action with mode "push" to show a sub-diagram.`,
    });
    res.end(JSON.stringify({ ok: true }));
});
```

**Use case:** Interactive exploration where user actions in the canvas trigger agent responses.

## Pattern 4: Session Hooks for Context (repo-actions-hub)

Track working directory across session lifecycle events.

```javascript
let currentWorkingDirectory = null;

const session = await joinSession({
    hooks: {
        onSessionStart: async (input) => {
            if (input?.workingDirectory) {
                currentWorkingDirectory = input.workingDirectory;
            }
        },
        onUserPromptSubmitted: async (input) => {
            if (input?.workingDirectory) {
                currentWorkingDirectory = input.workingDirectory;
            }
        },
        onPreToolUse: async (input) => {
            if (input?.workingDirectory) {
                currentWorkingDirectory = input.workingDirectory;
            }
        },
    },
    canvases: [ /* ... */ ],
});
```

**Use case:** Extensions that need to know the current repo/directory context.

## Pattern 5: Live Event Subscription (token-pacman)

Subscribe to session events to update canvas state without agent polling.

```javascript
const session = await joinSession({
    canvases: [createCanvas({ /* ... */ })],
});

session.on("assistant.usage", (event) => {
    const { inputTokens = 0, outputTokens = 0 } = event.data ?? {};
    for (const entry of servers.values()) {
        entry.totalTokens += inputTokens + outputTokens;
        broadcast(entry, "usage_update", { total: entry.totalTokens });
    }
});
```

**Use case:** Real-time dashboards, token/credit trackers, live monitors.

## Pattern 6: External CLI Integration (repo-actions-hub)

Integrate with external CLIs like `gh` using `child_process.spawn`.

```javascript
import { spawn } from "node:child_process";

function runGh(args, options = {}) {
    return new Promise((resolve, reject) => {
        const child = spawn("gh", args, {
            stdio: ["pipe", "pipe", "pipe"],
            env: { ...process.env, GIT_TERMINAL_PROMPT: "0" },
            ...options,
        });
        let stdout = "", stderr = "";
        child.stdout.on("data", (d) => { stdout += d; });
        child.stderr.on("data", (d) => { stderr += d; });
        child.on("close", (code) => {
            if (code !== 0) reject(new Error(stderr));
            else resolve(JSON.parse(stdout));
        });
    });
}
```

**Use case:** Extensions that interact with GitHub CLI, Docker, or other CLIs.

## Pattern 7: Use session.rpc for Internal APIs (token-pacman)

Access internal session RPC methods for usage/quota data.

```javascript
// Get usage metrics
const metrics = await session.rpc.usage.getMetrics();
const nanoAiu = Number(metrics.totalNanoAiu) || 0;

// Get account quota
const result = await session.connection.sendRequest("account.getQuota", {});
const snap = result?.quotaSnapshots?.premium_interactions || {};
```

**Use case:** Extensions that need to report usage, quotas, or session stats.
