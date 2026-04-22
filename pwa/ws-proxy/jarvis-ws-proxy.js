#!/usr/bin/env node
// jarvis-ws-proxy.js — zero-dependency WebSocket-to-TCP proxy
// Uses Node.js built-in crypto for the WS handshake, no external deps.
// AUTH: Challenge-response using shared secret. Client must send the
//       secret within 5 seconds or the connection is dropped.
const net = require('net');
const http = require('http');
const crypto = require('crypto');

// --- Configuration -----------------------------------------------------------
const SHARED_SECRET = process.env.SHARED_SECRET;
if (!SHARED_SECRET) {
  console.error('FATAL: SHARED_SECRET environment variable not set');
  process.exit(1);
}
const AUTH_TIMEOUT_MS = 5000; // 5 seconds to authenticate
const TUNNEL_HOST = process.env.TUNNEL_HOST || 'charlie.grizzlymedicine.icu';
const TUNNEL_PORT = parseInt(process.env.TUNNEL_PORT || '9443');
const WS_PORT = parseInt(process.env.WS_PORT || '9444');

const WS_MAGIC = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

// --- Timing-safe string comparison ------------------------------------------
function timingSafeEqual(a, b) {
  // Convert both to same-length buffers so comparison is constant-time.
  // If lengths differ, we still compare to avoid leaking length info.
  const bufA = Buffer.from(String(a), 'utf-8');
  const bufB = Buffer.from(String(b), 'utf-8');
  if (bufA.length !== bufB.length) {
    // Still do a full comparison against itself to burn the same time,
    // then return false.
    crypto.timingSafeEqual(bufA, bufA);
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

// --- WS frame helpers -------------------------------------------------------
function hashKey(key) {
  return crypto.createHash('sha1').update(key + WS_MAGIC).digest('base64');
}

function decodeFrame(buf) {
  if (buf.length < 2) return null;
  const fin = (buf[0] & 0x80) !== 0;
  const opcode = buf[0] & 0x0F;
  let mask = (buf[1] & 0x80) !== 0;
  let len = buf[1] & 0x7F;
  let offset = 2;
  if (len === 126) { if (buf.length < 4) return null; len = buf.readUInt16BE(2); offset = 4; }
  else if (len === 127) { if (buf.length < 10) return null; len = Number(buf.readBigUInt64BE(2)); offset = 10; }
  if (buf.length < offset + (mask ? 4 : 0) + len) return null;
  let maskKey;
  if (mask) { maskKey = buf.slice(offset, offset + 4); offset += 4; }
  let data = buf.slice(offset, offset + len);
  if (mask) { for (let i = 0; i < data.length; i++) data[i] ^= maskKey[i & 3]; }
  return { fin, opcode, data, totalLen: offset + len };
}

function encodeFrame(data, opcode = 1) {
  const buf = Buffer.from(data);
  const frames = [];
  if (buf.length < 126) {
    frames.push(Buffer.from([0x80 | opcode, buf.length]));
  } else if (buf.length < 65536) {
    const h = Buffer.alloc(4); h.writeUInt16BE(buf.length, 2);
    frames.push(Buffer.from([0x80 | opcode, 126]), h);
  } else {
    const h = Buffer.alloc(10); h[0]=0;h[1]=0;h.writeBigUInt64BE(BigInt(buf.length),2);
    frames.push(Buffer.from([0x80 | opcode, 127]), h);
  }
  frames.push(buf);
  return Buffer.concat(frames);
}

const clients = new Set();

const httpServer = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', tunnel: `${TUNNEL_HOST}:${TUNNEL_PORT}`, clients: clients.size }));
  } else {
    res.writeHead(404); res.end('Not found');
  }
});

httpServer.on('upgrade', (req, socket) => {
  if (req.url !== '/' && req.url !== '/ws') {
    socket.destroy(); return;
  }
  const key = req.headers['sec-websocket-key'];
  if (!key) { socket.destroy(); return; }

  socket.write('HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${hashKey(key)}\r\n\r\n`);

  const clientIP = req.socket.remoteAddress;
  console.log(`[+] WS client from ${clientIP} — awaiting auth (total: ${clients.size + 1})`);

  // --- Authentication state machine ------------------------------------------
  let authenticated = false;
  let wsBuffer = Buffer.alloc(0);
  let authTimer = setTimeout(() => {
    console.log(`[!] Auth timeout for ${clientIP} — closing`);
    try { socket.write(encodeFrame(JSON.stringify({ type: 'auth', status: 'timeout' }))); } catch {}
    socket.destroy();
  }, AUTH_TIMEOUT_MS);

  // Send auth challenge: client must respond with the shared secret
  try {
    socket.write(encodeFrame(JSON.stringify({ type: 'auth_challenge', message: 'Send shared secret to authenticate' })));
  } catch (e) {
    console.error(`[!] Failed to send auth challenge: ${e.message}`);
    socket.destroy();
    clearTimeout(authTimer);
    return;
  }

  // --- TCP connection (only opened after auth) -------------------------------
  let tcp = null;
  let tcpBuffer = Buffer.alloc(0);

  function openTunnel() {
    tcp = net.createConnection({ host: TUNNEL_HOST, port: TUNNEL_PORT });
    tcp.on('connect', () => console.log(`[+] TCP tunnel connected for ${clientIP}`));
    tcp.on('data', (chunk) => {
      tcpBuffer = Buffer.concat([tcpBuffer, chunk]);
      while (true) {
        const idx = tcpBuffer.indexOf(0x0A);
        if (idx === -1) break;
        const line = tcpBuffer.slice(0, idx).toString('utf-8');
        tcpBuffer = tcpBuffer.slice(idx + 1);
        if (line.trim() && !socket.destroyed) {
          socket.write(encodeFrame(line));
        }
      }
    });
    tcp.on('close', () => {
      console.log(`[-] TCP closed for ${clientIP}`);
      if (!socket.destroyed) socket.end();
    });
    tcp.on('error', (err) => {
      console.error(`[!] TCP error: ${err.message}`);
      if (!socket.destroyed) socket.end();
    });
  }

  // --- Handle WS frames -----------------------------------------------------
  socket.on('data', (chunk) => {
    wsBuffer = Buffer.concat([wsBuffer, chunk]);
    while (wsBuffer.length > 0) {
      const frame = decodeFrame(wsBuffer);
      if (!frame) break;
      wsBuffer = wsBuffer.slice(frame.totalLen);

      if (frame.opcode === 8) { // close
        clearTimeout(authTimer);
        if (!authenticated) return;
        if (tcp && !tcp.destroyed) tcp.destroy();
        return;
      }

      if (frame.opcode !== 1 || frame.data.length === 0) continue; // only text frames

      const msg = frame.data.toString('utf-8');

      // --- Pre-auth: check for secret ----------------------------------------
      if (!authenticated) {
        let parsed;
        try { parsed = JSON.parse(msg); } catch { parsed = null; }

        // Accept both raw secret string and { type: 'auth', secret: '...' }
        const candidate = parsed && parsed.type === 'auth' ? parsed.secret : msg;
        if (timingSafeEqual(candidate, SHARED_SECRET)) {
          authenticated = true;
          clearTimeout(authTimer);
          console.log(`[+] Auth succeeded for ${clientIP}`);
          socket.write(encodeFrame(JSON.stringify({ type: 'auth', status: 'ok' })));
          // Now open the TCP tunnel
          openTunnel();
        } else {
          clearTimeout(authTimer);
          console.log(`[!] Auth FAILED for ${clientIP} — closing`);
          socket.write(encodeFrame(JSON.stringify({ type: 'auth', status: 'denied' })));
          socket.destroy();
          return;
        }
        continue;
      }

      // --- Post-auth: forward to TCP ----------------------------------------
      const line = msg.replace(/\n+$/, '') + '\n';
      if (tcp && !tcp.destroyed) tcp.write(line);
    }
  });

  socket.on('close', () => {
    clearTimeout(authTimer);
    console.log(`[-] WS client ${clientIP} disconnected (total: ${clients.size - 1})`);
    clients.delete(socket);
    if (tcp && !tcp.destroyed) tcp.destroy();
  });

  socket.on('error', (err) => {
    clearTimeout(authTimer);
    console.error(`[!] WS error: ${err.message}`);
    clients.delete(socket);
    if (tcp && !tcp.destroyed) tcp.destroy();
  });

  clients.add(socket);
});

httpServer.listen(WS_PORT, '0.0.0.0', () => {
  console.log(`JARVIS WS Proxy 0.0.0.0:${WS_PORT} → TCP ${TUNNEL_HOST}:${TUNNEL_PORT}`);
  console.log(`  Auth: shared-secret required (timeout ${AUTH_TIMEOUT_MS}ms)`);
  console.log(`Health: http://localhost:${WS_PORT}/health`);
});