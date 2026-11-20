// Node module-resolution loader hook that maps the CLI SDK specifier to the
// committed test stub (test/stubs/copilot-sdk-extension.mjs) when running tests
// outside the CLI runtime.
//
// Usage: node --experimental-loader ./test/sdk-stub-loader.mjs test/canvas.test.mjs

const STUB = new URL("./stubs/copilot-sdk-extension.mjs", import.meta.url).href;

export async function resolve(specifier, context, nextResolve) {
  if (specifier === "@github/copilot-sdk/extension") {
    return { url: STUB, shortCircuit: true };
  }
  return nextResolve(specifier, context);
}
