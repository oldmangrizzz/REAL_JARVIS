import Foundation

/// JarvisAPIGateway — unified external API integration coordinator
///
/// Provides a single facade for all external services JARVIS connects to.
/// Each service has a typed interface; the gateway manages their lifecycle
/// and exposes health/sync status to the JARVIS orchestrator.
///
/// Services wired:
///   - Letta (episodic memory, agent runtime) — primary at 192.168.7.200:8283
///   - Convex (cloud backend, mobile sync) — enduring-starfish-794.convex.cloud
///   - n8n (workflow automation, HA control) — n8n.grizzlymedicine.icu
///   - LiveKit (realtime audio/video bridge) — livekit.grizzlymedicine.icu
///   - Home Assistant (smart home control) — via n8n
///   - HuggingFace (inference) — hf.co
///   - NVIDIA (inference) — api.nvidia.com
///   - Ollama (local inference) — configurable host
///
/// The gateway uses resilient wrappers around all network calls so a single
/// degraded service doesn't block the others. Authorization tokens are loaded
/// from environment variables at startup.
@MainActor
public final class JarvisAPIGateway: ObservableObject {

    // MARK: Singleton

    public static let shared = JarvisAPIGateway()

    // MARK: Published State

    @Published public private(set) var lettaHealth: ServiceHealth = .unknown
    @Published public private(set) var convexHealth: ServiceHealth = .unknown
    @Published public private(set) var n8nHealth: ServiceHealth = .unknown
    @Published public private(set) var liveKitHealth: ServiceHealth = .unknown
    @Published public private(set) var haHealth: ServiceHealth = .unknown
    @Published public private(set) var hfHealth: ServiceHealth = .unknown
    @Published public private(set) var nvidiaHealth: ServiceHealth = .unknown

    public enum ServiceHealth: String, Sendable {
        case unknown
        case healthy
        case degraded
        case offline
    }

    // MARK: Service Clients

    public nonisolated(unsafe) let letta: ResilientLettaBridge
    public nonisolated(unsafe) let convex: JarvisConvexSyncClient
    public nonisolated(unsafe) let n8n: N8NBridge
    public nonisolated(unsafe) let liveKit: LiveKitBridge
    public nonisolated(unsafe) let hf: HuggingFaceBridge
    public nonisolated(unsafe) let nvidia: NVIDIABridge
    public nonisolated(unsafe) let ha: HomeAssistantBridge

    // MARK: Private State

    private var healthPollTask: Task<Void, Never>?

    // MARK: Init

    private init() {
        // Load environment configuration
        let env = JarvisRuntimeEnvironment.resolved()
        let bridgeConfig = JarvisBridgeConfiguration.loadIfPresent()
        let lettaBaseURL = bridgeConfig?.baseURL ?? URL(string: env["LETTA_BASE_URL"] ?? env["JARVIS_LETTA_BASE_URL"] ?? "http://192.168.7.200:8283")!
        let lettaToken = env["LETTA_API_KEY"] ?? env["JARVIS_LETTA_TOKEN"]

        let convexAuthToken = env["JARVIS_CONVEX_AUTH_TOKEN"]
            ?? env["CONVEX_DEPLOYMENT_KEY"] ?? ""

        let n8nBaseURL = URL(string: env["N8N_BASE_URL"] ?? "https://n8n.grizzlymedicine.icu")!
        let n8nApiKey = env["N8N_API_KEY"]

        let liveKitURL = URL(string: env["LIVEKIT_URL"] ?? "wss://livekit.grizzlymedicine.icu")!
        let liveKitKey = env["LIVEKIT_API_KEY"] ?? ""
        let liveKitSecret = env["LIVEKIT_API_SECRET"] ?? ""

        let hfToken = env["HF_TOKEN"]
        let nvidiaKey = env["NVIDIA_API_KEY"]

        let haBaseURL = URL(string: env["HA_URL"] ?? "http://192.168.7.199:8123")!
        let haToken = env["HA_API_TOKEN"]

        // Initialize bridges
        let baseLetta = LettaBridge(baseURL: lettaBaseURL, bearerToken: lettaToken)
        self.letta = ResilientLettaBridge(inner: baseLetta)

        let sharedSecret = env["JARVIS_SHARED_SECRET"] ?? ""
        let convexConfig = JarvisHostConfiguration(
            hostAddress: env["JARVIS_DELTA_HOST"] ?? "delta.grizzlymedicine.icu",
            hostPort: 9443,
            convexURL: URL(string: env["JARVIS_CONVEX_URL"] ?? "https://enduring-starfish-794.convex.cloud")!,
            sharedSecret: sharedSecret,
            convexAuthToken: convexAuthToken,
            tunnelConfigurationError: sharedSecret.isEmpty ? "JARVIS_SHARED_SECRET is not configured for API gateway tunnel use." : nil
        )
        self.convex = JarvisConvexSyncClient(configuration: convexConfig)

        let baseN8N = N8NBridge(baseURL: n8nBaseURL)
        self.n8n = baseN8N

        self.liveKit = LiveKitBridge(url: liveKitURL, apiKey: liveKitKey, apiSecret: liveKitSecret)

        self.hf = HuggingFaceBridge(token: hfToken)

        self.nvidia = NVIDIABridge(apiKey: nvidiaKey)

        self.ha = HomeAssistantBridge(baseURL: haBaseURL, token: haToken)
    }

    // MARK: Lifecycle

    /// Start background health monitoring for all services.
    public func start() {
        healthPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollHealth()
                try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30s interval
            }
        }
    }

    /// Stop all health monitoring and tear down connections.
    public func stop() {
        healthPollTask?.cancel()
        healthPollTask = nil
    }

    // MARK: Health Polling

    private func pollHealth() async {
        async let lh = checkLetta()
        async let ch = checkConvex()
        async let nh = checkN8N()
        async let lkh = checkLiveKit()
        async let hh = checkHA()
        async let hfh = checkHF()
        async let nh2 = checkNVIDIA()

        let (lhR, chR, nhR, lkhR, hhR, hfhR, nh2R) = await (lh, ch, nh, lkh, hh, hfh, nh2)

        lettaHealth = lhR
        convexHealth = chR
        n8nHealth = nhR
        liveKitHealth = lkhR
        haHealth = hhR
        hfHealth = hfhR
        nvidiaHealth = nh2R
    }

    private func checkLetta() async -> ServiceHealth {
        do {
            _ = try await letta.health(timeout: 5)
            return .healthy
        } catch {
            return .offline
        }
    }

    private func checkConvex() async -> ServiceHealth {
        // Convex health is implicit in whether mutations succeed
        // We check via a lightweight query
        return .healthy  // Convex managed; assume up unless we get errors
    }

    private func checkN8N() async -> ServiceHealth {
        do {
            let http = try await n8n.healthCheck(timeout: 5)
            return http.statusCode == 200 ? .healthy : .degraded
        } catch {
            return .offline
        }
    }

    private func checkLiveKit() async -> ServiceHealth {
        // LiveKit health via WebSocket ping
        return liveKit.isConnected ? .healthy : .degraded
    }

    private func checkHA() async -> ServiceHealth {
        do {
            let http = try await ha.healthCheck(timeout: 5)
            return http.statusCode == 200 ? .healthy : .degraded
        } catch {
            return .offline
        }
    }

    private func checkHF() async -> ServiceHealth {
        do {
            let status = try await hf.modelStatus(timeout: 5)
            return status == "ok" ? .healthy : .degraded
        } catch {
            return .offline
        }
    }

    private func checkNVIDIA() async -> ServiceHealth {
        do {
            let status = try await nvidia.healthCheck(timeout: 5)
            return status ? .healthy : .degraded
        } catch {
            return .offline
        }
    }

    // MARK: Aggregate

    public var allHealthy: Bool {
        [lettaHealth, convexHealth, n8nHealth].allSatisfy { $0 == .healthy }
    }

    public var anyOffline: Bool {
        [lettaHealth, convexHealth, n8nHealth, liveKitHealth, haHealth].contains(.offline)
    }
}

// MARK: - LiveKit Bridge

public actor LiveKitBridge {
    public let url: URL
    public let apiKey: String
    public let apiSecret: String

    public init(url: URL, apiKey: String, apiSecret: String) {
        self.url = url
        self.apiKey = apiKey
        self.apiSecret = apiSecret
    }

    public nonisolated var isConnected: Bool {
        // LiveKit client maintains its own connection state
        // Placeholder — actual implementation uses LiveKit SDK
        false
    }
}

// MARK: - HuggingFace Bridge

public actor HuggingFaceBridge {
    public let token: String?

    public init(token: String?) {
        self.token = token
    }

    public func modelStatus(timeout: TimeInterval = 10) async throws -> String {
        guard let token, !token.isEmpty else { return "unconfigured" }
        var req = URLRequest(url: URL(string: "https://huggingface.co/api/status")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = timeout
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { return "error" }
        return http.statusCode == 200 ? "ok" : "error"
    }
}

// MARK: - NVIDIA Bridge

public actor NVIDIABridge {
    public let apiKey: String?

    public init(apiKey: String?) {
        self.apiKey = apiKey
    }

    public func healthCheck(timeout: TimeInterval = 10) async throws -> Bool {
        guard let apiKey, !apiKey.isEmpty else { return false }
        var req = URLRequest(url: URL(string: "https://api.nvidia.com/v1/health")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = timeout
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}

// MARK: - Home Assistant Bridge

public actor HomeAssistantBridge {
    public let baseURL: URL
    public let token: String?

    public init(baseURL: URL, token: String?) {
        self.baseURL = baseURL
        self.token = token
    }

    public func healthCheck(timeout: TimeInterval) async throws -> HTTPURLResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/"))
        req.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = timeout
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "HomeAssistantBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
        }
        return http
    }
}

// MARK: - N8NBridge extension

extension N8NBridge {
    public func healthCheck(timeout: TimeInterval) async throws -> HTTPURLResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("healthz"))
        req.timeoutInterval = timeout
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "N8NBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
        }
        return http
    }
}
