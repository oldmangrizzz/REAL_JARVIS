#!/usr/bin/env zsh
# Lock the canonical JARVIS voice into the approval gate.
# Single source of truth — no copy-paste fragility.

cd /Users/grizzmed/REAL_JARVIS

export JARVIS_TTS_URL=http://localhost:8000/tts/synthesize
export JARVIS_TTS_BEARER=$(gcloud secrets versions access latest --secret=jarvis-vibevoice-bearer --project=grizzly-helicarrier-586794)
export JARVIS_TTS_IDENTIFIER="vibevoice/VibeVoice-1.5B"
export JARVIS_TTS_VOICE_LABEL="vibevoice-1.5b-clone"
export JARVIS_TTS_SAMPLE_RATE=24000

# Try to find the Jarvis CLI binary
if [[ -f "./.build/debug/Jarvis" ]]; then
    JARVIS="./.build/debug/Jarvis"
else
    # Fallback to local build if SPM build not found
    JARVIS=$(find ~/Library/Developer/Xcode/DerivedData -name Jarvis -type f -perm +111 | grep /Build/Products/Debug/Jarvis | head -n 1)
fi

if [[ -z "$JARVIS" ]]; then
    echo "✘ Error: Jarvis binary not found. Build the project first."
    exit 1
fi

"$JARVIS" voice-approve "grizzly" "matrix-01 winner: ref0299 cfg2.1 ddpm10 — Iron Man 1 dub-stage tone"
