#!/usr/bin/env node
// jarvis-ws-proxy.js
// WebSocket-to-TCP proxy: bridges browser PWA to Jarvis TCP tunnel server.
// Browser clients connect via WS; this proxy forwards to the TCP tunnel.
// AUTH: Challenge-response using shared secret. Client must send the
//       secret within 5 seconds or the connection is dropped.
// Usage: node jarvis-ws-proxy.js [--tunnel-host ...] [--tunnel-port 9443] [--ws-port 9444]
//
// CarPlay integration: this proxy also exposes a /carplay endpoint that
// forwards MediaSession metadata, enabling basic now-playing controls
// on CarPlay dashboards via the PWA in Safari.

const net = require('net');
const http = require('http');
const crypto = require('crypto');
const { WebSocketServer, WebSocket } = require('ws');

const args = process.argv.slice(2);
function getArg(name, def) {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : def;
}

const SHARED_SECRET = process.env.SHARED_SECRET || 'changeme-jarvis-secret-2024';
const AUTH_TIMEOUT_MS = 5000;
const TUNNEL_HOST = process.env.TUNNEL_HOST || getArg('--tunnel-host', 'charlie.grizzlymedicine.icu');
const TUNNEL_PORT = parseInt(process.env.TUNNEL_PORT || getArg('--tunnel-port', '9443'));
const WS_PORT = parseInt(process.env.WS_PORT || getArg('--ws-port', '9444'));

// --- Timing-safe string comparison ------------------------------------------
function timingSafeEqual(a, b) {
  const bufA = Buffer.from(String(a), 'utf-8');
  const bufB = Buffer.from(String(b), 'utf-8');
  if (bufA.length !== bufB.length) {
    crypto.timingSafeEqual(bufA, bufA); // burn same time
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

// HTTP server for health + CarPlay metadata bridge
const httpServer = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', tunnel: `${TUNNEL_HOST}:${TUNNEL_PORT}`, clients: wss.clients.size }));
    return;
  }
  if (req.url === '/carplay' && req.method === 'POST') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        carplayMeta = JSON.parse(body);
        res.writeHead(200);
        res.end('OK');
      } catch {
        res.writeHead(400);
        res.end('Bad JSON');
      }
    });
    return;
  }
  if (req.url === '/carplay' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(carplayMeta || {}));
    return;
  }
  res.writeHead(404);
  res.end('Not found');
});

let carplayMeta = {};

const wss = new WebSocketServer({ server: httpServer });

wss.on('connection', (ws) => {
  const clientIP = ws._socket?.remoteAddress || 'unknown';
  console.log(`[+] WS client from ${clientIP} — awaiting auth (total: ${wss.clients.size})`);

  // --- Authentication state -------------------------------------------------
  let authenticated = false;

  const authTimer = setTimeout(() => {
    console.log(`[!] Auth timeout for ${clientIP} — closing`);
    try { ws.send(JSON.stringify({ type: 'auth', status: 'timeout' })); } catch {}
    ws.terminate();
  }, AUTH_TIMEOUT_MS);

  // Send auth challenge
  ws.send(JSON.stringify({ type: 'auth_challenge', message: 'Send shared secret to authenticate' }));

  // --- TCP connection (only opened after auth) ------------------------------
  let tcp = null;
  let tcpBuffer = Buffer.alloc(0);

  function openTunnel() {
    tcp = net.createConnection({ host: TUNNEL_HOST, port: TUNNEL_PORT }, () => {
      console.log(`[+] TCP tunnel connected for ${clientIP}`);
    });

    tcp.on('data', (chunk) => {
      tcpBuffer = Buffer.concat([tcpBuffer, chunk]);
      while (true) {
        const idx = tcpBuffer.indexOf(0x0A);
        if (idx === -1) break;
        const line = tcpBuffer.slice(0, idx).toString('utf-8');
        tcpBuffer = tcpBuffer.slice(idx + 1);
        if (line.trim() && ws.readyState === WebSocket.OPEN) {
          ws.send(line);
        }
      }
    });

    tcp.on('close', () => {
      console.log(`[-] TCP tunnel closed for ${clientIP}`);
      if (ws.readyState === WebSocket.OPEN) ws.close();
    });

    tcp.on('error', (err) => {
      console.error(`[!] TCP tunnel error: ${err.message}`);
      if (ws.readyState === WebSocket.OPEN) ws.close();
    });
  }

  // --- Message handler ------------------------------------------------------
  ws.on('message', (raw) => {
    const msg = typeof raw === 'string' ? raw : raw.toString('utf-8');

    if (!authenticated) {
      let parsed;
      try { parsed = JSON.parse(msg); } catch { parsed = null; }

      const candidate = parsed && parsed.type === 'auth' ? parsed.secret : msg;
      if (timingSafeEqual(candidate, SHARED_SECRET)) {
        authenticated = true;
        clearTimeout(authTimer);
        console.log(`[+] Auth succeeded for ${clientIP}`);
        ws.send(JSON.stringify({ type: 'auth', status: 'ok' }));
        openTunnel();
      } else {
        clearTimeout(authTimer);
        console.log(`[!] Auth FAILED for ${clientIP} — closing`);
        ws.send(JSON.stringify({ type: 'auth', status: 'denied' }));
        ws.terminate();
      }
      return;
    }

    // Post-auth: forward to TCP
    const line = msg.replace(/\n+$/, '') + '\n';
    if (tcp && !tcp.destroyed) tcp.write(line);
  });

  ws.on('close', () => {
    clearTimeout(authTimer);
    console.log(`[-] WS client ${clientIP} disconnected (total: ${wss.clients.size - 1})`);
    if (tcp && !tcp.destroyed) tcp.destroy();
  });

  ws.on('error', (err) => {
    clearTimeout(authTimer);
    console.error(`[!] WS client error: ${err.message}`);
    if (tcp && !tcp.destroyed) tcp.destroy();
  });
});

httpServer.listen(WS_PORT, () => {
  console.log(`JARVIS WS Proxy listening on ws://localhost:${WS_PORT}`);
  console.log(`  → bridging to TCP tunnel at ${TUNNEL_HOST}:${TUNNEL_PORT}`);
  console.log(`  Auth: shared-secret required (timeout ${AUTH_TIMEOUT_MS}ms)`);
  console.log(`  → CarPlay metadata at http://localhost:${WS_PORT}/carplay`);
  console.log(`  → Health check at http://localhost:${WS_PORT}/health`);
});