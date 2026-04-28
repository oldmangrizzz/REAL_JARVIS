import Foundation
import SwiftUI

@MainActor
public final class JarvisWatchCockpitStore: ObservableObject {
    @Published public private(set) var connectionState: JarvisConnectionState = .disconnected
    @Published public private(set) var state = JarvisSharedState(snapshot: nil, thoughts: [], signals: [], pendingPushDirectives: [])
    @Published public private(set) var diagnostics = ""
    @Published public private(set) var rogerRogerProfile: RogerRogerSessionProfile = .watchSentinel

    public let vitals = JarvisWatchVitalMonitor()

    private let configuration: JarvisHostConfiguration
    private let registration: JarvisClientRegistration
    private let convex: JarvisConvexSyncClient
    private var started = false
    private lazy var tunnel: JarvisTunnelClient = {
        JarvisTunnelClient(
            config: configuration,
            registration: registration,
            onMessage: { [weak self] message in
                Task { @MainActor in
                    self?.receive(message: message)
                }
            },
            onStateChange: { [weak self] state, message in
                Task { @MainActor in
                    self?.connectionState = state
                    if let message, !message.isEmpty {
                        self?.diagnostics = message
                    }
                }
            }
        )
    }()

    public init(bundle: Bundle = .main) {
        let configuration = JarvisHostConfiguration.load(from: bundle, role: .watch)
        let registration = JarvisDeviceIdentity.registration(role: .watch, bundle: bundle)
        self.configuration = configuration
        self.registration = registration
        self.convex = JarvisConvexSyncClient(configuration: configuration)
    }

    public func start() async {
        guard !started else {
            await refresh()
            return
        }
        started = true
        if configuration.canConnectTunnel {
            tunnel.connect()
        } else {
            connectionState = .disconnected
            diagnostics = configuration.tunnelConfigurationError ?? "Tunnel configuration is incomplete."
        }
        await vitals.start()

        do {
            try await convex.registerDevice(registration)
            try await convex.heartbeat(registration: registration, state: connectionState, pushToken: nil)
        } catch {
            diagnostics = error.localizedDescription
        }

        await refresh()
    }

    public func refresh() async {
        await vitals.refresh()
        do {
            state = try await convex.fetchSharedState(limit: 6)
        } catch {
            diagnostics = error.localizedDescription
        }
    }

    public func perform(action: JarvisRemoteAction) {
        diagnostics = "Command execution is restricted to the Obsidian Command Bar and terminal."
    }

    public func startupVoice() {
        diagnostics = "Voice startup remains gated behind the Obsidian Command Bar and terminal."
    }

    public func setRogerRogerMode(_ mode: RogerRogerMode) {
        let endpoint: GhostLineEndpoint
        switch mode {
        case .sentinel:
            endpoint = .watchHapticsText
        case .pushToTalk:
            endpoint = .watchSpeaker
        case .fullDuplexLiveSpeech:
            endpoint = .elehearBeyond
        }

        let profile = RogerRogerSessionProfile(
            mode: mode,
            preferredEndpoint: endpoint,
            watchAvailable: true,
            elehearPreferred: true
        )
        rogerRogerProfile = profile
        diagnostics = "\(mode.displayName): \(mode.watchLine)"

        if let data = try? JSONEncoder().encode(profile),
           let payload = String(data: data, encoding: .utf8) {
            tunnel.send(JarvisRemoteCommand(action: .rogerRogerMode, payloadJSON: payload, source: "watch"))
        }
    }

    private func receive(message: JarvisTunnelMessage) {
        switch message.kind {
        case .snapshot:
            if let snapshot = message.snapshot {
                state = JarvisSharedState(snapshot: snapshot, thoughts: snapshot.recentThoughts, signals: snapshot.recentSignals, pendingPushDirectives: [])
            }
        case .response:
            if let response = message.response, let snapshot = response.snapshot {
                state = JarvisSharedState(snapshot: snapshot, thoughts: snapshot.recentThoughts, signals: snapshot.recentSignals, pendingPushDirectives: [])
            }
        case .error:
            diagnostics = message.error ?? "Unknown watch tunnel error."
        case .register, .command, .push, .heartbeat:
            break
        }
    }
}
