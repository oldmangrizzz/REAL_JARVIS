import Foundation
import SwiftUI

@MainActor
public final class JarvisMacCockpitStore: ObservableObject {
    private final class BundleToken {}

    @Published public private(set) var connectionState: JarvisConnectionState = .disconnected
    @Published public private(set) var state = JarvisSharedState(snapshot: nil, thoughts: [], signals: [], pendingPushDirectives: [])
    @Published public private(set) var diagnostics = ""

    public let role: JarvisDeviceRole = .macDesktop

    public var voiceGate: JarvisVoiceGateSnapshot? {
        state.snapshot?.voiceGate
    }

    public var spatialHUD: [JarvisSpatialHUDElement] {
        state.snapshot?.spatialHUD ?? []
    }

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
        let configuration = JarvisHostConfiguration.load(from: bundle, role: .macDesktop)
        let registration = JarvisDeviceIdentity.registration(role: .macDesktop, bundle: bundle)
        self.configuration = configuration
        self.registration = registration
        self.convex = JarvisConvexSyncClient(configuration: configuration)
    }

    public func start() async {
        guard !started else {
            await refreshSharedState()
            await consumePendingInputs()
            return
        }
        started = true
        tunnel.connect()

        do {
            try await convex.registerDevice(registration)
            try await convex.heartbeat(registration: registration, state: connectionState, pushToken: UserDefaults.standard.string(forKey: "jarvis.mac.push-token"))
        } catch {
            diagnostics = error.localizedDescription
        }

        await refreshSharedState()
        await consumePendingInputs()
    }

    public func refreshSharedState() async {
        do {
            state = try await convex.fetchSharedState(limit: 8)
        } catch {
            diagnostics = error.localizedDescription
        }
    }

    public func perform(action: JarvisRemoteAction, text: String? = nil, skillName: String? = nil, payloadJSON: String? = nil) async {
        diagnostics = "Command execution is restricted to the Obsidian Command Bar and terminal."
    }

    public func receive(push: JarvisPushDirective) async {
        JarvisPendingActionStore.store(push: push)
        do {
            try await convex.log(push: push, registration: registration)
        } catch {
            diagnostics = error.localizedDescription
        }
        if push.requiresSpeech {
            await speak(line: push.startupLine)
        }
        await refreshSharedState()
    }

    private func receive(message: JarvisTunnelMessage) {
        switch message.kind {
        case .snapshot:
            if let snapshot = message.snapshot {
                state = JarvisSharedState(snapshot: snapshot, thoughts: snapshot.recentThoughts, signals: snapshot.recentSignals, pendingPushDirectives: state.pendingPushDirectives)
            }
        case .response:
            if let response = message.response {
                if let snapshot = response.snapshot {
                    state = JarvisSharedState(snapshot: snapshot, thoughts: snapshot.recentThoughts, signals: snapshot.recentSignals, pendingPushDirectives: state.pendingPushDirectives)
                }
            }
        case .push:
            if let push = message.push {
                Task {
                    await receive(push: push)
                }
            }
        case .error:
            diagnostics = message.error ?? "Unknown tunnel error."
        case .register, .command, .heartbeat:
            break
        }
    }

    private func consumePendingInputs() async {
        if let command = JarvisPendingActionStore.consumeCommand() {
            diagnostics = "Discarded unauthorized pending command from \(command.source ?? "unknown source")."
        }
        if let push = JarvisPendingActionStore.consumePush() {
            await receive(push: push)
        }
    }

    private func speak(line: String) async {
        print("[MAC] Voice output: \(line)")
    }
}
