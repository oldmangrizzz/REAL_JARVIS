# Interface

**Path:** `Jarvis/Sources/JarvisCore/Interface/`
**Files:** 8 (1003 lines)
- `RealJarvisInterface.swift` — top-level voice command router
- `IntentParser.swift` / `IntentTypes.swift` — speech → intent
- `CapabilityRegistry.swift` — registry of `DisplayEndpoint`s
- `DisplayCommandExecutor.swift` — authority-checked dispatch
- `AirPlayBridge.swift`, `HDMICECBridge.swift`, `HTTPDisplayBridge.swift` — output transports

## Purpose
The **voice-to-display pipeline** lives here (see [[architecture/VOICE_TO_DISPLAY_PIPELINE]]).
Speech arrives via AVFoundation/Speech, is parsed into an intent, routed
through capability checks, and dispatched to the right display transport.

## Key types
- `VoiceCommandResponse`, `VoiceCommandRouter` — top of pipeline.
- `ParsedIntent`, `JarvisIntent` — sum type of supported operator intents.
- `IntentParser` (`@unchecked Sendable`) — NL → intent.
- `DisplayEndpoint` (`Codable`, `Sendable`, `Identifiable`) — a screen/output
  we can reach.
- `CommandAuthority` + `CommandAuthorization` — who is allowed to do what.
- `DisplayCommandExecutor` — the enforcement point.
- `AirPlayBridge` / `HDMICECBridge` / `HTTPDisplayBridge` — transports.

## Pipeline (normal path)
1. `RealJarvisInterface` receives recognized text.
2. `IntentParser` produces `ParsedIntent`.
3. `CommandAuthorization` is checked against `CommandAuthority`
   (operator-bound).
4. `DisplayCommandExecutor` dispatches to a `DisplayEndpoint` via the right
   bridge.
5. Result returns as `VoiceCommandResponse`.

## Gates invoked
- A&Ox4 ([[concepts/AOx4]]) — any confidence below threshold short-circuits.
- Voice-Approval-Gate ([[concepts/Voice-Approval-Gate]]) — for spoken replies.
- Alignment Tax — pre-action for any "potentially adverse" intent.
- NLB ([[concepts/NLB]]) — any LLM-in-the-loop goes through the summarizer.

## Related
- [[architecture/VOICE_TO_DISPLAY_PIPELINE]]
- [[codebase/modules/Voice]] for audio output side.
- [[codebase/modules/Core]] for skill dispatch once intent is decided.
