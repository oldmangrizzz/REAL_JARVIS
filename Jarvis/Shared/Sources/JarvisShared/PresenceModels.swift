import Foundation

/// Source of a presence event. Informs downstream policy (e.g. CSI-only events
/// stay inside the lab network; HomeKit geofence is trusted for "operator
/// arrived home" semantics; manual events are explicit operator overrides).
public enum JarvisPresenceSource: String, Codable, Sendable, CaseIterable {
    /// Wi-Fi CSI extraction (Nexmon, esp-csi, ASUS AiMesh, etc.). Local LAN only.
    case wifiCSI = "wifi-csi"
    /// HomeKit "Person Arrives/Leaves Home" automation → webhook.
    case homeKitGeofence = "homekit-geofence"
    /// iOS / watchOS Shortcut triggered manually (e.g. "I'm walking in").
    case iOSShortcut = "ios-shortcut"
    /// Operator typed `jarvis greet me` or similar manual override.
    case manual
    /// Test harness or recorded replay. Never triggers actuation in production.
    case mock
}

public enum JarvisPresenceKind: String, Codable, Sendable, CaseIterable {
    /// Operator crossed into the home perimeter / walked through the door.
    case arrival
    /// Operator left the perimeter.
    case departure
    /// Passive presence (still at home, heartbeat).
    case presence
    /// Explicit absence (no one home).
    case absence
}

/// A presence signal carried over the tunnel or webhook. This is the **input**
/// to the greeting orchestrator; it is NOT itself an actuation.
public struct JarvisPresenceEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let source: JarvisPresenceSource
    public let kind: JarvisPresenceKind
    /// Who the event is about. Defaults to "operator" — the house operator.
    /// Future expansion: per-person presence.
    public let subject: String
    /// Optional device/sensor identifier that originated the event
    /// (e.g. `foxtrot-csi-01`, `iphone-grizz`).
    public let originator: String?
    /// Confidence 0.0 — 1.0. CSI events should include this; HomeKit geofence
    /// may report `nil`.
    public let confidence: Double?
    /// ISO-8601 timestamp from the source.
    public let observedAtISO8601: String
    /// Free-form notes (e.g. which door, signal strength, etc.).
    public let notes: String?
    /// SPEC-009: server-presumed principal for this presence event. Only
    /// set when the ingress source is trustworthy enough to bind identity
    /// (HomeKit geofence on operator's phone, iOS Shortcut from operator's
    /// device, manual `jarvis greet me`). Bare CSI / sensor presence
    /// leaves this nil because they can detect a body without knowing
    /// whose body. Threaded into telemetry for evidence-corpus witness.
    public let presumedPrincipal: Principal?

    public init(
        id: String = UUID().uuidString,
        source: JarvisPresenceSource,
        kind: JarvisPresenceKind,
        subject: String = "operator",
        originator: String? = nil,
        confidence: Double? = nil,
        observedAtISO8601: String,
        notes: String? = nil,
        presumedPrincipal: Principal? = nil
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.subject = subject
        self.originator = originator
        self.confidence = confidence
        self.observedAtISO8601 = observedAtISO8601
        self.notes = notes
        self.presumedPrincipal = presumedPrincipal
    }
}
