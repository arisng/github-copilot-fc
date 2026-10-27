// Extension: {{EXTENSION_NAME}}
// {{EXTENSION_DESCRIPTION}}
// Adds a /{{COMMAND_NAME}} slash command

import { joinSession } from "@github/copilot-sdk/extension";

let state = {
    // {{STATE_DEFINITION}}
};

const session = await joinSession({
    commands: [
        {
            name: "{{COMMAND_NAME}}",
            description: "{{COMMAND_DESCRIPTION}}",
            handler: async (ctx) => {
                const arg = (ctx.args ?? "").trim();

                // Handle sub-commands (e.g., /command start, /command stop)
                if (arg === "start") {
                    // {{START_HANDLER}}
                    await session.log("{{START_MESSAGE}}", { level: "info" });
                    return;
                }

                if (arg === "stop") {
                    // {{STOP_HANDLER}}
                    await session.log("{{STOP_MESSAGE}}", { level: "info" });
                    return;
                }

                // Default handler
                // {{DEFAULT_HANDLER}}
                await session.log("{{DEFAULT_MESSAGE}}", { level: "info" });
            },
        },
    ],
});

// Event subscriptions (optional)
// session.on("assistant.usage", (event) => { ... });
