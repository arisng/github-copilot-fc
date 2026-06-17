const https = require('https');
const http = require('http');
const url = require('url');
const fs = require('fs');
const path = require('path');

const PORT = 3002;
const PORT_443 = 443;   // when run as admin, also listen here for clean URLs
const UPSTREAM = 'api.moonshot.ai';
const PFX_PASSPHRASE = 'proxy';
const DATA_DIR = path.join(process.env.USERPROFILE || process.env.HOME || '.', '.copilot', 'moonshot-proxy');

// Look for certs in the user data directory (~/.copilot/moonshot-proxy/)
const MOONSHOT_PFX = path.join(DATA_DIR, 'moonshot.pfx');
const DEV_PFX = path.join(DATA_DIR, 'cert.pfx');
const PFX_PATH = fs.existsSync(MOONSHOT_PFX) ? MOONSHOT_PFX : DEV_PFX;

if (!fs.existsSync(PFX_PATH)) {
  // Auto-generate from .NET dev cert as fallback
  const { execSync } = require('child_process');
  try {
    const certPfx = path.join(DATA_DIR, 'cert.pfx');
    if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
    execSync(`dotnet dev-certs https --export-path "${certPfx}" --password proxy --format Pfx`, { stdio: 'pipe' });
    console.log('[proxy] Generated cert from .NET dev cert');
  } catch (e) {
    console.error(`[proxy] No certificate found. Run setup-dns.ps1 first.`);
    console.error(`[proxy] Looked in: ${PFX_PATH}`);
    process.exit(1);
  }
  // Re-check
  if (!fs.existsSync(PFX_PATH)) {
    console.error(`[proxy] Certificate generation failed.`);
    process.exit(1);
  }
}

const options = {
  pfx: fs.readFileSync(PFX_PATH),
  passphrase: PFX_PASSPHRASE,
};

// Shared request handler for both ports
function onRequest(req, res) {
  // Add CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', '*');

  const parsed = url.parse(req.url);

  // Health check endpoint for quick status (run before CORS/OPTIONS check)
  if (req.method === 'GET' && (parsed.pathname === '/health' || parsed.pathname === '/')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', upstream: UPSTREAM, top_p_override: 0.95 }));
    return;
  }

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // Build upstream headers — exclude Content-Length; we'll recalculate it
  const upstreamHeaders = {};
  for (const [k, v] of Object.entries(req.headers)) {
    const lk = k.toLowerCase();
    if (!['host', 'content-length', 'transfer-encoding', 'proxy-connection', 'connection'].includes(lk)) {
      upstreamHeaders[k] = v;
    }
  }
  upstreamHeaders.host = UPSTREAM;

  const proxyReq = https.request({
    hostname: UPSTREAM,
    port: 443,
    path: parsed.path,
    method: req.method,
    headers: upstreamHeaders,
  }, (proxyRes) => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res);
  });

  // Buffer request body, modify top_p if needed, recalculate Content-Length
  let bodyChunks = [];
  req.on('data', (chunk) => bodyChunks.push(chunk));
  req.on('end', () => {
    const raw = Buffer.concat(bodyChunks).toString();
    let finalBody;
    try {
      const body = JSON.parse(raw);
      if (body.top_p !== undefined && body.top_p !== 0.95) {
        console.log(`[proxy] top_p: ${body.top_p} → 0.95`);
        body.top_p = 0.95;
        finalBody = JSON.stringify(body);
      } else {
        finalBody = raw; // unchanged
      }
    } catch {
      finalBody = raw;
    }
    // Set correct Content-Length for the actual body being sent
    proxyReq.setHeader('Content-Length', Buffer.byteLength(finalBody, 'utf-8'));
    proxyReq.write(finalBody);
    proxyReq.end();
  });

  req.on('error', (e) => {
    console.error(`[proxy] Request error: ${e.message}`);
    if (!res.headersSent) res.writeHead(500);
    res.end();
  });
  proxyReq.on('error', (e) => {
    console.error(`[proxy] Upstream error: ${e.message}`);
    if (!res.headersSent) res.writeHead(502);
    res.end();
  });
}

// Create two servers sharing the same request handler for dual-port binding
function createServer(port) {
  const s = https.createServer(options, onRequest);
  s.listen(port, () => console.log(`[proxy] Listening on https://moonshot.local${port === 443 ? '' : ':' + port}`));
  s.on('error', (e) => {
    if (e.code === 'EACCES' || e.code === 'EADDRINUSE') {
      console.log(`[proxy] Port ${port} not available (${e.code === 'EACCES' ? 'need admin' : 'in use'})`);
    }
  });
}

createServer(PORT);       // always: moonshot.local:3002
createServer(PORT_443);   // if admin: moonshot.local (clean URL)

console.log(`[proxy] Moonshot top_p fix proxy`);
console.log(`[proxy] Forwards to https://${UPSTREAM}`);
console.log(`[proxy] Overrides top_p → 0.95`);
