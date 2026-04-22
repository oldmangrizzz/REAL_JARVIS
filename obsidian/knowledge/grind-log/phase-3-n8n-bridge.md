# Phase 3 — n8n Bridge (Jarvis's Hands)

## Status
SHIPPED. Commits `cb93f93` (workflows) + `d68a4a7` (swift wiring) on origin/main.

## What landed
- `Jarvis/Sources/JarvisCore/Interface/N8nWorkflowRunner.swift` — protocol + class, env-driven
  (`JARVIS_N8N_BASE_URL`, `JARVIS_N8N_USER`, `JARVIS_N8N_PASSWORD`). Stamps `ts` + `source` on payloads.
- `SystemCommandHandler` — `n8n:<path>` skill prefix routes to the runner; Swift-6-safe sync bridge
  via `SystemCommandHandlerAwaitBox<T>` (`@unchecked Sendable` class wrapping `NSLock` inside
  synchronous methods). Avoids `NSLock.lock()` calls from async contexts.
- `VoiceCommandRouter` — both inits thread `n8nRunner` through; `makeN8nRunner()` factory pulls env.
- `N8nWorkflowRunnerTests` — 7/7 green (success, failure, basic auth, URL assembly, payload stamping,
  transport error, non-2xx).
- Seed workflows: `ha-call-service`, `scene-downstairs-on`, `scene-upstairs-on`, `forge-self-heal`,
  `daily-briefing`, `mesh-display-broadcast` — all `alwaysOutputData:true`.

## Verification
- `xcodebuild build` → `BUILD SUCCEEDED`.
- `xcodebuild test -scheme Jarvis -only-testing:JarvisCoreTests` → **612 executed, 0 failures, 1 skip**.

## Swift-6 gotcha (documented)
`NSLock.lock()/unlock()` are `@available(*, unavailable)` from async contexts. Sync-over-async bridges
that need mutual exclusion must wrap the lock inside synchronous methods on a dedicated
`@unchecked Sendable` class (the AwaitBox pattern). The Task closure calls the sync method; the lock
never crosses the async boundary.

## Next: Phase 4
- ConversationEngine TODOs: `turnId`, `bargeInCount`, route-from-gateway.
- SpeakerIdentifier at `RealJarvisInterface.swift:518`.
- Cognee migrate echo→beta; MemGPT on beta.
