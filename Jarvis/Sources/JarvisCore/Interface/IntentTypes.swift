import Foundation

public enum JarvisIntent: Sendable {
    case displayAction(target: String, action: String, parameters: [String: String])
    case homeKitControl(accessoryName: String, characteristic: String, value: String)
    case systemQuery(query: String)
    case skillInvocation(skillName: String, payload: [String: Any])
    case unknown(rawTranscript: String)
}

public struct ParsedIntent: Sendable {
    public let intent: JarvisIntent
    public let confidence: Double
    public let rawTranscript: String
    public let timestamp: String

    public init(intent: JarvisIntent, confidence: Double, rawTranscript: String, timestamp: String) {
        self.intent = intent
        self.confidence = confidence
        self.rawTranscript = rawTranscript
        self.timestamp = timestamp
    }
}
