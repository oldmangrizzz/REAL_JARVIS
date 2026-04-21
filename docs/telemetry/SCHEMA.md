# Jarvis Telemetry Schema

**Classification:** Operational reference
**Scope:** Every telemetry row written by Swift (`JarvisCore.TelemetryStore`),
the forge (`/opt/swarm-forge/`), and the dashboard front-end must conform
to one of the shapes below. Rows that do not match their declared table's
contract are malformed and will be rejected by the SPEC-009 chain
verifier (extra required-field drift) or silently dropped by Convex
(unknown validator key).

## Global invariants

Every row written by `TelemetryStore.append` carries, in addition to the
table-specific body fields:

| Field          | Type   | Who writes     | Notes                                                                 |
|----------------|--------|----------------|-----------------------------------------------------------------------|
| `timestamp`    | string | store          | ISO-8601. Caller-supplied value wins; missing ⇒ `Date()` at write.    |
| `principal`    | string | store          | `principal.tierToken` when supplied; absent for legacy / pre-principal rows. |
| `prevRowHash`  | string | store          | SHA-256 hex of the previous row's body, or `"GENESIS"` at chain start.|
| `rowHash`      | string | store          | SHA-256 hex of this row's body (sorted-keys JSON, excluding `rowHash` itself). |

Per PRINCIPLES §2, telemetry MUST NOT contain:

- Raw audio samples or waveform buffers.
- Raw canon content (principles, soul anchor biographical mass, etc.).
- Private-key material of any kind.
- Unredacted operator PII beyond the `operatorLabel` tag.

If a new event needs to reference audio or canon, the telemetry row
carries only a SHA-256 digest and the original bytes live on disk under
access control.

## Tables

### `execution_traces`
Forge / skill / CLI step completion.

| Field           | Type   | Required | Description                              |
|-----------------|--------|:--------:|------------------------------------------|
| `workflowId`    | string | ✔︎       | Stable workflow / task ID.               |
| `stepId`        | string | ✔︎       | Step identifier inside the workflow.     |
| `inputContext`  | string | ✔︎       | Opaque; hash of input if sensitive.      |
| `outputResult`  | string | ✔︎       | Opaque; hash of output if sensitive.     |
| `status`        | string | ✔︎       | One of `started`, `ok`, `failed`, `skipped`. |

### `stigmergic_signals`
Ternary pheromone edges between graph nodes.

| Field          | Type    | Required | Description                          |
|----------------|---------|:--------:|--------------------------------------|
| `nodeSource`   | string  | ✔︎       |                                      |
| `nodeTarget`   | string  | ✔︎       |                                      |
| `ternaryValue` | int     | ✔︎       | −1, 0, or +1.                        |
| `agentId`      | string  | ✔︎       |                                      |
| `pheromone`    | number  | ✔︎       | Non-negative double.                 |

### `recursive_thoughts`
Ralph-style scratchpad step log.

| Field              | Type     | Required | Description                    |
|--------------------|----------|:--------:|--------------------------------|
| `sessionId`        | string   | ✔︎       |                                |
| `thoughtTrace`     | string[] | ✔︎       | Bullet/step lines.             |
| `memoryPageFault`  | bool     | ✔︎       |                                |

### `vagal_tone`
Bio-inspired regulation signal per source node.

| Field       | Type    | Required | Description                     |
|-------------|---------|:--------:|---------------------------------|
| `sourceNode`| string  | ✔︎       |                                 |
| `value`     | number  | ✔︎       | Double.                         |
| `state`     | string  | ✔︎       | `resting`, `sympathetic`, etc.  |

### `node_registry`
Mesh node reachability heartbeats.

| Field          | Type   | Required | Description                |
|----------------|--------|:--------:|----------------------------|
| `nodeName`     | string | ✔︎       | alpha, beta, charlie, ...  |
| `address`      | string | ✔︎       | May be empty string.       |
| `rustDeskID`   | string | ✔︎       | May be empty string.       |
| `tunnelState`  | string | ✔︎       | `up`, `down`, `degraded`.  |
| `guiReachable` | bool   | ✔︎       |                            |

### `harness_mutations`
Agency-swarm / archon self-upgrade records.

| Field             | Type   | Required | Description                          |
|-------------------|--------|:--------:|--------------------------------------|
| `versionId`       | string | ✔︎       |                                      |
| `workflowId`      | string | ✔︎       |                                      |
| `diffPatch`       | string | ✔︎       | May be empty string; stored as-is.   |
| `evaluationScore` | number | ✔︎       | Double 0…1.                          |
| `rollbackHash`    | string | ✔︎       | SHA-256 hex of previous state.       |

### `voice_gate_state`
Current state of the voice approval gate.

| Field                          | Type   | Required | Description                                   |
|--------------------------------|--------|:--------:|-----------------------------------------------|
| `hostNode`                     | string | ✔︎       |                                               |
| `state`                        | string | ✔︎       | `ok`, `pending`, `revoked`, etc.              |
| `lastSync`                     | string | ✔︎       | ISO-8601.                                     |
| `composite`                    | string |          | Fingerprint composite (hex).                  |
| `expectedComposite`            | string |          |                                               |
| `referenceAudioDigest`         | string |          | SHA-256 hex only.                             |
| `referenceTranscriptDigest`    | string |          | SHA-256 hex only.                             |
| `modelRepository`              | string |          |                                               |
| `personaFramingVersion`        | string |          |                                               |
| `operatorLabel`                | string |          |                                               |
| `approvedAtISO8601`            | string |          |                                               |
| `notes`                        | string |          |                                               |

### `voice_gate_events`
Discrete voice-gate transitions. Same schema as above but with required
`eventType ∈ {approved, revoked, rotated, failed, rejected}`.

### `heartbeat` (MK2-EPIC-07)
Host liveness. Dashboard drives the GREEN/YELLOW/RED pill from the most
recent row's `timestamp`: GREEN when age < 60 s, YELLOW when < 300 s, RED
otherwise.

| Field            | Type   | Required | Description                         |
|------------------|--------|:--------:|-------------------------------------|
| `event`          | string | ✔︎       | Constant `"heartbeat"`.             |
| `voiceGateOK`    | bool   | ✔︎       |                                     |
| `tunnelClients`  | int    | ✔︎       |                                     |
| `memoryVersion`  | string | ✔︎       | Opaque monotonic tag.               |
| `lastIntentAt`   | string |          | ISO-8601 of most recent intent.     |

### `tunnel_events` (MK2-EPIC-02)
Authorization + destructive-guardrail outcomes.

| Event name                | Required fields                                                                 |
|---------------------------|---------------------------------------------------------------------------------|
| `tunnel.auth.granted`     | `clientPubKey`, `role`, `tokenExpiresAt`                                        |
| `tunnel.auth.denied`      | `clientPubKey?`, `reason ∈ {bad_token, expired, tamper, unknown_client}`        |
| `destructive.confirmed`   | `action`, `canonicalHashHex`, `nonce`                                           |
| `destructive.rejected`    | `action?`, `reason ∈ {missing_header, wrong_hash, nonce_replay}`                |

### `arc_submission_events` (MK2-EPIC-03)
ARC-AGI end-to-end pipeline progress.

| Event name                     | Required fields                                      |
|--------------------------------|------------------------------------------------------|
| `arc.submit.start`             | `taskId`                                             |
| `arc.submit.physics_loaded`    | `taskId`, `gridRows`, `gridCols`                     |
| `arc.submit.rlm_response`      | `taskId`, `rlmLatencyMs`, `tokensUsed`               |
| `arc.submit.validated`         | `taskId`, `witnessSha256`                            |
| `arc.submit.done`              | `taskId`, `latencyMs`, `witnessSha256`               |
| `arc.submit.failed`            | `taskId?`, `reason ∈ {invalid_json, shape_mismatch, rlm_timeout, physics_nan}` |

### `oscillator`
Master-oscillator tick + PLV samples. Event names `oscillator.started`,
`oscillator.stopped`, `oscillator.tick`, `oscillator.plv`.

| Field       | Type    | Required | Description                      |
|-------------|---------|:--------:|----------------------------------|
| `event`     | string  | ✔︎       |                                  |
| `phase`     | number  |          | Radians for `tick`.              |
| `plv`       | number  |          | 0…1 for `plv`.                   |

### `conversation_turns` + `conversation_state_transitions`
ConversationEngine turn audit. Free-form `state`, `nextState`, `sessionId`
and `turnNumber` fields. Used for SPEC-003 replay.

---

## Versioning

Schema version is tracked via the `schema_version` key-value in
`soul-anchor` metadata (not per-row). A schema breaking change implies
either a new table name (preferred) or a canon-signed migration note in
`CANON/telemetry/<version>-migration.md`.

Last revised: MK2-EPIC-07 landing.
