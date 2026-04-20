# jarvis-linux-node

**Path:** `services/jarvis-linux-node/`
**Files:**
- `jarvis_node.py` — daemon (asyncio, cryptography).
- `install.sh` — install script.
- `jarvis-node.service` — systemd unit (Linux).
- `ai.realjarvis.host-tunnel.plist` — launchd plist (macOS dev parity).
- `README.md`

## Purpose
Linux-side **mesh node daemon**. Satisfies the CANON §5.1 "interconnected
mesh" contract: every host running JARVIS maintains a registered,
heartbeating tunnel back to the Mac's
[[codebase/modules/Host|JarvisHostTunnelServer]] on port **9443**.

## Wire protocol (reproduced bit-for-bit from Swift `TunnelCrypto`)

```
TCP
 → newline-framed lines
   → JSON JarvisTransportPacket { origin, timestamp, payload }
     → payload = base64(ChaCha20-Poly1305 sealed box,
                        key = SHA-256(sharedSecret_utf8))
       → plaintext = JSON JarvisTunnelMessage
         { kind, registration?, command?, snapshot?,
           response?, push?, error? }
```

## Dependencies
- `python3` (stdlib)
- `python3-cryptography` (Debian package)

## Invariants
- Shared secret is derived identically on both ends; no key exchange
  over the wire (pinned).
- Peer fingerprint ratified by [[codebase/modules/SoulAnchor]] before
  any command is executed.

## Related
- [[codebase/modules/Host]]
- [[codebase/platforms/Shared]] (TunnelModels, TunnelCrypto)
- [[codebase/modules/ControlPlane]]
