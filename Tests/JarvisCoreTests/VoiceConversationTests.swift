import XCTest
@testable import JarvisCore

final class VoiceConversationTests: XCTestCase {
    
    func testVoiceConversationCanBeCreated() {
        let conversation = VoiceConversation()
        XCTAssertNotNil(conversation, "VoiceConversation should be instantiable")
    }
    
    func testStartAndStopDoNotThrow() async throws {
        let conversation = VoiceConversation()
        try await conversation.start()
        try await conversation.stop()
    }
    
    func testSendMessageReturnsNonEmptyResponse() async throws {
        let conversation = VoiceConversation()
        try await conversation.start()
        let response = try await conversation.send(message: "Hello")
        XCTAssertNotNil(response, "Response should not be nil")
        XCTAssertFalse(response.isEmpty, "Response should not be empty")
        try await conversation.stop()
    }
    
    func testSpeakRealtimePropertyIsRemoved() {
        let conversation = VoiceConversation()
        let mirror = Mirror(reflecting: conversation)
        let hasSpeakRealtime = mirror.children.contains { $0.label == "speakRealtime" }
        XCTAssertFalse(hasSpeakRealtime, "VoiceConversation should not expose a speakRealtime property")
    }
}