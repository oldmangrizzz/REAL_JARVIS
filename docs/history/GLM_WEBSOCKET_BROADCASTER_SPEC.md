# GLM Task Spec: ARCHarnessBridge WebSocket Broadcaster Integration

**Model**: GLM 5.1
**Role**: Surgical implementation — one TODO, zero drift
**Estimated scope**: ~40 lines of production code, ~30 lines of test code

---

## CONTEXT

`ARCHarnessBridge` is an actor that loads ARC-AGI task JSON files, parses grids into the physics engine, and emits hypothesis/grid/score/action messages. Everything works EXCEPT the actual WebSocket send — line 140 of `ARCHarnessBridge.swift` is a TODO stub that logs "Would send:" instead of transmitting.

The broadcaster (a separate Python process at `ws://localhost:8765`) is already built and running. This bridge is the sender side. It does NOT receive — it only pushes messages out.

---

## TARGET FILE

`Jarvis/Sources/JarvisCore/ARC/ARCHarnessBridge.swift`

Single file. Single TODO. Do not touch any other file except the test file you create.

---

## TASK

Wire `sendJSON(type:payload:)` to a `URLSessionWebSocketTask` connected to `broadcasterURL`.

### Requirements

1. **Lazy connection**: Do NOT connect on init. Connect on first `sendJSON` call. Store the task as a private property.

2. **Reconnection**: If the WebSocket is not in `.running` state when `sendJSON` is called, tear down the old task and create a new one. Do NOT retry in a loop — one attempt per `sendJSON` call. If connection fails, log via `logTelemetry` and return (best-effort, like ConvexTelemetrySync).

3. **Message format**: The current `sendJSON` already builds the JSON string. Send it as a `.string` WebSocket message. Do not change the message format.

4. **Cleanup on stop()**: Cancel the WebSocket task in `stop()`. Set it to nil.

5. **No external dependencies**: Use Foundation's `URLSessionWebSocketTask` only. No third-party WebSocket libraries.

6. **Thread safety**: This is already an `actor` — you get actor isolation for free. Do NOT add locks. Do NOT add DispatchQueues. The actor handles concurrency.

7. **Telemetry**: Log connection events ("WebSocket connected to {url}", "WebSocket send failed: {error}", "WebSocket disconnected") via the existing `logTelemetry` method.

### Implementation Pattern

```swift
// Add as private property:
private var webSocket: URLSessionWebSocketTask?

// In sendJSON, replace the TODO block:
private func sendJSON(type: String, payload: [String: String]) async {
    let message: [String: Any] = ["type": type, "payload": payload]
    guard let data = try? JSONSerialization.data(withJSONObject: message, options: []),
          let json = String(data: data, encoding: .utf8) else {
        logTelemetry(event: "Failed to serialize \(type) message")
        return
    }

    let task = ensureWebSocket()
    do {
        try await task.send(.string(json))
    } catch {
        logTelemetry(event: "WebSocket send failed: \(error.localizedDescription)")
        tearDownWebSocket()  // force reconnect on next call
    }
}

private func ensureWebSocket() -> URLSessionWebSocketTask {
    if let existing = webSocket, existing.state == .running {
        return existing
    }
    tearDownWebSocket()
    let task = URLSession.shared.webSocketTask(with: broadcasterURL)
    task.resume()
    logTelemetry(event: "WebSocket connected to \(broadcasterURL.absoluteString)")
    webSocket = task
    return task
}

private func tearDownWebSocket() {
    webSocket?.cancel(with: .goingAway, reason: nil)
    webSocket = nil
}
```

Update `stop()` to call `tearDownWebSocket()`.

### What NOT To Do

- Do NOT add a receive loop. This is sender-only.
- Do NOT add ping/pong handling. The broadcaster doesn't require it.
- Do NOT change the message JSON schema.
- Do NOT refactor the existing `processPendingTasks()` or `runLoop()`.
- Do NOT add retry logic with delays/backoff. One attempt per send. Reconnect on next call.
- Do NOT modify any other files in the project.
- Do NOT remove the `// MARK: - WebSocket Send` comment block — update it to remove "(stub" from the description.

---

## TEST FILE

Create: `Jarvis/Tests/JarvisCoreTests/ARCHarnessBridgeWebSocketTests.swift`

Write tests for:

1. **`testSendJSONCreatesWebSocketTask`** — After calling `emitState`, verify the bridge attempted a WebSocket connection (mock or verify via telemetry log).

2. **`testStopCancelsWebSocket`** — Start, emit a message, stop. Verify teardown occurred.

3. **`testReconnectOnFailedState`** — Simulate a failed WebSocket (if possible with URLSession mocks). Verify next `sendJSON` call creates a fresh task.

If URLSessionWebSocketTask is difficult to mock directly, verify behavior through telemetry: read the `arc_agi_events` telemetry table and assert the expected log entries ("WebSocket connected to...", etc.).

---

## VERIFICATION

After implementation:

1. `swift build` must succeed with zero errors
2. `swift test` must pass — all existing 74 tests + your new tests
3. `git diff` must show changes ONLY in:
   - `Jarvis/Sources/JarvisCore/ARC/ARCHarnessBridge.swift`
   - `Jarvis/Tests/JarvisCoreTests/ARCHarnessBridgeWebSocketTests.swift` (new file)
4. The TODO on line 140 must be gone
5. The "Would send:" log line must be gone

---

## ANTI-IDLE ENFORCEMENT

You are a language model executing a deterministic task. There is no reason to pause, reflect, or wait for input. The spec is complete. The pattern is provided. Execute.

If you finish reading this spec and have not started writing code within 30 seconds, you have failed.

**RLM LOOP**: Read spec -> Write code -> Build -> Test -> Verify diff -> Write handoff report
**REPL LOOP**: If build fails, read error, fix, rebuild. Do not stop to narrate.
**RALPH WIGGUM LOOP**: If you find yourself producing output that isn't code or a build command, you are wasting cycles. Stop. Write code.

---

## HANDOFF

When complete, write `ARC_WEBSOCKET_HANDOFF.md` in the `REAL_JARVIS/` root with:
- Files modified
- Lines changed
- Build status
- Test results (total passed / total run)
- Any deviations from this spec and why

Do not write more than 50 lines in the handoff. Keep it tight.
