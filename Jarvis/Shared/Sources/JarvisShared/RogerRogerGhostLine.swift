import Foundation

/// Roger Roger is the bidirectional intelligibility layer: capture, enhance,
/// understand, and respond when voice is the lifeline.
public enum RogerRogerMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case sentinel
    case pushToTalk = "push_to_talk"
    case fullDuplexLiveSpeech = "full_duplex_live_speech"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sentinel:
            return "Sentinel"
        case .pushToTalk:
            return "Push to Talk"
        case .fullDuplexLiveSpeech:
            return "Full Live Speech"
        }
    }

    public var watchLine: String {
        switch self {
        case .sentinel:
            return "Listening quietly. Haptics + watch text."
        case .pushToTalk:
            return "Hold to speak. Replies route by GhostLine."
        case .fullDuplexLiveSpeech:
            return "Live two-way audio channel."
        }
    }
}

/// GhostLine is the delivery fabric: choose where JARVIS voice/media renders
/// without making the operator hunt for the phone.
public enum GhostLineEndpoint: String, Codable, CaseIterable, Identifiable, Sendable {
    case elehearBeyond = "elehear_beyond"
    case watchSpeaker = "watch_speaker"
    case watchHapticsText = "watch_haptics_text"
    case iPhoneBroker = "iphone_broker"
    case iPadVeil = "ipad_veil"
    case macVeil = "mac_veil"
    case homePods = "homepods"
    case carPlay = "carplay"
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .elehearBeyond: return "Elehear Beyond"
        case .watchSpeaker: return "Watch Speaker"
        case .watchHapticsText: return "Watch Haptics/Text"
        case .iPhoneBroker: return "iPhone Broker"
        case .iPadVeil: return "iPad Veil"
        case .macVeil: return "Mac Veil"
        case .homePods: return "HomePods"
        case .carPlay: return "CarPlay"
        case .unknown: return "Unknown"
        }
    }
}

public struct RogerRogerSessionProfile: Codable, Equatable, Sendable {
    public let mode: RogerRogerMode
    public let preferredEndpoint: GhostLineEndpoint
    public let watchAvailable: Bool
    public let elehearPreferred: Bool
    public let updatedAtISO8601: String

    public init(
        mode: RogerRogerMode,
        preferredEndpoint: GhostLineEndpoint,
        watchAvailable: Bool,
        elehearPreferred: Bool,
        updatedAtISO8601: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.mode = mode
        self.preferredEndpoint = preferredEndpoint
        self.watchAvailable = watchAvailable
        self.elehearPreferred = elehearPreferred
        self.updatedAtISO8601 = updatedAtISO8601
    }

    public static let watchSentinel = RogerRogerSessionProfile(
        mode: .sentinel,
        preferredEndpoint: .watchHapticsText,
        watchAvailable: true,
        elehearPreferred: true
    )
}
