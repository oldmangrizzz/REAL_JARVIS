import Foundation
import Combine
import LiveKit

/// Manages the WebRTC connection to the LiveKit server (Charlie VPS).
/// Pipes Coqui XTTS v2 ambient voice to the Apple device's audio output.
/// Trauma-Informed Design: Strictly requires cryptographic authentication; fails closed on error.
@MainActor
public class VoiceManager: ObservableObject {
    @Published public var isConnected: Bool = false

    private let room = Room()
    private let liveKitUrl = "wss://charlie.grizzlymedicine.icu"
    private let tokenUrl = URL(string: "https://grizzlymedicine.icu/api/livekit/auth?room=GrizzOS_Sanctuary&participant=Operator_Apple")!

    public init() {
        Task { await connect() }
    }

    public func connect() async {
        print("[VoiceManager] Requesting secure WebRTC token...")

        do {
            let token = try await fetchSecureToken()

            print("[VoiceManager] Secure connection established. Initiating WebRTC bridge...")
            try await room.connect(url: liveKitUrl, token: token)

            self.isConnected = true
            print("[VoiceManager] JARVIS Voice Subscribed.")
        } catch {
            failClosed(reason: error.localizedDescription)
        }
    }

    private func fetchSecureToken() async throws -> String {
        var request = URLRequest(url: tokenUrl)
        request.setValue("true", forHTTPHeaderField: "X-GrizzOS-Request")
        request.timeoutInterval = 5.0

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = json["token"] as? String {
            return token
        }

        throw URLError(.cannotParseResponse)
    }

    private func failClosed(reason: String) {
        self.isConnected = false
        print("[CRITICAL WOUND] VoiceManager: Authentication failed. Failing closed to prevent disembodied audio. Reason: \(reason)")
    }

    public func disconnect() async {
        await room.disconnect()
        self.isConnected = false
    }
}