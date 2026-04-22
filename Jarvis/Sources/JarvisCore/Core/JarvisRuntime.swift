import Foundation

public final class JarvisRuntime {
    public let paths: WorkspacePaths
    public let telemetry: TelemetryStore
    public let pheromind: PheromindEngine
    public let memory: MemoryEngine
    public let pythonRLM: PythonRLMBridge
    public let retrievalBridge: ContextualRetrievalBridge
    public let voice: JarvisVoicePipeline
    public let metaHarness: MetaHarness
    public let controlPlane: MyceliumControlPlane
    public let oscillator: MasterOscillator
    public let phaseLock: PhaseLockMonitor
    public let telemetrySync: ConvexTelemetrySync
    public let physics: PhysicsEngine
    public let physicsSummarizer: PhysicsSummarizer
    public let arcBridge: ARCHarnessBridge
    public let presenceRouter: PresenceEventRouter
    public let lettaBridge: ResilientLettaBridge?

    public init(paths: WorkspacePaths) throws {
        self.paths = paths
        try paths.ensureSupportDirectories()
        self.telemetry = try TelemetryStore(paths: paths)
        let aox4 = AOxFourProbe(paths: paths, telemetry: telemetry)
        try aox4.requireFullOrientation()
        self.pheromind = PheromindEngine(telemetry: telemetry)
        self.memory = try MemoryEngine(paths: paths, telemetry: telemetry)
        self.pythonRLM = PythonRLMBridge(paths: paths, telemetry: telemetry)
        self.retrievalBridge = ContextualRetrievalBridge(memory: memory, pheromind: pheromind)
        self.voice = JarvisVoicePipeline(paths: paths, telemetry: telemetry)
        self.metaHarness = MetaHarness(paths: paths, telemetry: telemetry)
        self.controlPlane = try MyceliumControlPlane(paths: paths, telemetry: telemetry)
        self.oscillator = MasterOscillator(telemetry: telemetry)
        self.phaseLock = PhaseLockMonitor(telemetry: telemetry)
        self.telemetrySync = try ConvexTelemetrySync(paths: paths)
        self.physics = StubPhysicsEngine()
        self.physicsSummarizer = PhysicsSummarizer()
        self.arcBridge = ARCHarnessBridge(
            broadcasterURL: URL(string: "ws://localhost:8765")!,
            telemetry: telemetry,
            engine: self.physics
        )
        self.presenceRouter = PresenceEventRouter(
            voice: self.voice,
            telemetry: self.telemetry,
            voiceCacheDirectory: paths.voiceCacheDirectory
        )
        self.lettaBridge = Self.makeLettaBridge()
        Task.detached { [telemetrySync] in
            await telemetrySync.start()
        }
    }

    private static func makeLettaBridge() -> ResilientLettaBridge? {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["JARVIS_LETTA_BASE_URL"],
              let url = URL(string: raw) else {
            return nil
        }
        // H2: Letta exclusivity preflight. The Letta server on Alpha LXC 201
        // stores episodic memory for a *digital person* (see PRINCIPLES.md §1,
        // Natural-Language Barrier). If that same Letta instance is shared
        // with any other persona/project the substrate-merger invariant is
        // violated. We require operator attestation via env var. Default
        // (unset / not "true") disables the bridge; memory stays local in
        // .jarvis/storage/ via MemoryEngine.
        let exclusive = (env["JARVIS_LETTA_EXCLUSIVE"] ?? "").lowercased()
        guard exclusive == "true" || exclusive == "1" || exclusive == "yes" else {
            return nil
        }
        let inner = LettaBridge(baseURL: url, bearerToken: env["JARVIS_LETTA_TOKEN"])
        return ResilientLettaBridge(inner: inner)
    }
}
