import AVFoundation
import Foundation
import Speech

public struct VoiceCommandResponse {
    public let spokenText: String
    public let details: [String: Any]
    public let shouldShutdown: Bool
}

private final class AwaitSyncBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var success: T?
    private var failure: Error?
    func setSuccess(_ value: T) { lock.lock(); success = value; lock.unlock() }
    func setFailure(_ error: Error) { lock.lock(); failure = error; lock.unlock() }
    func result() throws -> T {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        guard let success else { fatalError("AwaitSyncBox resolved without value") }
        return success
    }
}

public final class VoiceCommandRouter {
    private let runtime: JarvisRuntime
    private let registry: JarvisSkillRegistry
    private let intentParser: IntentParser?
    private let displayExecutor: DisplayCommandExecutor?
    private let capabilityRegistry: CapabilityRegistry?
    private let systemHandler: SystemCommandHandler
    private let rateLimiter: CommandRateLimiter
    private let destructiveGuard: DestructiveIntentGuard
    private let companionPolicy: CompanionCapabilityPolicy

    public init(runtime: JarvisRuntime, registry: JarvisSkillRegistry) {
        self.runtime = runtime
        self.registry = registry
        self.intentParser = nil
        self.displayExecutor = nil
        self.capabilityRegistry = nil
        self.systemHandler = SystemCommandHandler(runtime: runtime, skillRegistry: registry)
        self.rateLimiter = CommandRateLimiter()
        self.destructiveGuard = DestructiveIntentGuard()
        self.companionPolicy = CompanionCapabilityPolicy()
    }

    public init(
        runtime: JarvisRuntime,
        registry: JarvisSkillRegistry,
        intentParser: IntentParser,
        displayExecutor: DisplayCommandExecutor,
        capabilityRegistry: CapabilityRegistry,
        rateLimiter: CommandRateLimiter = CommandRateLimiter(),
        destructiveGuard: DestructiveIntentGuard = DestructiveIntentGuard(),
        companionPolicy: CompanionCapabilityPolicy = CompanionCapabilityPolicy()
    ) {
        self.runtime = runtime
        self.registry = registry
        self.intentParser = intentParser
        self.displayExecutor = displayExecutor
        self.capabilityRegistry = capabilityRegistry
        self.systemHandler = SystemCommandHandler(runtime: runtime, skillRegistry: registry)
        self.rateLimiter = rateLimiter
        self.destructiveGuard = destructiveGuard
        self.companionPolicy = companionPolicy
    }

    /// SPEC-009: `principal` is required — the router refuses to guess. Call
    /// sites that historically had no principal awareness should pass the
    /// principal resolved from the connected session (tunnel registration)
    /// or from SpeakerIdentifier for local-mic audio. Use `.guestTier` if
    /// the principal cannot be resolved (fail-closed).
    public func route(transcript: String, principal: Principal) throws -> VoiceCommandResponse? {
        guard let command = extractCommand(from: transcript) else { return nil }

        if command.isEmpty {
            return VoiceCommandResponse(
                spokenText: "At your service. Say status, list skills, self heal, or shutdown.",
                details: ["command": "wake"],
                shouldShutdown: false
            )
        }

        // SPEC-004: unified dispatch path — IntentParser → handler chain.
        // Display/HomeKit go through DisplayCommandExecutor; system + skill
        // intents go through SystemCommandHandler. Unknown falls through.
        if let parser = intentParser,
           let executor = displayExecutor,
           let capabilityRegistry = capabilityRegistry {
            let parsed = parser.parse(transcript: command)

            // SPEC-008.1: blocked patterns come back as .unknown with 0.0
            // confidence — refuse with a telemetry record before anything
            // else touches the command.
            if IntentParser.isBlockedIntent(command) {
                try? runtime.telemetry.logExecutionTrace(
                    workflowID: "voice-command-router",
                    stepID: "spec-008-blocked-pattern",
                    inputContext: command,
                    outputResult: "blocked",
                    status: "command_refused"
                )
                return VoiceCommandResponse(
                    spokenText: "That phrasing trips a safety guardrail, so I'm going to decline.",
                    details: ["command": "blocked", "transcript": command],
                    shouldShutdown: false
                )
            }

            switch parsed.intent {
            case .displayAction, .homeKitControl:
                if let refusal = companionRefusalIfNeeded(parsed: parsed, command: command, principal: principal) {
                    return refusal
                }
                if let response = try dispatchThroughExecutor(
                    parsed: parsed,
                    command: command,
                    executor: executor,
                    capabilityRegistry: capabilityRegistry
                ) {
                    return response
                }
            case .systemQuery, .skillInvocation:
                if let refusal = companionRefusalIfNeeded(parsed: parsed, command: command, principal: principal) {
                    return refusal
                }
                if let refusal = destructiveRefusalIfNeeded(parsed: parsed, command: command) {
                    return refusal
                }
                if let response = try systemHandler.handle(intent: parsed, command: command) {
                    return response
                }
            case .unknown:
                break
            }
        } else {
            // Legacy fallback when no capability config is available — route
            // straight through the system handler so `status` / `shutdown`
            // still work on a bare install.
            let parsed = ParsedIntent(
                intent: .systemQuery(query: command),
                confidence: 0.5,
                rawTranscript: command,
                timestamp: ""
            )
            if let refusal = companionRefusalIfNeeded(parsed: parsed, command: command, principal: principal) {
                return refusal
            }
            if let refusal = destructiveRefusalIfNeeded(parsed: parsed, command: command) {
                return refusal
            }
            if let response = try systemHandler.handle(intent: parsed, command: command) {
                return response
            }
        }

        return VoiceCommandResponse(
            spokenText: "I heard \(command), but that does not yet map to a sanctioned interface command. Say status, list skills, self heal, run skill, or shutdown.",
            details: ["command": "unmatched", "transcript": command],
            shouldShutdown: false
        )
    }

    /// SPEC-009: consult the companion capability policy before anything
    /// else fires. Operator tier falls through (returns nil). Companion
    /// and guest tiers get a spoken refusal + telemetry when the parsed
    /// command isn't in their allowed surface.
    private func companionRefusalIfNeeded(parsed: ParsedIntent, command: String, principal: Principal) -> VoiceCommandResponse? {
        let decision = companionPolicy.evaluateVoiceIntent(parsed, command: command, principal: principal)
        guard case .deny(let reason) = decision else { return nil }
        let spoken: String = {
            switch principal {
            case .guestTier: return CompanionCapabilityPolicy.guestDenialLine
            default: return CompanionCapabilityPolicy.companionDenialLine
            }
        }()
        try? runtime.telemetry.logExecutionTrace(
            workflowID: "voice-command-router",
            stepID: "spec-009-companion-policy",
            inputContext: command,
            outputResult: "\(principal.tierToken):\(reason)",
            status: "command_refused",
            principal: principal
        )
        return VoiceCommandResponse(
            spokenText: spoken,
            details: [
                "command": "policy-denied-companion",
                "reason": reason,
                "principal": principal.tierToken,
                "transcript": command
            ],
            shouldShutdown: false
        )
    }

    /// SPEC-008: consult the destructive-intent guard before handing the
    /// parsed intent to SystemCommandHandler. Non-destructive intents
    /// fall through (returns nil) and dispatch normally. Destructive
    /// intents consume a token from the stricter bucket; over-capacity
    /// returns a spoken refusal + `command_refused` telemetry.
    private func destructiveRefusalIfNeeded(parsed: ParsedIntent, command: String) -> VoiceCommandResponse? {
        let classification = destructiveGuard.classify(intent: parsed, command: command)
        guard case .destructive(let reason) = classification else { return nil }
        if destructiveGuard.allow() { return nil }
        try? runtime.telemetry.logExecutionTrace(
            workflowID: "voice-command-router",
            stepID: "spec-008-destructive-rate-limit",
            inputContext: command,
            outputResult: "destructive:\(reason)",
            status: "command_refused"
        )
        return VoiceCommandResponse(
            spokenText: DestructiveIntentGuard.refusalResponse,
            details: [
                "command": "destructive-refused",
                "reason": reason,
                "transcript": command
            ],
            shouldShutdown: false
        )
    }

    private func dispatchThroughExecutor(
        parsed: ParsedIntent,
        command: String,
        executor: DisplayCommandExecutor,
        capabilityRegistry: CapabilityRegistry
    ) throws -> VoiceCommandResponse? {
        let target: String
        let commandLabel: String
        let detailKey: String
        let action: String?
        switch parsed.intent {
        case .displayAction(let t, let a, _):
            guard t != "unknown" else { return nil }
            target = t; commandLabel = "display-action"; detailKey = "display"; action = a
        case .homeKitControl(let t, _, _):
            guard t != "unknown" else { return nil }
            target = t; commandLabel = "homekit-control"; detailKey = "accessory"; action = nil
        case .systemQuery, .skillInvocation, .unknown:
            return nil
        }

        // SPEC-008.2: rate-limit display/HomeKit dispatch before touching executor.
        guard rateLimiter.allow() else {
            try? runtime.telemetry.logExecutionTrace(
                workflowID: "voice-command-router",
                stepID: "spec-008-rate-limit",
                inputContext: command,
                outputResult: "rate_limited",
                status: "command_refused"
            )
            return VoiceCommandResponse(
                spokenText: CommandRateLimiter.limitExceededResponse,
                details: [
                    "command": commandLabel,
                    detailKey: target,
                    "refused": "rate_limited"
                ],
                shouldShutdown: false
            )
        }

        let auth = CommandAuthorization.voiceOperator(registry: capabilityRegistry)
        let result = try awaitSync { try await executor.execute(intent: parsed, authorization: auth) }

        var details: [String: Any] = [
            "command": commandLabel,
            detailKey: target,
            "success": result.success
        ]
        if let action { details["action"] = action }
        for (key, value) in result.details { details[key] = value }
        return VoiceCommandResponse(
            spokenText: result.spokenText,
            details: details,
            shouldShutdown: false
        )
    }

    // Bridge an async throwing operation to the synchronous route() pipeline.
    private func awaitSync<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let boxed = AwaitSyncBox<T>()
        Task {
            do {
                let value = try await operation()
                boxed.setSuccess(value)
            } catch {
                boxed.setFailure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try boxed.result()
    }

    private func extractCommand(from transcript: String) -> String? {
        let normalized = normalize(transcript)
        guard let range = normalized.range(of: "jarvis") else { return nil }
        return normalized[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalize(_ text: String) -> String {
        let replaced = text.lowercased().map { character -> Character in
            character.isLetter || character.isNumber || character == " " ? character : " "
        }
        return String(replaced)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

public final class RealJarvisInterface: NSObject {
    private let runtime: JarvisRuntime
    private let logLock = NSLock()
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isRunning = false
    private var lastHandledTranscript = ""
    private var activeRegistry: JarvisSkillRegistry?
    private var commandRouter: VoiceCommandRouter?
    private var voiceSession: VoiceSessionConfiguration?
    private var autonomousTimer: Timer?
    private var hostTunnel: JarvisHostTunnelServer?

    public init(runtime: JarvisRuntime) {
        self.runtime = runtime
        super.init()
    }

    public func start(registry: JarvisSkillRegistry) throws {
        activeRegistry = registry
        commandRouter = Self.makeCommandRouter(runtime: runtime, registry: registry)
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB")) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard speechRecognizer != nil else {
            throw JarvisError.processFailure("Speech recognizer could not be initialized for the J.A.R.V.I.S. interface.")
        }

        try requestPermissions()
        voiceSession = try runtime.voice.prepareSession()
        let hostTunnel = JarvisHostTunnelServer(runtime: runtime, registry: registry)
        try hostTunnel.start()
        self.hostTunnel = hostTunnel
        try writePID()

        let startupPayload = try runStartupSequence(registry: registry)
        try appendLog("startup-complete \(startupPayload)")
        try startListening()
        scheduleAutonomousPulse()
        isRunning = true
        try appendLog("listening-active")

        while isRunning && RunLoop.current.run(mode: .default, before: .distantFuture) {}
    }

    public func stop() {
        autonomousTimer?.invalidate()
        autonomousTimer = nil
        hostTunnel?.stop()
        hostTunnel = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRunning = false
        try? appendLog("interface-stopped")
        try? FileManager.default.removeItem(at: runtime.paths.interfacePIDURL)
    }

    public func startupLine(registry: JarvisSkillRegistry) throws -> String {
        let memify = try runtime.memory.memify(logFileURLs: try runtime.memory.defaultMemifyTargets())
        let callables = registry.callableSkillNames().count
        let allSkills = registry.allSkillNames().count
        let samples = try runtime.paths.audioSampleURLs().count
        let greeting = greetingPrefix()
        return "\(greeting). J.A.R.V.I.S. is online. I have \(allSkills) indexed skills, \(callables) native runtime skills, \(samples) local voice references, and \(memify.nodeCount) knowledge nodes warmed into memory. Say Jarvis status, Jarvis list skills, Jarvis self heal, or Jarvis shutdown."
    }

    private func runStartupSequence(registry: JarvisSkillRegistry) throws -> [String: Any] {
        let line = try startupGreetingLine(registry: registry)
        let filename = "startup-\(Int(Date().timeIntervalSince1970)).wav"
        let outputURL = runtime.paths.storageDirectory.appendingPathComponent(filename)
        let result = try runtime.voice.speak(
            text: line,
            configuration: voiceSession,
            persistAs: outputURL,
            workflowID: "voice-startup"
        )

        try runtime.telemetry.logExecutionTrace(
            workflowID: "voice-interface",
            stepID: "startup-sequence",
            inputContext: line,
            outputResult: outputURL.path,
            status: "success"
        )

        return [
            "line": line,
            "outputPath": result.outputPath,
            "voice": result.selectedVoice,
            "rate": result.rate
        ]
    }

    private func startupGreetingLine(registry: JarvisSkillRegistry) throws -> String {
        if ProcessInfo.processInfo.physicalMemory <= 8 * 1_024 * 1_024 * 1_024 {
            let greeting = greetingPrefix()
            return "\(greeting). J.A.R.V.I.S. online."
        }
        return try startupLine(registry: registry)
    }

    private func requestPermissions() throws {
        let speechStatus = requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            throw JarvisError.processFailure("Speech recognition permission was not granted for the J.A.R.V.I.S. interface.")
        }

        let microphoneGranted = requestMicrophoneAccess()
        guard microphoneGranted else {
            throw JarvisError.processFailure("Microphone permission was not granted for the J.A.R.V.I.S. interface.")
        }
    }

    private func requestSpeechAuthorization() -> SFSpeechRecognizerAuthorizationStatus {
        let semaphore = DispatchSemaphore(value: 0)
        var status = SFSpeechRecognizerAuthorizationStatus.notDetermined
        SFSpeechRecognizer.requestAuthorization {
            status = $0
            semaphore.signal()
        }
        semaphore.wait()
        return status
    }

    private func requestMicrophoneAccess() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .audio) {
                granted = $0
                semaphore.signal()
            }
            semaphore.wait()
            return granted
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func startListening() throws {
        guard let speechRecognizer else {
            throw JarvisError.processFailure("Speech recognizer is unavailable.")
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.handleTranscript(result.bestTranscription.formattedString, isFinal: result.isFinal)
            }
            if error != nil || result?.isFinal == true {
                self.restartListeningIfNeeded()
            }
        }
    }

    private func restartListeningIfNeeded() {
        guard isRunning else { return }
        Thread.sleep(forTimeInterval: 0.2)
        do {
            try startListening()
        } catch {
            try? appendLog("restart-error \(error)")
        }
    }

    private func handleTranscript(_ transcript: String, isFinal: Bool) {
        guard isFinal else { return }
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != lastHandledTranscript else { return }
        lastHandledTranscript = normalized

        do {
            try appendLog("heard \(normalized)")
            // SPEC-009: local-mic utterances originate at the Mac console.
            // Until SpeakerIdentifier diarization is wired in (todo:
            // speaker-id), treat the console mic as operator tier — that
            // is where Grizz sits. This is an explicit, auditable choice
            // rather than an implicit default in the router.
            guard let commandRouter, let response = try commandRouter.route(transcript: normalized, principal: .operatorTier) else { return }
            try runtime.telemetry.logRecursiveThought(
                sessionID: "voice-interface-\(UUID().uuidString)",
                trace: ["transcript=\(normalized)", "spoken=\(response.spokenText)"],
                memoryPageFault: false
            )
            _ = try runtime.voice.speak(
                text: response.spokenText,
                configuration: voiceSession,
                persistAs: runtime.paths.storageDirectory.appendingPathComponent("response-\(Int(Date().timeIntervalSince1970)).aiff"),
                workflowID: "voice-interface"
            )
            try appendLog("responded \(response.details)")

            if response.shouldShutdown {
                stop()
            }
        } catch {
            try? appendLog("command-error \(error)")
        }
    }

    private static func makeCommandRouter(runtime: JarvisRuntime, registry: JarvisSkillRegistry) -> VoiceCommandRouter {
        // Wire SPEC-004 pipeline if a capability config is present; otherwise fall back to legacy keyword router.
        let configURL = runtime.paths.capabilityConfigURL
        guard FileManager.default.fileExists(atPath: configURL.path),
              let capabilityRegistry = try? CapabilityRegistry(configURL: configURL) else {
            return VoiceCommandRouter(runtime: runtime, registry: registry)
        }
        let intentParser = IntentParser(capabilityRegistry: capabilityRegistry)
        let executor = DisplayCommandExecutor(
            registry: capabilityRegistry,
            controlPlane: runtime.controlPlane,
            telemetry: runtime.telemetry
        )
        return VoiceCommandRouter(
            runtime: runtime,
            registry: registry,
            intentParser: intentParser,
            displayExecutor: executor,
            capabilityRegistry: capabilityRegistry
        )
    }

    private func scheduleAutonomousPulse() {
        autonomousTimer = Timer.scheduledTimer(
            timeInterval: 60.0,
            target: self,
            selector: #selector(autonomousPulseTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc
    private func autonomousPulseTimerFired(_ timer: Timer) {
        performAutonomousPulse()
    }

    private func performAutonomousPulse() {
        do {
            let logText = (try? String(contentsOf: runtime.telemetry.tableURL("execution_traces"), encoding: .utf8)) ?? ""
            guard logText.lowercased().contains("\"status\":\"failure\"") else {
                try appendLog("heartbeat stable")
                return
            }

            let result = try runtime.metaHarness.diagnoseAndRewrite(
                workflowURL: runtime.paths.archonDirectory.appendingPathComponent("default_workflow.yaml"),
                traceDirectory: runtime.paths.traceDirectory
            )
            let spoken = result.mutationApplied
                ? "I've spotted a workflow bruise and corrected it."
                : "I've inspected the workflow pulse. No further intervention is required."
            _ = try runtime.voice.speak(
                text: spoken,
                configuration: voiceSession,
                persistAs: runtime.paths.storageDirectory.appendingPathComponent("autonomous-\(Int(Date().timeIntervalSince1970)).aiff"),
                workflowID: "autonomous-pulse"
            )
            try appendLog("autonomous-pulse \(result.json)")
        } catch {
            try? appendLog("autonomous-pulse-error \(error)")
        }
    }

    private func greetingPrefix() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<18:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    private func writePID() throws {
        try "\(ProcessInfo.processInfo.processIdentifier)".write(
            to: runtime.paths.interfacePIDURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private func appendLog(_ line: String) throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let payload = "[\(timestamp)] \(line)\n"
        guard let data = payload.data(using: .utf8) else { return }

        logLock.lock()
        defer { logLock.unlock() }

        if !FileManager.default.fileExists(atPath: runtime.paths.interfaceLogURL.path) {
            FileManager.default.createFile(atPath: runtime.paths.interfaceLogURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: runtime.paths.interfaceLogURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
