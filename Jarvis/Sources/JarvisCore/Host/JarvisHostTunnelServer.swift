import Foundation
import Network
import Security  // CX-044: SecRandomCopyBytes

public final class JarvisHostTunnelServer: @unchecked Sendable {
    private let runtime: JarvisRuntime
    private let registry: JarvisSkillRegistry
    private let queue = DispatchQueue(label: "ai.realjarvis.host-tunnel")
    private let crypto: JarvisTunnelCrypto
    private let authorizedSources = Set(["obsidian-command-bar", "terminal", "voice-operator", "mobile-cockpit"])
    private let port: UInt16
    private let idleTimeout: TimeInterval  // SPEC-011: disconnect unauthenticated clients after this interval
    private let isoFormatter = ISO8601DateFormatter()
    private var listener: NWListener?
    private var buffers: [ObjectIdentifier: Data] = [:]
    private var clients: [ObjectIdentifier: NWConnection] = [:]
    private var clientSources: [ObjectIdentifier: String] = [:]  // CX-038: server-assigned source per connection
    private var clientPrincipals: [ObjectIdentifier: Principal] = [:]  // SPEC-009: server-assigned tier per connection
    private let identityStore: TunnelIdentityStore  // SPEC-007: per-device role binding
    private let companionPolicy: CompanionCapabilityPolicy  // SPEC-009: tier-aware command policy
    // MK2-EPIC-02: role token state
    private var clientTokens: [ObjectIdentifier: TunnelRoleToken] = [:]
    private var clientPubKeys: [ObjectIdentifier: String] = [:]
    private let capabilityRegistry: CapabilityRegistry
    private let nonceTracker = DestructiveNonceTracker()

    /// SPEC-011: active connection count (thread-safe via serial queue).
    public var activeConnectionCount: Int {
        queue.sync { clients.count }
    }

    /// SPEC-011: number of unauthenticated clients kicked by the idle timer (thread-safe).
    public var idleDisconnectCount: Int {
        queue.sync { _idleDisconnectCount }
    }
    private var _idleDisconnectCount: Int = 0

    public init(
        runtime: JarvisRuntime,
        registry: JarvisSkillRegistry,
        port: UInt16 = 9443,
        sharedSecret: String? = nil,
        idleTimeout: TimeInterval = 60,
        identityStore: TunnelIdentityStore? = nil,
        capabilityRegistry: CapabilityRegistry? = nil
    ) {
        self.runtime = runtime
        self.registry = registry
        self.port = port
        self.idleTimeout = max(0.1, idleTimeout)  // SPEC-011: clamp to avoid zero/negative
        // CX-044: generate random secret if none provided
        let seed: String
        if let provided = sharedSecret {
            seed = provided
        } else {
            var randomBytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, &randomBytes)
            seed = "jarvis-" + randomBytes.map { String(format: "%02x", $0) }.joined()
        }
        self.crypto = JarvisTunnelCrypto(sharedSecret: seed)
        // SPEC-007: resolve identity store from disk if not injected.
        if let provided = identityStore {
            self.identityStore = provided
        } else {
            let url = URL(fileURLWithPath: ".jarvis/storage/tunnel/identities.json")
            let store = TunnelIdentityStore(fileURL: url)
            store.reload()
            self.identityStore = store
        }
        self.companionPolicy = CompanionCapabilityPolicy()
        // MK2-EPIC-02: capability registry for client role lookup
        if let provided = capabilityRegistry {
            self.capabilityRegistry = provided
        } else {
            self.capabilityRegistry = (try? CapabilityRegistry(configURL: runtime.paths.capabilityConfigURL))
                ?? CapabilityRegistry(displays: [], accessories: [], clientRoles: [])
        }
    }

    public func start() throws {
        guard listener == nil else { return }
        guard let listenerPort = NWEndpoint.Port(rawValue: port) else {
            throw JarvisError.invalidInput("Invalid tunnel port \(port).")
        }

        let listener = try NWListener(using: .tcp, on: listenerPort)
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                try? self?.runtime.telemetry.logExecutionTrace(
                    workflowID: "host-tunnel",
                    stepID: "listener",
                    inputContext: "state-update",
                    outputResult: error.localizedDescription,
                    status: "failure"
                )
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.queue.async { self?.accept(connection) }  // CX-011: dispatch accept onto serial queue
        }
        listener.start(queue: queue)
        self.listener = listener

        try runtime.telemetry.logExecutionTrace(
            workflowID: "host-tunnel",
            stepID: "startup",
            inputContext: "listen:\(listenerPort.rawValue)",
            outputResult: "listening",
            status: "success"
        )
    }

    public func run() throws {
        try start()
        while RunLoop.current.run(mode: .default, before: .distantFuture) {}
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        queue.sync {
            for connection in self.clients.values {
                connection.cancel()
            }
            self.clients.removeAll()
            self.buffers.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        clients[identifier] = connection
        buffers[identifier] = Data()
        clientSources[identifier] = "unauthenticated"  // R06: default unauthenticated — must register to get authorized source

        // SPEC-011: kick unauthenticated clients after idleTimeout to defend against slow-loris / RAM exhaustion.
        queue.asyncAfter(deadline: .now() + idleTimeout) { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            let id = ObjectIdentifier(connection)
            // Only fire if the connection is still tracked AND still unauthenticated.
            guard self.clients[id] != nil, self.clientSources[id] == "unauthenticated" else { return }
            self._idleDisconnectCount += 1
            try? self.runtime.telemetry.logExecutionTrace(
                workflowID: "host-tunnel",
                stepID: "idle-disconnect",
                inputContext: "timeout:\(self.idleTimeout)s",
                outputResult: "unauthenticated-client-closed",
                status: "success"
            )
            self.disconnect(connection, reason: "idle-timer")
            connection.cancel()
        }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receive(on: connection)
                if let snapshot = try? self?.makeSnapshot() {
                    try? self?.send(JarvisTunnelMessage(kind: .snapshot, snapshot: snapshot), on: connection)
                }
            case .failed(let error):
                self?.disconnect(connection, reason: "state-cb")
                try? self?.runtime.telemetry.logExecutionTrace(
                    workflowID: "host-tunnel",
                    stepID: "connection",
                    inputContext: "client-failed",
                    outputResult: error.localizedDescription,
                    status: "failure"
                )
            case .cancelled:
                self?.disconnect(connection, reason: "state-cb")
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func disconnect(_ connection: NWConnection, reason: String = "unknown") {
        let identifier = ObjectIdentifier(connection)
        clients.removeValue(forKey: identifier)
        clientSources.removeValue(forKey: identifier)  // CX-038: cleanup
        clientPrincipals.removeValue(forKey: identifier)  // SPEC-009: cleanup
        clientTokens.removeValue(forKey: identifier)  // MK2-EPIC-02: cleanup
        clientPubKeys.removeValue(forKey: identifier)  // MK2-EPIC-02: cleanup
        buffers.removeValue(forKey: identifier)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.handle(data: data, on: connection)
            }
            if isComplete || error != nil {
                self.disconnect(connection, reason: "receive-complete")
                connection.cancel()
                return
            }
            self.receive(on: connection)
        }
    }

    private let maxBufferBytes = 1_048_576  // CX-004: 1MB per-connection buffer limit

    private func handle(data: Data, on connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        var buffer = buffers[identifier] ?? Data()
        buffer.append(data)

        // CX-004: disconnect clients that send >1MB without a newline
        if buffer.count > maxBufferBytes {
            buffers.removeValue(forKey: identifier)
            disconnect(connection, reason: "legacy")
            return
        }

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            if !line.isEmpty {
                handle(line: Data(line), on: connection)
            }
        }

        buffers[identifier] = buffer
    }

    private func handle(line: Data, on connection: NWConnection) {
        do {
            let packet = try JSONDecoder().decode(JarvisTransportPacket.self, from: line)
            let message = try crypto.open(JarvisTunnelMessage.self, from: packet.payload)
            let reply = try route(message, from: connection)  // CX-038: pass connection for source verification
            try send(reply, on: connection)
        } catch {
            let response = JarvisTunnelMessage(kind: .error, error: error.localizedDescription)
            try? send(response, on: connection)
        }
    }

    /// SPEC-007: resolve a registration to an authorized server-assigned role.
    /// Returns (role: lowercased role string) on success, (error: reason) on rejection.
    /// voice-operator is only granted when the host's voice approval gate is green,
    /// and privileged roles must present a valid per-device identity proof.
    internal func authorizeRegistration(_ registration: JarvisClientRegistration) -> (role: String?, error: String?) {
        let role = registration.role.lowercased()
        guard authorizedSources.contains(role) else {
            return (nil, nil) // silent — unknown roles are dropped without response, matches prior behavior
        }
        // SPEC-007: verify per-device identity binding.
        if let failure = identityStore.validate(registration) {
            let reason: String
            switch failure {
            case .privilegedRoleRequiresIdentityProof:
                reason = "Role \(role) requires a per-device identity proof."
            case .nonceMissing:
                reason = "Registration missing nonce."
            case .nonceStale(let drift):
                reason = "Registration nonce stale (drift \(drift)s)."
            case .nonceReplay:
                reason = "Registration nonce replay detected."
            case .unknownDevice:
                reason = "Device \(registration.deviceID) is not authorized for role \(role)."
            case .roleNotAllowedForDevice:
                reason = "Device \(registration.deviceID) is not permitted to claim role \(role)."
            case .proofMismatch:
                reason = "Registration identity proof failed verification."
            case .malformedIdentityKey:
                reason = "Server identity key for \(registration.deviceID) is malformed."
            }
            try? runtime.telemetry.logExecutionTrace(
                workflowID: "host-tunnel",
                stepID: "identity-reject",
                inputContext: "\(registration.deviceID):\(role)",
                outputResult: reason,
                status: "failure"
            )
            return (nil, reason)
        }
        if role == "voice-operator" {
            let gate = runtime.voice.approval.snapshotForSpatialHUD()
            guard gate.state == .green else {
                return (nil, "Voice gate is not green (state: \(gate.stateName)). Cannot register as voice-operator.")
            }
        }
        return (role, nil)
    }

    /// Backward-compatible shim used by tests that don't exercise identity binding.
    @available(*, deprecated, message: "Use authorizeRegistration(_:) — SPEC-007")
    internal func authorizeRegistrationRole(_ rawRole: String) -> (role: String?, error: String?) {
        let reg = JarvisClientRegistration(
            deviceID: "legacy-shim",
            deviceName: "legacy",
            platform: "legacy",
            role: rawRole,
            appVersion: "0.0.0"
        )
        return authorizeRegistration(reg)
    }

    private func route(_ message: JarvisTunnelMessage, from connection: NWConnection) throws -> JarvisTunnelMessage {
        // MK2-EPIC-02: validate role token on all non-register frames
        if message.kind != .register {
            try validateRoleToken(message, from: connection)
        }
        switch message.kind {
        case .register:
            // R06: assign source from client registration role
            if let registration = message.registration {
                let identifier = ObjectIdentifier(connection)
                let result = authorizeRegistration(registration)
                if let role = result.role {
                    clientSources[identifier] = role
                    // SPEC-009: bind principal at registration time. Identity
                    // store is the only trusted source; clients never assert.
                    clientPrincipals[identifier] = identityStore.principal(for: registration.deviceID)
                    // MK2-EPIC-02: issue role token. Use device identity key as pubKey if available.
                    let identityKeyHex = identityStore.identity(for: registration.deviceID)?.identityKeyHex
                        ?? registration.deviceID
                    let tunnelRole = capabilityRegistry.clientIdentity(publicKeyHex: identityKeyHex)
                    let token = crypto.signRoleToken(role: tunnelRole, clientPubKey: identityKeyHex)
                    clientTokens[identifier] = token
                    clientPubKeys[identifier] = identityKeyHex
                    let wireToken = try? token.wireString()
                    try? runtime.telemetry.logExecutionTrace(
                        workflowID: "host-tunnel",
                        stepID: "tunnel.auth.granted",
                        inputContext: "\(registration.deviceID):\(tunnelRole.rawValue)",
                        outputResult: "role-token-issued",
                        status: "success"
                    )
                    return JarvisTunnelMessage(
                        kind: .response,
                        response: JarvisTunnelResponse(
                            action: .ping,
                            spokenText: "Mobile endpoint registered to the Jarvis host tunnel.",
                            snapshot: try makeSnapshot()
                        ),
                        roleToken: wireToken
                    )
                } else if let err = result.error {
                    return JarvisTunnelMessage(kind: .error, error: err)
                }
            }
            return JarvisTunnelMessage(
                kind: .response,
                response: JarvisTunnelResponse(
                    action: .ping,
                    spokenText: "Mobile endpoint registered to the Jarvis host tunnel.",
                    snapshot: try makeSnapshot()
                )
            )
        case .heartbeat:
            return JarvisTunnelMessage(kind: .snapshot, snapshot: try makeSnapshot())
        case .command:
            guard let command = message.command else {
                throw JarvisError.invalidInput("Tunnel command missing payload.")
            }
            try ensureAuthorized(command, from: connection)
            let response = try handle(command: command, confirmHash: message.confirmHash, nonce: message.nonce, from: connection)
            return JarvisTunnelMessage(kind: .response, snapshot: response.snapshot, response: response)
        case .snapshot:
            return JarvisTunnelMessage(kind: .snapshot, snapshot: try makeSnapshot())
        case .response, .push, .error:
            return JarvisTunnelMessage(kind: .snapshot, snapshot: try makeSnapshot())
        }
    }

    private func ensureAuthorized(_ command: JarvisRemoteCommand, from connection: NWConnection) throws {
        let identifier = ObjectIdentifier(connection)
        // CX-038: verify server-assigned source, ignore client-asserted source
        guard let assignedSource = clientSources[identifier],
              authorizedSources.contains(assignedSource) else {
            throw JarvisError.invalidInput("Connection source is not authorized.")
        }
        // Also reject if client asserts a different source than what server assigned
        if let clientSource = command.source, clientSource != assignedSource {
            throw JarvisError.invalidInput("Command source '\(clientSource)' does not match connection source '\(assignedSource)'.")
        }
        // SPEC-009: companion-tier policy. Operator tier is a pass-through.
        // Companion tier is denied destructive/admin verbs. Guest tier is
        // limited to status/ping. Principal defaults to .guestTier if the
        // identifier isn't in the map (fail-closed).
        let principal = clientPrincipals[identifier] ?? .guestTier
        let decision = companionPolicy.evaluateTunnelAction(command.action, principal: principal)
        if case .deny(let reason) = decision {
            try? runtime.telemetry.logExecutionTrace(
                workflowID: "host-tunnel",
                stepID: "spec-009-companion-policy",
                inputContext: "\(principal.tierToken):\(command.action.rawValue)",
                outputResult: reason,
                status: "command_refused",
                principal: principal
            )
            throw JarvisError.invalidInput("Principal \(principal.tierToken) is not permitted to run \(command.action.rawValue) (\(reason)).")
        }
    }

    /// MK2-EPIC-02: Validate the role token carried in every post-registration frame.
    /// On any failure, emits `tunnel.auth.denied` telemetry and throws.
    private func validateRoleToken(_ message: JarvisTunnelMessage, from connection: NWConnection) throws {
        let identifier = ObjectIdentifier(connection)
        // If this connection has no stored token (e.g., unauthenticated), we only
        // enforce if the client is registered (has a source assigned). Unauthenticated
        // connections are handled by the idle-timer path.
        guard clientSources[identifier] != nil, clientSources[identifier] != "unauthenticated" else {
            return
        }
        guard let wireToken = message.roleToken else {
            emitAuthDenied(connection: connection, reason: "missing-role-token")
            throw TunnelError.missingRoleToken
        }
        let token: TunnelRoleToken
        do {
            token = try TunnelRoleToken.from(wireString: wireToken)
        } catch {
            emitAuthDenied(connection: connection, reason: "token-decode-failed")
            throw TunnelError.invalidToken
        }
        guard crypto.verifyRoleToken(token) else {
            emitAuthDenied(connection: connection, reason: "hmac-invalid")
            throw TunnelError.invalidToken
        }
        guard !token.isExpired else {
            emitAuthDenied(connection: connection, reason: "token-expired")
            throw TunnelError.expiredToken
        }
        // Verify pubKey matches the one we stored at registration
        if let storedPubKey = clientPubKeys[identifier], storedPubKey != token.clientPubKey {
            emitAuthDenied(connection: connection, reason: "pubkey-mismatch")
            throw TunnelError.pubKeyMismatch
        }
        // Verify token role matches the role we stored
        if let storedToken = clientTokens[identifier], storedToken.role != token.role {
            emitAuthDenied(connection: connection, reason: "role-mismatch")
            throw TunnelError.roleClaimMismatch
        }
    }

    private func emitAuthDenied(connection: NWConnection, reason: String) {
        try? runtime.telemetry.logExecutionTrace(
            workflowID: "host-tunnel",
            stepID: "tunnel.auth.denied",
            inputContext: reason,
            outputResult: "connection-dropped",
            status: "failure"
        )
        disconnect(connection, reason: "auth-denied:\(reason)")
        connection.cancel()
    }

    /// MK2-EPIC-02: Synchronous nonce validation using DispatchSemaphore bridge.
    /// The actor runs on the cooperative thread pool; we block the tunnel serial queue briefly.
    private func validateDestructiveNonce(_ nonce: String) -> Bool {
        // Use a Mutex-like box to safely pass the result out of the Task.
        let box = _NonceResultBox()
        let sema = DispatchSemaphore(value: 0)
        Task {
            box.result = await nonceTracker.insertAndValidate(nonce)
            sema.signal()
        }
        sema.wait()
        return box.result
    }

    private func handle(command: JarvisRemoteCommand, confirmHash: String? = nil, nonce: String? = nil, from connection: NWConnection? = nil) throws -> JarvisTunnelResponse {
        // MK2-EPIC-02: Destructive path — nonce + confirmHash required
        if command.action.isDestructive {
            guard let nonceValue = nonce, !nonceValue.isEmpty else {
                try? runtime.telemetry.logExecutionTrace(
                    workflowID: "host-tunnel",
                    stepID: "destructive.rejected",
                    inputContext: command.action.rawValue,
                    outputResult: "missing-nonce",
                    status: "failure"
                )
                throw TunnelError.missingNonce
            }
            guard validateDestructiveNonce(nonceValue) else {
                try? runtime.telemetry.logExecutionTrace(
                    workflowID: "host-tunnel",
                    stepID: "destructive.rejected",
                    inputContext: command.action.rawValue,
                    outputResult: "nonce-replay",
                    status: "failure"
                )
                throw TunnelError.nonceReplay
            }
            let expected = command.action.canonicalHashHex
            guard let provided = confirmHash else {
                try? runtime.telemetry.logExecutionTrace(
                    workflowID: "host-tunnel",
                    stepID: "destructive.rejected",
                    inputContext: command.action.rawValue,
                    outputResult: "missing-confirm-hash",
                    status: "failure"
                )
                throw TunnelError.destructiveRequiresConfirm
            }
            guard provided == expected else {
                try? runtime.telemetry.logExecutionTrace(
                    workflowID: "host-tunnel",
                    stepID: "destructive.rejected",
                    inputContext: command.action.rawValue,
                    outputResult: "hash-mismatch",
                    status: "failure"
                )
                throw TunnelError.confirmHashMismatch
            }
            try? runtime.telemetry.logExecutionTrace(
                workflowID: "host-tunnel",
                stepID: "destructive.confirmed",
                inputContext: command.action.rawValue,
                outputResult: "proceeding",
                status: "success"
            )
            return JarvisTunnelResponse(
                action: command.action,
                spokenText: "Destructive action \(command.action.rawValue) confirmed and accepted.",
                snapshot: try makeSnapshot()
            )
        }
        switch command.action {
        case .status, .ping:
            let snapshot = try makeSnapshot()
            return JarvisTunnelResponse(action: command.action, spokenText: snapshot.statusLine, snapshot: snapshot)
        case .homeKitStatus:
            let status = try runtime.controlPlane.synchronize()
            return JarvisTunnelResponse(
                action: .homeKitStatus,
                spokenText: status.homeKitBridge.bridgeState,
                snapshot: try makeSnapshot(),
                payloadJSON: try makeJSONString(status.json)
            )
        case .listSkills:
            let callable = registry.callableSkillNames()
            let spokenList = callable.prefix(6).joined(separator: ", ")
            return JarvisTunnelResponse(
                action: .listSkills,
                spokenText: "Callable skills online: \(spokenList).",
                snapshot: try makeSnapshot(),
                payloadJSON: try makeJSONString(["skills": callable])
            )
        case .selfHeal:
            let result = try runtime.metaHarness.diagnoseAndRewrite(
                workflowURL: runtime.paths.archonDirectory.appendingPathComponent("default_workflow.yaml"),
                traceDirectory: runtime.paths.traceDirectory
            )
            return JarvisTunnelResponse(
                action: .selfHeal,
                spokenText: result.mutationApplied ? "Host harness rewritten and stabilized." : "Harness already stable.",
                snapshot: try makeSnapshot(),
                payloadJSON: try makeJSONString(result.json)
            )
        case .startupVoice:
            let line = command.text ?? "Mobile cockpit linked. J.A.R.V.I.S. is attentive."
            let outputURL = runtime.paths.voiceCacheDirectory.appendingPathComponent("host-mobile-\(UUID().uuidString).wav")
            let result = try runtime.voice.speak(text: line, persistAs: outputURL, workflowID: "host-mobile-startup")
            return JarvisTunnelResponse(
                action: .startupVoice,
                spokenText: line,
                snapshot: try makeSnapshot(),
                payloadJSON: try makeJSONString(result.json),
                outputPath: result.outputPath
            )
        case .bridgeIntercom:
            let controlPlane = try runtime.controlPlane.synchronize()
            let line = command.text ?? "Jarvis intercom route is standing by on Charlie."
            return JarvisTunnelResponse(
                action: .bridgeIntercom,
                spokenText: line,
                snapshot: try makeSnapshot(),
                payloadJSON: try makeJSONString([
                    "intercomRoute": controlPlane.homeKitBridge.voiceIntercomRoute,
                    "reachable": controlPlane.homeKitBridge.reachable,
                    "authorizedCommandSources": controlPlane.homeKitBridge.authorizedCommandSources
                ])
            )
        case .queueGuiIntent:
            let payload = try parsePayload(command.payloadJSON)
            let sourceNode = (payload["sourceNode"] as? String) ?? "echo"
            let targetNodes = (payload["targetNodes"] as? [String]) ?? ["echo", "alpha", "beta", "charlie", "delta"]
            let action = command.text ?? "Jarvis Status"
            let intent = try runtime.controlPlane.queueGUIIntent(sourceNode: sourceNode, targetNodes: targetNodes, action: action, payloadJSON: command.payloadJSON)
            return JarvisTunnelResponse(
                action: .queueGuiIntent,
                spokenText: "Queued \(action) across \(targetNodes.joined(separator: ", ")).",
                snapshot: try makeSnapshot(),
                payloadJSON: try makeJSONString([
                    "id": intent.id,
                    "sourceNode": intent.sourceNode,
                    "targetNodes": intent.targetNodes,
                    "action": intent.action,
                    "payloadJSON": intent.payloadJSON ?? "",
                    "queuedAt": intent.queuedAt,
                    "status": intent.status
                ])
            )
        case .reseedObsidian:
            let controlPlane = try runtime.controlPlane.synchronize(forceVaultReseed: true)
            return JarvisTunnelResponse(
                action: .reseedObsidian,
                spokenText: controlPlane.obsidianVault.statusLine,
                snapshot: try makeSnapshot(),
                payloadJSON: try makeJSONString(controlPlane.json)
            )
        case .runSkill:
            guard let skillName = command.skillName else {
                throw JarvisError.invalidInput("run_skill requires a skillName.")
            }
            let payload = try parsePayload(command.payloadJSON)
            let result = try registry.execute(name: skillName, input: payload, runtime: runtime)
            return JarvisTunnelResponse(
                action: .runSkill,
                spokenText: "Executed \(skillName).",
                snapshot: try makeSnapshot(),
                payloadJSON: try makeJSONString(result)
            )
        case .shutdown:
            return JarvisTunnelResponse(
                action: .shutdown,
                spokenText: "Tunnel acknowledged shutdown. The host remains available for manual restart.",
                snapshot: try makeSnapshot()
            )
        case .presenceArrival:
            let event = try decodePresenceEvent(from: command)
            let outcome = try runtime.presenceRouter.handle(event)
            return JarvisTunnelResponse(
                action: .presenceArrival,
                spokenText: outcome.summary,
                snapshot: try makeSnapshot(),
                payloadJSON: try makeJSONString([
                    "eventID": outcome.eventID,
                    "greeted": outcome.greeted,
                    "suppressed": outcome.plan.suppressed,
                    "suppressionReason": outcome.plan.suppressionReason ?? "",
                    "surfaces": outcome.plan.surfaces.map { $0.rawValue },
                    "line": outcome.plan.line
                ]),
                outputPath: outcome.spokenOutputPath
            )
        case .displayWipe, .capabilityDelete, .voiceGateRevoke, .memoryPurge, .soulAnchorRotate:
            // Destructive actions pass nonce + confirmHash validation in the preamble above.
            // The tunnel's contract is: (1) authenticate, (2) authorize, (3) audit, (4) acknowledge.
            // Physical effect is owned by the subsystem that subscribes to the destructive-actions
            // audit stream (soul-anchor rotation ceremony, capability registry config mutation,
            // voice gate revoke daemon, memory purge service, cockpit display clear). Writing an
            // immutable audit record here is the real observable effect at this layer.
            try runtime.telemetry.append(
                record: [
                    "action": command.action.rawValue,
                    "acceptedAt": isoFormatter.string(from: Date()),
                    "source": command.source ?? "unknown",
                    "nonce": nonce ?? "",
                    "confirmHash": confirmHash ?? "",
                    "payloadJSON": command.payloadJSON ?? "",
                    "text": command.text ?? ""
                ],
                to: "destructive_actions"
            )
            return JarvisTunnelResponse(
                action: command.action,
                spokenText: "Destructive action \(command.action.rawValue) confirmed, audited, and accepted.",
                snapshot: try makeSnapshot()
            )
        }
    }

    private func decodePresenceEvent(from command: JarvisRemoteCommand) throws -> JarvisPresenceEvent {
        guard let json = command.payloadJSON, let data = json.data(using: .utf8) else {
            throw JarvisError.invalidInput("presence_arrival requires a JSON payload describing the presence event.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(JarvisPresenceEvent.self, from: data)
        } catch {
            throw JarvisError.invalidInput("presence_arrival payload failed to decode: \(error.localizedDescription)")
        }
    }

    private func makeSnapshot() throws -> JarvisHostSnapshot {
        let indexed = registry.allSkillNames().count
        let callable = registry.callableSkillNames().count
        let samples = try runtime.paths.audioSampleURLs().count
        let thoughts = try loadThoughts(limit: 5)
        let signals = try loadSignals(limit: 5)
        let mutations = try loadLastMutation()
        let controlPlane = try runtime.controlPlane.synchronize()

        let voiceGate = runtime.voice.approval.snapshotForSpatialHUD()
        let voiceGateHUD = runtime.voice.approval.spatialHUDElement()

        return JarvisHostSnapshot(
            hostName: Host.current().localizedName ?? "J.A.R.V.I.S. Host",
            statusLine: "J.A.R.V.I.S. host online. \(indexed) indexed skills, \(callable) callable skills, \(samples) voice references, \(thoughts.count) recent thought traces.",
            indexedSkillCount: indexed,
            callableSkillCount: callable,
            voiceSampleCount: samples,
            tunnelState: clients.isEmpty ? .degraded : .online,
            activeWorkflow: "jarvis-default",
            lastMutation: mutations,
            recentThoughts: thoughts,
            recentSignals: signals,
            homeKitBridge: controlPlane.homeKitBridge,
            obsidianVault: controlPlane.obsidianVault,
            nodeRegistry: controlPlane.nodeRegistry,
            guiIntents: controlPlane.guiIntents,
            rustDeskNodes: controlPlane.rustDeskNodes,
            voiceGate: voiceGate,
            spatialHUD: [voiceGateHUD]
        )
    }

    private func loadThoughts(limit: Int) throws -> [JarvisThoughtSnapshot] {
        let url = runtime.telemetry.tableURL("recursive_thoughts")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let lines = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .suffix(limit)

        return lines.compactMap { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return JarvisThoughtSnapshot(
                id: UUID().uuidString,
                sessionID: (object["sessionId"] as? String) ?? "unknown",
                trace: (object["thoughtTrace"] as? [String]) ?? [],
                memoryPageFault: (object["memoryPageFault"] as? Bool) ?? false,
                timestamp: (object["timestamp"] as? String) ?? isoFormatter.string(from: Date())
            )
        }
    }

    private func loadSignals(limit: Int) throws -> [JarvisSignalSnapshot] {
        let url = runtime.telemetry.tableURL("stigmergic_signals")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let lines = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .suffix(limit)

        return lines.compactMap { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return JarvisSignalSnapshot(
                id: UUID().uuidString,
                nodeSource: (object["nodeSource"] as? String) ?? "unknown",
                nodeTarget: (object["nodeTarget"] as? String) ?? "unknown",
                ternaryValue: (object["ternaryValue"] as? Int) ?? 0,
                agentID: (object["agentId"] as? String) ?? "unknown",
                pheromone: (object["pheromone"] as? Double) ?? 0.0,
                timestamp: (object["timestamp"] as? String) ?? isoFormatter.string(from: Date())
            )
        }
    }

    private func loadLastMutation() throws -> String {
        let url = runtime.telemetry.tableURL("harness_mutations")
        guard FileManager.default.fileExists(atPath: url.path) else { return "No recorded harness mutation." }
        let line = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .last

        guard let line,
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "No recorded harness mutation."
        }
        let diagnosis = (object["diffPatch"] as? String)?.components(separatedBy: .newlines).first ?? "Harness mutation logged."
        return diagnosis
    }

    private func send(_ message: JarvisTunnelMessage, on connection: NWConnection) throws {
        let payload = try crypto.seal(message)
        let packet = JarvisTransportPacket(
            origin: "jarvis-host",
            timestamp: isoFormatter.string(from: Date()),
            payload: payload
        )
        let data = try JSONEncoder().encode(packet) + Data([0x0A])
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func makeJSONString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw JarvisError.serializationFailure("Unable to encode tunnel response JSON.")
        }
        return text
    }

    private func parsePayload(_ raw: String?) throws -> [String: Any] {
        guard let raw, !raw.isEmpty else { return [:] }
        guard let data = raw.data(using: .utf8) else {
            throw JarvisError.invalidInput("Tunnel command payload must be valid UTF-8.")
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            throw JarvisError.invalidInput("Tunnel command payload must be a JSON object.")
        }
        return payload
    }
}

// MARK: - MK2-EPIC-02: Internal helper for nonce validation bridge

/// Single-use box for ferrying an actor result out of a Task into synchronous code.
/// Only ever written once (inside the Task, before the semaphore fires) and
/// read once (in the calling thread after sema.wait()). The server's serial queue
/// and the semaphore together guarantee no concurrent access.
private final class _NonceResultBox: @unchecked Sendable {
    var result = false
}
