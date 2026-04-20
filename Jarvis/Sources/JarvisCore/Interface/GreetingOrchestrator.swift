import Foundation

/// Picks the greeting line and target surfaces for a presence event.
///
/// This is **pure logic** — no I/O, no side effects. All decisions are made
/// from the event + a clock. Ingress (webhook / tunnel action) and egress
/// (voice pipeline, HomePod broadcast, display bridges) are wired in by
/// `PresenceEventRouter`.
///
/// The orchestrator is the policy surface. It can be exercised in unit tests
/// without touching audio, network, or filesystem.
public struct JarvisGreetingPlan: Sendable, Equatable {
    public enum Surface: String, Sendable {
        /// Speak through the host's default audio output (goes to whatever
        /// AirPlay/HomePod group the Mac is currently routed to).
        case hostAudio = "host-audio"
        /// Push a visible greeting to Charlie's HomeKit intercom speaker chain.
        case homePodIntercom = "homepod-intercom"
        /// Show greeting card on the Lab TV.
        case labTV = "lab-tv"
        /// Show greeting card on the kitchen Echo Show via Alexa routine.
        case echoShowKitchen = "echo-show-kitchen"
        /// Show greeting card on the living-room Apple TV.
        case appleTVLivingRoom = "apple-tv-living-room"
        /// Show greeting card on the Fire TV stick.
        case fireTV = "fire-tv"
    }

    public let line: String
    public let surfaces: [Surface]
    public let suppressed: Bool
    public let suppressionReason: String?

    public init(line: String, surfaces: [Surface], suppressed: Bool = false, suppressionReason: String? = nil) {
        self.line = line
        self.surfaces = surfaces
        self.suppressed = suppressed
        self.suppressionReason = suppressionReason
    }

    public static func suppress(_ reason: String) -> JarvisGreetingPlan {
        JarvisGreetingPlan(line: "", surfaces: [], suppressed: true, suppressionReason: reason)
    }
}

public struct JarvisGreetingContext: Sendable {
    /// How long since the last time a greeting was delivered. `nil` means
    /// no prior greeting on record (boot / first event).
    public let timeSinceLastGreeting: TimeInterval?
    /// Current local time — used for time-of-day greeting flavour.
    public let now: Date
    /// Operator label (e.g. "Grizz"). Injected so the orchestrator never
    /// hardcodes identity.
    public let operatorLabel: String

    public init(timeSinceLastGreeting: TimeInterval?, now: Date = Date(), operatorLabel: String = "Grizz") {
        self.timeSinceLastGreeting = timeSinceLastGreeting
        self.now = now
        self.operatorLabel = operatorLabel
    }
}

public enum JarvisGreetingOrchestrator {
    /// Minimum interval between greetings for the same operator. Prevents
    /// greeting-loop on a noisy CSI sensor.
    public static let cooldownSeconds: TimeInterval = 5 * 60  // 5 minutes

    /// Decide whether — and how — to greet for this event.
    public static func plan(for event: JarvisPresenceEvent, context: JarvisGreetingContext) -> JarvisGreetingPlan {
        // Only `arrival` triggers a greeting. Other kinds flow to telemetry
        // but don't speak.
        guard event.kind == .arrival else {
            return .suppress("event-kind:\(event.kind.rawValue)")
        }

        // Cooldown: don't greet again within the last N minutes. Protects
        // against sensor flutter + multiple-sources firing on the same arrival.
        if let elapsed = context.timeSinceLastGreeting, elapsed < cooldownSeconds {
            return .suppress("cooldown:\(Int(elapsed))s<\(Int(cooldownSeconds))s")
        }

        // Mock source never actuates, even in tests that slip through.
        if event.source == .mock {
            return .suppress("source:mock")
        }

        // Low-confidence CSI events don't speak — they wait for corroboration.
        if event.source == .wifiCSI, let c = event.confidence, c < 0.6 {
            return .suppress("low-confidence:\(c)")
        }

        let greeting = greetingLine(operator: context.operatorLabel, at: context.now, source: event.source)

        // Surfaces: always speak on host audio + HomePod intercom. Echo Show /
        // Fire TV / Apple TV get a non-speech card so the visual layer mirrors
        // the audible greeting.
        let surfaces: [JarvisGreetingPlan.Surface] = [
            .hostAudio,
            .homePodIntercom,
            .labTV,
            .echoShowKitchen,
            .appleTVLivingRoom,
            .fireTV
        ]

        return JarvisGreetingPlan(line: greeting, surfaces: surfaces)
    }

    // MARK: - Greeting line

    static func greetingLine(operator name: String, at date: Date, source: JarvisPresenceSource) -> String {
        let hour = Calendar(identifier: .gregorian).component(.hour, from: date)
        let timeWord: String
        switch hour {
        case 5..<12:  timeWord = "morning"
        case 12..<17: timeWord = "afternoon"
        case 17..<22: timeWord = "evening"
        default:      timeWord = "night"
        }

        // Tone follows JARVIS canon: dry, warm, competent, not sycophantic.
        // Source is surfaced in the line for operator transparency — Grizz
        // should always be able to hear which sensor called it.
        let sourceTag: String
        switch source {
        case .wifiCSI:          sourceTag = "via Wi-Fi CSI"
        case .homeKitGeofence:  sourceTag = "via HomeKit arrival"
        case .iOSShortcut:      sourceTag = "via your Shortcut"
        case .manual:           sourceTag = "on manual cue"
        case .mock:             sourceTag = "in test mode"
        }

        return "Good \(timeWord), \(name). Welcome home. Picked you up \(sourceTag)."
    }
}
