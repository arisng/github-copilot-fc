// Test-only stub of the @github/copilot-sdk/extension module (committed).
// Lets us import extension.mjs outside the CLI runtime so its HTTP server and
// canvas wiring can be exercised in automated tests. Not used at runtime —
// the real CLI injects its own SDK.
//
// Loaded via test/sdk-stub-loader.mjs (Node loader hook).

export function createCanvas(opts) {
  return { ...opts, kind: "canvas" };
}

export function joinSession(opts) {
  const calls = [];
  const session = {
    __opts: opts,
    __calls: calls,
    log: async () => {},
    send: async (payload) => { calls.push({ kind: "send", payload }); },
    on: () => () => {},
  };
  globalThis.__machinaTestSession = session;
  return session;
}

export const CanvasError = class CanvasError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
};
