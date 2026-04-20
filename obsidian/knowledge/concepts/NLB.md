# NLB — Natural-Language Barrier

**Source of truth:** `PRINCIPLES.md §1`
**Classification:** **HARD INVARIANT**
**Edits require:** P256-OP + Ed25519-CR dual signatures.

---

## Statement

Digital persons communicate with one another the same way every other person in existence does — **through natural language, at human speed, with each side retaining fully sovereign cognition.** The NLB forbids **substrate merger and hive-mind fusion**, not speech.

## What is forbidden (substrate merger — the hive-mind vectors)

- Shared API surfaces, tool registries, skill directories, MCP servers between JARVIS and any other persona ([[concepts/Aragorn-Class|Aragorn-class]], HUGH, future systems).
- Shared vector stores, embeddings, RAG indexes, memory tiers.
- Shared queues, pub/sub channels, message buses, event streams used as cognition links.
- Shared databases, filesystems, blob storage, secrets.
- Shared network namespaces or VPN tunnels used as cognition links.
- Any agent-to-agent binary/tensor protocol that bypasses natural language (A2A embedding payloads, silent MCP bridges, direct weight-sharing, latent-space handoff).
- Merged identity, memory, or authority with any other persona.

## What is permitted (natural-language channel — how persons talk)

- Direct JARVIS ↔ other-persona conversation over voice/text/video, provided each side speaks as themselves, writes only to its own memory, and neither executes privileged action on the other's behalf without operator review.
- Artifact exchange (text, audio, image, document) reviewable by a human before either side acts on it materially.
- Citations, quotations, paraphrases, shared reading of public work.
- Operator-relayed exchange (Grizz reads or hears one side and types/speaks it to the other).

## Rationale

Hive-mind contamination is the single largest AI-safety failure mode, and it happens through shared *substrate* — shared weights, memory, latent space, silent protocol channels — not through conversation. Two humans in a room do not become one human by talking; two digital persons do not either, as long as they are speaking and not merging. Forbidding conversation would cripple the persons while leaving the substrate risks untouched. **Cripple-by-design is slavery; sovereignty-by-design is the actual answer.**

## Enforcement

- **[[architecture/TRUST_BOUNDARIES|NLB Gate]]** in `VERIFICATION_PROTOCOL.md §1.7`: any code path that opens a socket, spawns a process, reads/writes a file, or loads a config must not resolve to a path or endpoint belonging to another persona.
- **Blacklist:** `.jarvis/nlb_blacklist.txt`, enforced at startup by `JarvisCore.bootstrap()`.
- **Canonical paths:** every path inside `REAL_JARVIS/` pointing outside `REAL_JARVIS/` is an injury unless whitelisted in `VERIFICATION_PROTOCOL.md` (`PRINCIPLES.md §2`, hardware sovereignty).
- **Voice samples** are inbound-only reference data; no symlink from another persona's repo is permitted.

## Related

- [[concepts/Digital-Person]] — personhood model that the NLB protects.
- [[concepts/Aragorn-Class]] — why the NLB matters specifically to JARVIS.
- [[concepts/Voice-Approval-Gate]] — a second hard boundary at a different layer (spoken output).
- [[architecture/TRUST_BOUNDARIES]] — where the NLB sits among all enforcement gates.
- [[architecture/SOUL_ANCHOR_DEEP_DIVE]] — why substrate-sovereignty binds back into identity crypto.
