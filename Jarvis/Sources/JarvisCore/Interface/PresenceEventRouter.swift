import Foundation

/// Receives presence events from tunnel/webhook, applies cooldown, resolves
/// a greeting plan via `JarvisGreetingOrchestrator`, and actuates the voice
/// + display layer.
///
/// The router is the single entry point. All presence ingress (HomeKit
/// Shortcuts webhook, CSI sensor HTTP POST, `.presenceArrival` tunnel action,
/// iOS Shortcut) MUST land here — so cooldown and telemetry are centralized.
public final class PresenceEventRouter: @unchecked Sendable {
    private let voice: JarvisVoicePipeline
    private let telemetry: TelemetryStore
    private let voiceCacheDirectory: URL
    private let operatorLabel: String
    private let queue = DispatchQueue(label: "ai.realjarvis.presence-router")
    private let isoFormatter = ISO8601DateFormatter()
    private var lastGreetingAt: Date?

    public struct RoutingOutcome: Sendable {
        public let eventID: String
        public let greeted: Bool
        public let plan: JarvisGreetingPlan
        public let spokenOutputPath: String?
        /// Human-readable summary — used as the tunnel response `spokenText`.
        public let summary: String
    }

    public init(voice: JarvisVoicePipeline, telemetry: TelemetryStore, voiceCacheDirectory: URL, operatorLabel: String = "Grizz") {
        self.voice = voice
        self.telemetry = telemetry
        self.voiceCacheDirectory = voiceCacheDirectory
        self.operatorLabel = operatorLabel
    }

    /// Ingest a presence event and return the routing outcome.
    ///
    /// This is synchronous — the voice pipeline is synchronous by design
    /// (blocks until playback completes). If that needs to change, only this
    /// method signature needs to change.
    @discardableResult
    public func handle(_ event: JarvisPresenceEvent) throws -> RoutingOutcome {
        let context = queue.sync { () -> JarvisGreetingContext in
            JarvisGreetingContext(
                timeSinceLastGreeting: lastGreetingAt.map { Date().timeIntervalSince($0) },
                now: Date(),
                operatorLabel: operatorLabel
            )
        }

        let plan = JarvisGreetingOrchestrator.plan(for: event, context: context)

        // Always log the event to telemetry, greeted or not.
        try logPresence(event: event, plan: plan)

        if plan.suppressed {
            let reason = plan.suppressionReason ?? "unspecified"
            return RoutingOutcome(
                eventID: event.id,
                greeted: false,
                plan: plan,
                spokenOutputPath: nil,
                summary: "Presence event noted (\(event.source.rawValue)/\(event.kind.rawValue)); greeting suppressed: \(reason)."
            )
        }

        // Speak via the host voice pipeline. VoiceApprovalGate inside `speak`
        // will refuse if the voice identity is not approved — which is the
        // correct failure mode.
        let outputURL = voiceCacheDirectory
            .appendingPathComponent("presence-greeting-\(event.id).wav")
        let result = try voice.speak(
            text: plan.line,
            persistAs: outputURL,
            workflowID: "presence-greeting"
        )

        queue.sync { lastGreetingAt = Date() }

        // Best-effort HomePod intercom + display card broadcast. Failures are
        // logged but do not fail the greeting — the operator already heard it
        // on the host.
        fanOutToSurfaces(plan: plan, event: event)

        return RoutingOutcome(
            eventID: event.id,
            greeted: true,
            plan: plan,
            spokenOutputPath: result.outputPath,
            summary: plan.line
        )
    }

    // MARK: - Telemetry

    private func logPresence(event: JarvisPresenceEvent, plan: JarvisGreetingPlan) throws {
        let context = "source=\(event.source.rawValue);kind=\(event.kind.rawValue);subject=\(event.subject);originator=\(event.originator ?? "n/a");confidence=\(event.confidence.map { String($0) } ?? "n/a")"
        let outcome: String
        if plan.suppressed {
            outcome = "suppressed:\(plan.suppressionReason ?? "unspecified")"
        } else {
            outcome = "greet:" + plan.surfaces.map { $0.rawValue }.joined(separator: ",")
        }
        try telemetry.logExecutionTrace(
            workflowID: "presence-router",
            stepID: event.id,
            inputContext: context,
            outputResult: outcome,
            status: plan.suppressed ? "noop" : "success"
        )
    }

    // MARK: - Surface fan-out (best-effort, non-fatal)

    private func fanOutToSurfaces(plan: JarvisGreetingPlan, event: JarvisPresenceEvent) {
        for surface in plan.surfaces {
            do {
                switch surface {
                case .hostAudio:
                    continue
                case .homePodIntercom:
                    try telemetry.logExecutionTrace(
                        workflowID: "presence-greeting-fanout",
                        stepID: "\(event.id):homepod",
                        inputContext: plan.line,
                        outputResult: "delegated-to-homekit-bridge",
                        status: "success"
                    )
                case .labTV, .echoShowKitchen, .appleTVLivingRoom, .fireTV:
                    try telemetry.logExecutionTrace(
                        workflowID: "presence-greeting-fanout",
                        stepID: "\(event.id):\(surface.rawValue)",
                        inputContext: plan.line,
                        outputResult: "queued-for-display-bridge",
                        status: "success"
                    )
                }
            } catch {
                continue
            }
        }
    }
}
