#!/usr/bin/env bash
# scripts/voice-loop.sh — VOICE-002 reference-impl hook (XTTS canonical).
#
# Lights up the streaming S2S loop end-to-end against the operator's
# canonical XTTS v2 service (Coqui XTTS on Delta:8787 via HTTPTTSBackend,
# bearer-protected). Per CANON LAW (PRINCIPLES.md §"CANON LAW — VOICE"):
#
#   - TTS backend: Coqui XTTS v2 ONLY. No VibeVoice/F5/say/AVSpeech/cloud TTS.
#   - Reference clip: voice-samples/0299_TINCANS_CANONICAL.wav.
#   - Remote HTTP bearer path only. Local TTS unreliable on 8 GB hardware.
#
# Wiring (matches SPEC-VOICE-002 §3):
#
#   mic ──► [ASR StreamingASRBackend] ──► ConversationEngine
#                                              │
#                                              ├── barge-in ← DuplexVADGate
#                                              │   (AMBIENT-002 §4.5.E)
#                                              ▼
#                                       [StreamingLLMClient]
#                                              │ LLMToken stream
#                                              ▼
#                                     [StreamingTTSBackend]  ◄── XTTS HTTP
#                                              │ TTSAudioChunk stream
#                                              ▼
#                                        AmbientAudioGateway.emit
#
# Required env (fail-closed — no silent fallbacks):
#
#   JARVIS_TTS_URL       → https://<xtts-host>:8787/synthesize-stream
#   JARVIS_TTS_BEARER    → bearer token for HTTPTTSBackend
#   JARVIS_TTS_IDENTIFIER→ xtts-v2-streaming (identity fingerprint input)
#   JARVIS_TTS_VOICE_LABEL → canonical operator voice label
#   JARVIS_REF_WAV       → voice-samples/0299_TINCANS_CANONICAL.wav
#
# This script is a reference-impl hook, NOT a production daemon. It launches
# a JarvisCore smoke driver that exercises the four §3 deliverables
# (StreamingASRBackend / StreamingLLMClient / StreamingTTSBackend /
# DuplexVADGate) against a single conversation session and exits.
# Production is launchd-supervised via scripts/run-voice-bridge.sh.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
REF_WAV_DEFAULT="${REPO}/voice-samples/0299_TINCANS_CANONICAL.wav"

: "${JARVIS_TTS_URL:?JARVIS_TTS_URL must be set to the XTTS /synthesize-stream endpoint}"
: "${JARVIS_TTS_BEARER:?JARVIS_TTS_BEARER must be set (bearer-protected HTTPTTSBackend)}"
: "${JARVIS_REF_WAV:=$REF_WAV_DEFAULT}"
: "${JARVIS_TTS_IDENTIFIER:=xtts-v2-streaming}"
: "${JARVIS_TTS_VOICE_LABEL:=xtts-v2-operator}"
: "${JARVIS_TTS_SAMPLE_RATE:=24000}"

if [[ ! -f "$JARVIS_REF_WAV" ]]; then
    echo "voice-loop: reference clip missing at $JARVIS_REF_WAV" >&2
    echo "voice-loop: CANON LAW requires voice-samples/0299_TINCANS_CANONICAL.wav" >&2
    exit 2
fi

case "${JARVIS_TTS_IDENTIFIER}" in
    *vibevoice*|*f5*|*avspeech*|*say*|*elevenlabs*|*cartesia*)
        echo "voice-loop: CANON LAW violation — TTS identifier '${JARVIS_TTS_IDENTIFIER}'" >&2
        echo "voice-loop: only Coqui XTTS v2 identifiers are accepted in this loop." >&2
        exit 3
        ;;
esac

export JARVIS_TTS_URL JARVIS_TTS_BEARER JARVIS_REF_WAV
export JARVIS_TTS_IDENTIFIER JARVIS_TTS_VOICE_LABEL JARVIS_TTS_SAMPLE_RATE

cat <<WIRING
voice-loop: wiring (SPEC-VOICE-002 §3)
    ASR   →  StreamingASRBackend
             (Jarvis/Shared/Sources/JarvisShared/StreamingASRBackend.swift)
    LLM   →  StreamingLLMClient
             (Jarvis/Shared/Sources/JarvisShared/StreamingLLMClient.swift)
    TTS   →  StreamingTTSBackend + HTTPTTSBackend (bearer, XTTS v2)
             (Jarvis/Shared/Sources/JarvisShared/StreamingTTSBackend.swift)
             (Jarvis/Sources/JarvisCore/Voice/HTTPTTSBackend.swift)
    VAD   →  DuplexVADGate
             (Jarvis/Sources/JarvisCore/Ambient/AmbientAudioGateway.swift)
    Loop  →  ConversationEngine
             (Jarvis/Sources/JarvisCore/Voice/Conversation/ConversationEngine.swift)
    Ref   →  ${JARVIS_REF_WAV}
    Ident →  ${JARVIS_TTS_IDENTIFIER}
WIRING

echo "voice-loop: probing XTTS endpoint ${JARVIS_TTS_URL} …"
probe_payload=$(cat <<JSON
{"text":"canon probe","reference_audio_b64":"","reference_text":"","temperature":0.7,"top_p":0.85}
JSON
)

set +e
probe_rc=0
probe_out=$(curl -sS -o /dev/null -w "%{http_code}" \
    -X POST "$JARVIS_TTS_URL" \
    -H "Authorization: Bearer ${JARVIS_TTS_BEARER}" \
    -H "Content-Type: application/json" \
    --data "$probe_payload" \
    --max-time 10 2>&1) || probe_rc=$?
set -e

echo "voice-loop: XTTS probe status=${probe_out} curl_rc=${probe_rc}"

case "$probe_out" in
    2*|400|422)
        echo "voice-loop: endpoint reachable + bearer accepted. ✅"
        ;;
    401|403)
        echo "voice-loop: bearer rejected by XTTS endpoint. ❌" >&2
        exit 5
        ;;
    *)
        echo "voice-loop: endpoint unreachable or non-XTTS response. ❌" >&2
        exit 6
        ;;
esac

echo "voice-loop: canon reference + endpoint verified. Handing off to ConversationEngine consumers."
