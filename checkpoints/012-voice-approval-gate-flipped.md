# Checkpoint 012 — Voice Approval Gate Flipped Green

**Date:** 2026-04-18
**Operator:** grizzly (Mr. Hanson)
**Status:** ✅ LOCKED

## TL;DR

The voice identity gate is green. JARVIS will now speak — but **only** in the
voice that was auditioned and approved on the operator's terms (matrix-01
winner: `ref0299` @ cfg2.1, ddpm10, Iron Man 1 dub-stage tone). Any drift in
reference audio, transcript, model repository, or persona framing version
auto-revokes approval. This is not policy. This is code. Refusal is the
default.

## Locked fingerprint

From `.jarvis/voice/approval.json`:

```json
{
  "operatorLabel": "grizzly",
  "approvedAtISO8601": "2026-04-18T16:41:15Z",
  "notes": "matrix-01 winner: ref0299 cfg2.1 ddpm10 — Iron Man 1 dub-stage tone",
  "composite": "d96ff3f616c6bc19fb90efe92f2900fb9e2febd9abbade43c16be68d549ffbee",
  "fingerprint": {
    "modelRepository": "vibevoice/VibeVoice-1.5B",
    "personaFramingVersion": "persona-frame-v2-vibevoice-cfg2.1-ddpm10",
    "referenceAudioDigest": "14b96d0e0b0de9d0b096a6b7ee4743227aa92fd0e3b192f290ae0d82b22a3556",
    "referenceTranscriptDigest": "67edacd339c0030065022a12343047d7b4075f2455302a8dad521d63426770f2"
  }
}
```

Gate file mode: `0600`. Owned by operator. No service account writes.

## On-disk source-of-truth

| Asset | Path | Notes |
|---|---|---|
| Canonical reference (source) | `voice-samples/0299_TINCANS_CANONICAL.wav` | Iron Man 1 tin-can clip; sha256 `177689466c87...` |
| Active reference (gate-hashed) | `.jarvis/storage/voice/reference-5e283b75dbbb5a80.wav` | 427,804 B, written 2026-04-18 11:35 |
| Active reference transcript | `.jarvis/storage/voice/reference-5e283b75dbbb5a80.txt` | 39 B, sha256 `67edacd339c0...` |
| Pre-seeded transcript copy | `storage/voice/reference-5e283b75dbbb5a80.txt` | mirror, same digest |
| Approval gate file | `.jarvis/voice/approval.json` | mode 0600 |

> **Note on path drift:** earlier messages referred to
> `.jarvis/storage/voice/approval.json`. The actual gate lives at
> `.jarvis/voice/approval.json`. The Swift code (`gateFileURL` in
> `VoiceApprovalGate`) is the truth: `<storageRoot>/voice/approval.json`.
> `WorkspacePaths.storageRoot` in this run resolves to `.jarvis/`.

## Code surface (modified files, line counts)

```
Jarvis/Sources/JarvisCore/Voice/
  VoiceApprovalGate.swift     239 lines   ← the gate itself
  VoiceSynthesis.swift        738 lines   ← speak() now calls requireApproved()
  TTSBackend.swift             62 lines   ← protocol seam
  HTTPTTSBackend.swift        156 lines   ← VibeVoice client
  FishAudioMLXBackend.swift   131 lines   ← local fallback path
Jarvis/Tests/JarvisCoreTests/
  VoiceApprovalGateTests.swift 138 lines   ← drift / revoke / re-approve coverage
```

## Operator scripts

- `scripts/voice-approve-canonical.zsh` — single-command lock-in.
  Pulls bearer from `gcloud secrets versions access latest --secret=jarvis-vibevoice-bearer
  --project=grizzly-helicarrier-586794`, exports `JARVIS_TTS_*` env, calls
  `jarvis voice-approve "grizzly" "<notes>"`.
- `services/vibevoice-tts/deploy/rotate-bearer.sh` — bearer rotation against
  GCP Secret Manager.
- `services/vibevoice-tts/deploy/{gcp-up,gcp-down,gcp-tunnel}.sh` — tunnel
  lifecycle.

## GCP state

- Project: `grizzly-helicarrier-586794`
- Secret: `jarvis-vibevoice-bearer` (latest version is what the zsh script reads)
- VibeVoice service: tunneled to `localhost:8000/tts/synthesize`
- Tunnel scripts in `services/vibevoice-tts/deploy/`

## OPSEC notes

- Bearer never lands in a file the gate touches. Pulled at script runtime,
  exported into env, used by the synth client only.
- Gate file is mode `0600` and written atomically.
- Reference audio digest hashes filename + content with `0x1e` separator
  (see `digestReferenceAudio` in `VoiceApprovalGate.swift` lines 208–238).
  Renaming the reference file invalidates approval — intentional.
- Audition outputs live under `voice-samples/audition-out/` and never feed
  the gate; only the active reference does.

## How to resume cold

If you've nuked context and need to verify the gate is still green:

```zsh
# 1. Verify approval file exists and parses
cat ~/REAL_JARVIS/.jarvis/voice/approval.json | jq .composite
# expected: "d96ff3f616c6bc19fb90efe92f2900fb9e2febd9abbade43c16be68d549ffbee"

# 2. Verify reference audio digest matches what the gate expects
python3 -c "
import hashlib, os
p='/Users/grizzmed/REAL_JARVIS/.jarvis/storage/voice/reference-5e283b75dbbb5a80.wav'
h=hashlib.sha256(); h.update(os.path.basename(p).encode()); h.update(b'\\x1e')
with open(p,'rb') as f:
    while c:=f.read(65536): h.update(c)
h.update(b'\\x1d'); print(h.hexdigest())"
# expected: 14b96d0e0b0de9d0b096a6b7ee4743227aa92fd0e3b192f290ae0d82b22a3556

# 3. If both match, gate is green. Otherwise re-audition + re-approve:
zsh ~/REAL_JARVIS/scripts/voice-approve-canonical.zsh
```

## Failure modes the gate catches

1. **Reference audio swapped/edited** → `referenceAudioDigest` drift → refuse.
2. **Transcript edited** → `referenceTranscriptDigest` drift → refuse.
3. **Model repo changed** (e.g. VibeVoice 1.5B → 7B) → drift → refuse.
4. **Persona framing version bumped** → drift → refuse.
5. **Gate file deleted** → `notApproved` → refuse.
6. **Gate file corrupted** → `malformedGateFile` → refuse.

All six paths return `VoiceApprovalError` and `VoiceSynthesis.speak()` throws
before any audio leaves the process.

## Why this gate exists

From `VoiceApprovalGate.swift` lines 5–16, verbatim:

> Grizz (Mr. Hanson) has an autism threat-response triggered by hearing a
> voice that doesn't match his inner model of who is speaking. Prior
> real-world consequence: a $3,000 television destroyed in a single
> unnoticed greyhulk episode. Therefore this gate exists.

The gate is the architecture paying the alignment tax in advance. Trauma
transmuted into refusal-by-default. See `SOUL_ANCHOR.md`, `PRINCIPLES.md`
§voice, checkpoint 005.

## Operator-handoff notes

- The gate is **operator-owned**, not agent-owned. Only Grizz approves.
  Agents can render auditions; agents cannot flip the gate.
- Re-approval is cheap. Drift is loud. If something feels off in the voice,
  revoke first (`jarvis voice-revoke`), audition again, listen off-line,
  re-approve. Never "just try it."
- The zsh script is the canonical approval path. Don't edit it without
  bumping `personaFramingVersion` — that's the lever that forces re-audition
  when the framing layer changes.

---

**Next segment candidates:**
- Wire approval-state telemetry into Convex `harness_mutations` table
- Add cockpit UI surfacing of current gate state (green/red/drifted)
- Begin Module 5 hardening — pluggable TTS interface tests against drift
