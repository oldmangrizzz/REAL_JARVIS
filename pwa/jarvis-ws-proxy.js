#!/usr/bin/env node
// jarvis-ws-proxy.js
// WebSocket-to-TCP proxy: bridges browser PWA to Jarvis TCP tunnel server.
// Browser clients connect via WS; this proxy forwards to the TCP tunnel.
// Usage: node jarvis-ws-proxy.js [--tunnel-host 127.0.0.1] [--tunnel-port 9443] [--ws-port 9444]
//
// CarPlay integration: this proxy also exposes a /carplay endpoint that
// forwards MediaSession metadata, enabling basic now-playing controls
// on CarPlay dashboards via the PWA in Safari.

const net = require('net');
const http = require('http');
const { WebSocketServer, WebSocket } = require('ws');

const args = process.argv.slice(2);
function getArg(name, def) {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : def;
}

const TUNNEL_HOST = getArg('--tunnel-host', '127.0.0.1');
const TUNNEL_PORT = parseInt(getArg('--tunnel-port', '9443'));
const WS_PORT = parseInt(getArg('--ws-port', '9444'));

// HTTP server for health + CarPlay metadata bridge
const httpServer = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', tunnel: `${TUNNEL_HOST}:${TUNNEL_PORT}`, clients: wss.clients.size }));
    return;
  }
  if (req.url === '/carplay' && req.method === 'POST') {
    // CarPlay now-playing metadata from PWA
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
  console.log(`[+] WS client connected (total: ${wss.clients.size})`);

  // Open a TCP connection to the tunnel server for this WS client
  const tcp = net.createConnection({ host: TUNNEL_HOST, port: TUNNEL_PORT }, () => {
    console.log('[+] TCP tunnel connected');
  });

  let tcpBuffer = Buffer.alloc(0);

  tcp.on('data', (chunk) => {
    tcpBuffer = Buffer.concat([tcpBuffer, chunk]);
    // Split on 0x0A (newline) — same protocol as tunnel
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
    console.log('[-] TCP tunnel closed');
    if (ws.readyState === WebSocket.OPEN) ws.close();
  });

  tcp.on('error', (err) => {
    console.error('[!] TCP tunnel error:', err.message);
    if (ws.readyState === WebSocket.OPEN) ws.close();
  });

  // WS → TCP: forward messages, appending newline
  ws.on('message', (raw) => {
    const msg = typeof raw === 'string' ? raw : raw.toString('utf-8');
    // Strip trailing newlines from client, add exactly one
    const line = msg.replace(/\n+$/, '') + '\n';
    if (!tcp.destroyed) tcp.write(line);
  });

  ws.on('close', () => {
    console.log(`[-] WS client disconnected (total: ${wss.clients.size})`);
    if (!tcp.destroyed) tcp.destroy();
  });

  ws.on('error', (err) => {
    console.error('[!] WS client error:', err.message);
    if (!tcp.destroyed) tcp.destroy();
  });
});

httpServer.listen(WS_PORT, () => {
  console.log(`JARVIS WS Proxy listening on ws://localhost:${WS_PORT}`);
  console.log(`  → bridging to TCP tunnel at ${TUNNEL_HOST}:${TUNNEL_PORT}`);
  console.log(`  → CarPlay metadata at http://localhost:${WS_PORT}/carplay`);
  console.log(`  → Health check at http://localhost:${WS_PORT}/health`);
});