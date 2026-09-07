// Minimal server for playwright-cli smoke testing.
// Starts the simulator app on a fixed port and keeps it alive.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const appHtml = fs.readFileSync(path.join(__dirname, "..", "simulator", "app.html"), "utf8");
const engineJs = fs.readFileSync(path.join(__dirname, "..", "machine-simulator.mjs"), "utf8");
const sampleMachine = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "simulator", "samples", "machina-order.json"), "utf8")
);

const PORT = 18923;
const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://127.0.0.1");
  if (url.pathname === "/") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(appHtml);
    return;
  }
  if (url.pathname === "/machine-simulator.mjs") {
    res.writeHead(200, { "Content-Type": "text/javascript; charset=utf-8" });
    res.end(engineJs);
    return;
  }
  if (url.pathname === "/events") {
    res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" });
    res.write(":ok\n\n");
    res.on("close", () => {});
    return;
  }
  if (url.pathname === "/state") {
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: true, machine: null, compliance: null, replay: null, runHistory: [] }));
    return;
  }
  if (url.pathname === "/runs") {
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: true, runs: [] }));
    return;
  }
  if (url.pathname === "/sample-machine") {
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify(sampleMachine));
    return;
  }
  res.writeHead(404);
  res.end("Not found");
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`SMOKE_SERVER_URL=http://127.0.0.1:${PORT}`);
  console.log(`Server running on http://127.0.0.1:${PORT}`);
});
