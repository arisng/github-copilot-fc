#!/usr/bin/env node
// Manually pre-start the machina-simulator HTTP server on the fixed port
// (127.0.0.1:7750) WITHOUT a Copilot session. Later Copilot sessions detect
// the port already listening, skip auto-start, and attach as secondaries —
// their agents' open_canvas / action calls delegate to this process.
//
// Usage:
//   node scripts/start-standalone.mjs
//
// Safe to run twice: if the port is already in use, this exits immediately
// with an "already running" message (exit code 0).
process.env.MACHINA_STANDALONE = "1";
await import(new URL("../extension.mjs", import.meta.url).href);
