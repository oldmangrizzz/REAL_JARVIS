import Foundation
import SwiftUI

/// Read-only cockpit store for Apple TV. The tvOS cockpit surfaces the same
/// `JarvisHostSnapshot` the Mac / iPad / iPhone stores render, but it never
/// issues control commands — tvOS is a spectator surface. Control authority
/// belongs to the Mac host (echo) plus the voice-operator role from SPEC-007.
///
/// Non-DOM by construction: pure SwiftUI + URLSession. No WebView shims.
@MainActor
public final class JarvisTVCockpitStore: ObservableObject {
    @Published public private(set) var status: String = "connecting"
    @Published public private(set) var voiceGateState: String = "unknown"
    @Published public private(set) var activeHUD: String = "—"
    @Published public private(set) var lastUpdate: Date?

    public var hostURL: URL = URL(string: "http://echo.local:19480")!
    public var sharedSecret: String = ""

    private var pollTask: Task<Void, Never>?

    public init() {}

    public func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollOnce() async {
        var req = URLRequest(url: hostURL.appendingPathComponent("snapshot"))
        req.setValue("Bearer \(sharedSecret)", forHTTPHeaderField: "Authorization")
        req.setValue("apple-tv-cockpit/1.0", forHTTPHeaderField: "X-Jarvis-Client")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                status = (obj["status"] as? String) ?? status
                voiceGateState = (obj["voiceGateState"] as? String) ?? voiceGateState
                activeHUD = (obj["activeHUD"] as? String) ?? activeHUD
                lastUpdate = Date()
            }
        } catch {
            status = "offline"
        }
    }
}

public struct JarvisTVCockpitView: View {
    @ObservedObject public var store: JarvisTVCockpitStore

    public init(store: JarvisTVCockpitStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 32) {
            Text("REAL JARVIS — Cockpit")
                .font(.system(size: 64, weight: .bold, design: .rounded))
            HStack(spacing: 48) {
                pill(label: "Status", value: store.status)
                pill(label: "Voice Gate", value: store.voiceGateState)
                pill(label: "Active HUD", value: store.activeHUD)
            }
            if let last = store.lastUpdate {
                Text("last update: \(last.formatted(date: .omitted, time: .standard))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(80)
        .onAppear { store.start() }
        .onDisappear { store.stop() }
    }

    private func pill(label: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(label).font(.title3).foregroundStyle(.secondary)
            Text(value).font(.system(size: 48, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
    }
}
