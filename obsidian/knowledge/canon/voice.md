# CANON — Voice

**Engine**: Coqui XTTS v2 (zero-shot clone).
**Reference clip**: `voice-samples/0299_TINCANS_CANONICAL.wav` (Derek Harvard JARVIS).
**Host**: Delta (187.124.28.147) port 8787, systemd unit `jarvis-tts.service`.
**Transport**: LaunchAgent `com.grizz.jarvis.xtts-tunnel` forwards localhost → Delta.
**Client**: `~/.jarvis/bin/jarvis-say "<text>"` is the ONLY sanctioned invocation.
**Echo bridge**: `/speak` endpoint on 127.0.0.1:8765 wraps jarvis-say.

## Forbidden
- `say` / `AVSpeechSynthesizer` / Siri voices
- VibeVoice (deprecated — any `TTSBackend.vibevoiceLocked` reference is stale name only)
- F5-TTS (archived)
- Any cloud TTS (ElevenLabs, Google, Azure, OpenAI)

## Failure mode
Canon failure = **silent**. Never substitute with another voice. Log and alert via ntfy, but do not speak.

## Swift integration
- `Jarvis/Sources/JarvisCore/Voice/HTTPTTSBackend.swift` — production backend.
- Bearer token required, config in `~/.jarvis/tts.env`.

## Migration debt
- Rename `TTSBackend.vibevoiceLocked` → `TTSBackend.xttsLocked` (stale symbol).
