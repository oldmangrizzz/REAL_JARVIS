import Foundation
import Security

public struct MyceliumControlPlaneStatus: Sendable {
    public let homeKitBridge: JarvisHomeKitBridgeStatus
    public let obsidianVault: JarvisObsidianVaultStatus
    public let nodeRegistry: [JarvisNodeHeartbeat]
    public let guiIntents: [JarvisGUIIntent]
    public let rustDeskNodes: [JarvisRustDeskNode]

    public var json: [String: Any] {
        [
            "homeKitBridge": MyceliumControlPlane.encode(homeKitBridge),
            "obsidianVault": MyceliumControlPlane.encode(obsidianVault),
            "nodeRegistry": nodeRegistry.map(MyceliumControlPlane.encode),
            "guiIntents": guiIntents.map(MyceliumControlPlane.encode),
            "rustDeskNodes": rustDeskNodes.map(MyceliumControlPlane.encode)
        ]
    }
}

public final class MyceliumControlPlane {
    private struct SiloNodeDefinition: Sendable {
        let name: String
        let address: String?
        let rustDeskID: String?
    }

    private struct LocalVaultStatus: Sendable {
        let endpoint: String
        let databaseName: String
        let docCount: Int
    }

    private enum Constants {
        static let charlieAddress = "192.168.4.151"
        static let homebridgePort = 8581
        static let liveKitURL = "https://livekit.grizzlymedicine.icu"
        static let couchPort = 5984
        static let obsidianDatabase = "obsidian_vault"
        static let bridgeName = "J.A.R.V.I.S. Iron Silo Matter Bridge"
        static let voiceIntercomRoute = "airplay2://192.168.4.151/homepods/jarvis-intercom"
        static let convexDeploymentURL = "https://enduring-starfish-794.convex.cloud"
        static let guiNodes = ["echo", "alpha", "beta", "charlie", "delta"]
        static let authorizedCommandSources = ["obsidian-command-bar", "terminal"]
        static let regulationVisibility = "internal-only"
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private let paths: WorkspacePaths
    private let telemetry: TelemetryStore
    private let formatter = ISO8601DateFormatter()
    private let fallbackNodes: [SiloNodeDefinition] = [
        SiloNodeDefinition(name: "echo", address: nil, rustDeskID: "IRONSILO-ECHO"),
        SiloNodeDefinition(name: "alpha", address: nil, rustDeskID: "IRONSILO-ALPHA"),
        SiloNodeDefinition(name: "beta", address: "192.168.4.151:5984", rustDeskID: "IRONSILO-BETA"),
        SiloNodeDefinition(name: "charlie", address: "192.168.4.151", rustDeskID: "IRONSILO-CHARLIE"),
        SiloNodeDefinition(name: "delta", address: nil, rustDeskID: "IRONSILO-DELTA")
    ]

    private let charlieAddress: String  // CX-028: configurable instead of hardcoded
    private let homebridgePort: Int

    public init(paths: WorkspacePaths, telemetry: TelemetryStore,
                charlieAddress: String = "192.168.4.151",
                homebridgePort: Int = 8581) throws {  // CX-028
        self.paths = paths
        self.telemetry = telemetry
        self.charlieAddress = charlieAddress
        self.homebridgePort = homebridgePort
        try paths.ensureSupportDirectories()
    }

    public func synchronize(forceVaultReseed: Bool = false) throws -> MyceliumControlPlaneStatus {
        let lastSync = formatter.string(from: Date())
        let signals = try loadSignals(limit: 8)
        let vagalTone = try loadLatestVagalTone()
        let homeKitBridge = buildHomeKitBridgeStatus(signals: signals, vagalTone: vagalTone, lastSync: lastSync)
        let rustDeskNodes = buildRustDeskNodes(lastSync: lastSync)
        let nodeRegistry = buildNodeRegistry(homeKitBridge: homeKitBridge, lastSync: lastSync, rustDeskNodes: rustDeskNodes)
        let guiIntents = try loadQueuedGUIIntents()
        let obsidianVault = buildObsidianVaultStatus(forceReseed: forceVaultReseed, lastSync: lastSync)

        try writeHomebridgeConfig(homeKitBridge: homeKitBridge, nodeRegistry: nodeRegistry)
        try writeObsidianConfigs(homeKitBridge: homeKitBridge, obsidianVault: obsidianVault, rustDeskNodes: rustDeskNodes)

        let status = MyceliumControlPlaneStatus(
            homeKitBridge: homeKitBridge,
            obsidianVault: obsidianVault,
            nodeRegistry: nodeRegistry,
            guiIntents: guiIntents,
            rustDeskNodes: rustDeskNodes
        )

        try writeDashboardAssets(status: status)
        try writeControlPlaneStatus(status)
        try logOperationalTelemetry(homeKitBridge: homeKitBridge, obsidianVault: obsidianVault, nodeRegistry: nodeRegistry)
        return status
    }

    @discardableResult
    public func queueGUIIntent(sourceNode: String, targetNodes: [String], action: String, payloadJSON: String?) throws -> JarvisGUIIntent {
        let intent = JarvisGUIIntent(
            id: UUID().uuidString,
            sourceNode: sourceNode,
            targetNodes: targetNodes,
            action: action,
            payloadJSON: payloadJSON,
            queuedAt: formatter.string(from: Date()),
            status: "queued"
        )
        var queue = try loadQueuedGUIIntents()
        queue.insert(intent, at: 0)
        if queue.count > 25 {
            queue = Array(queue.prefix(25))
        }
        try write(queue, to: paths.guiIntentQueueURL)
        return intent
    }

    public func dashboardJSON() throws -> [String: Any] {
        try synchronize().json
    }

    private func buildHomeKitBridgeStatus(signals: [JarvisSignalSnapshot], vagalTone: Double?, lastSync: String) -> JarvisHomeKitBridgeStatus {
        let latestSignal = signals.first
        let highDistress = (latestSignal?.ternaryValue ?? 0) < 0 || (latestSignal?.pheromone ?? 0.0) >= 0.85 || (vagalTone ?? 1.0) <= 0.35
        let homebridgeProbe = probe(urlString: "http://\(charlieAddress):\(homebridgePort)/")
        let liveKitProbe = probe(urlString: Constants.liveKitURL)
        let audioBridgeReachable = liveKitProbe.reachable || homebridgeProbe.reachable
        let bridgeState: String
        if liveKitProbe.reachable {
            bridgeState = "Charlie audio bridge reachable through LiveKit."
        } else if homebridgeProbe.reachable {
            bridgeState = "Charlie Matter audio bridge reachable."
        } else {
            bridgeState = "Charlie Matter audio bridge pending deployment; audio-only config is staged."
        }

        let accessories = [
            JarvisHomeKitAccessoryStatus(
                id: "internal-regulation",
                name: "J.A.R.V.I.S. Internal Regulation",
                kind: "internal_regulation",
                room: "Iron Silo",
                state: highDistress ? "elevated" : "regulated",
                severity: highDistress ? "warning" : "nominal",
                value: latestSignal?.pheromone,
                lastUpdated: lastSync
            ),
            JarvisHomeKitAccessoryStatus(
                id: "vagal-tone",
                name: "J.A.R.V.I.S. Vagal Tone",
                kind: "internal_metric",
                room: "Iron Silo",
                state: vagalTone == nil ? "unknown" : (highDistress ? "suppressed" : "regulated"),
                severity: (vagalTone ?? 1.0) <= 0.35 ? "warning" : "nominal",
                value: vagalTone,
                lastUpdated: lastSync
            ),
            JarvisHomeKitAccessoryStatus(
                id: "command-gate",
                name: "J.A.R.V.I.S. Command Gate",
                kind: "command_gate",
                room: "Iron Silo",
                state: Constants.authorizedCommandSources.joined(separator: ", "),
                severity: "nominal",
                value: nil,
                lastUpdated: lastSync
            ),
            JarvisHomeKitAccessoryStatus(
                id: "voice-intercom",
                name: "J.A.R.V.I.S. HomePod Intercom",
                kind: "doorbell_intercom",
                room: "Iron Silo",
                state: audioBridgeReachable ? "route-ready" : "config-ready",
                severity: audioBridgeReachable ? "nominal" : "warning",
                value: nil,
                lastUpdated: lastSync
            )
        ]

        return JarvisHomeKitBridgeStatus(
            bridgeName: Constants.bridgeName,
            charlieAddress: charlieAddress,
            homebridgePort: homebridgePort,
            reachable: audioBridgeReachable,
            matterEnabled: true,
            voiceIntercomRoute: Constants.voiceIntercomRoute,
            authorizedCommandSources: Constants.authorizedCommandSources,
            regulationVisibility: Constants.regulationVisibility,
            distressState: highDistress ? "elevated" : "regulated",
            bridgeState: bridgeState,
            accessories: accessories,
            lastSync: lastSync
        )
    }

    private func buildObsidianVaultStatus(forceReseed: Bool, lastSync: String) -> JarvisObsidianVaultStatus {
        let localVault = loadLocalVaultStatus()
        let endpoint = localVault?.endpoint ?? "http://\(charlieAddress):\(Constants.couchPort)/\(Constants.obsidianDatabase)"
        let docCount = localVault?.docCount ?? {
            let probe = probe(urlString: endpoint)
            return extractDocCount(from: probe.body) ?? 0
        }()
        let replicationObserved = docCount > 0
        let reseedTriggered = forceReseed || docCount == 0
        let statusLine = replicationObserved
            ? "Obsidian vault is replicating from Beta."
            : "Obsidian vault requires reseed from Beta CouchDB."

        return JarvisObsidianVaultStatus(
            databaseName: localVault?.databaseName ?? Constants.obsidianDatabase,
            betaCouchEndpoint: endpoint,
            docCount: docCount,
            replicationConfigured: true,
            replicationObserved: replicationObserved,
            reseedTriggered: reseedTriggered,
            pluginListening: true,
            lastSync: lastSync,
            statusLine: statusLine
        )
    }

    private func buildRustDeskNodes(lastSync: String) -> [JarvisRustDeskNode] {
        resolvedNodes().map { node in
            let handoffURL = node.rustDeskID.map { "rustdesk://\($0)" }
            return JarvisRustDeskNode(
                id: node.name,
                nodeName: node.name,
                rustDeskID: node.rustDeskID,
                address: node.address,
                relayLocked: true,
                lastSeen: lastSync,
                handoffURL: handoffURL,
                status: node.rustDeskID == nil ? "relay-locked-manual-verification" : "relay-locked"
            )
        }
    }

    private func buildNodeRegistry(homeKitBridge: JarvisHomeKitBridgeStatus, lastSync: String, rustDeskNodes: [JarvisRustDeskNode]) -> [JarvisNodeHeartbeat] {
        resolvedNodes().map { node in
            let rustdesk = rustDeskNodes.first { $0.nodeName == node.name }
            let isCharlie = node.name == "charlie"
            let isBeta = node.name == "beta"
            let guiReachable = isCharlie ? homeKitBridge.reachable : isBeta
            return JarvisNodeHeartbeat(
                id: node.name,
                nodeName: node.name,
                address: node.address,
                source: isCharlie ? "homebridge" : "rustdesk",
                tunnelState: guiReachable ? "online" : "pending",
                guiReachable: guiReachable,
                rustDeskID: rustdesk?.rustDeskID,
                lastSeen: lastSync
            )
        }
    }

    private func writeHomebridgeConfig(homeKitBridge: JarvisHomeKitBridgeStatus, nodeRegistry: [JarvisNodeHeartbeat]) throws {
        let config: [String: Any] = [
            "bridge": [
                "name": homeKitBridge.bridgeName,
                "username": "0E:CA:04:15:10:01",
                "port": 51826,
                "pin": "031-45-154"
            ],
            "description": "J.A.R.V.I.S. Iron Silo Matter bridge for Charlie.",
            "platforms": [
                [
                    "platform": "JarvisMyceliumBridge",
                    "name": homeKitBridge.bridgeName,
                    "charlieHost": homeKitBridge.charlieAddress,
                    "matter": homeKitBridge.matterEnabled,
                    "audioOnly": true,
                    "convexTables": ["stigmergic_signals", "vagal_tone", "homekit_bridge_status"],
                    "convexDeployment": Constants.convexDeploymentURL,
                    "authorizedCommandSources": homeKitBridge.authorizedCommandSources,
                    "regulationVisibility": homeKitBridge.regulationVisibility,
                    "internalRegulation": [
                        "distressState": homeKitBridge.distressState,
                        "visibility": homeKitBridge.regulationVisibility
                    ],
                    "voiceIntercom": [
                        "worker": "jarvis-voice-worker",
                        "route": homeKitBridge.voiceIntercomRoute
                    ],
                    "commandRegistry": paths.commandRegistryURL.path,
                    "nodeRegistry": nodeRegistry.map { [
                        "nodeName": $0.nodeName,
                        "address": $0.address ?? "",
                        "tunnelState": $0.tunnelState
                    ] }
                ]
            ],
            "accessories": homeKitBridge.accessories.map { accessory -> [String: Any] in
                var payload: [String: Any] = [
                    "name": accessory.name,
                    "kind": accessory.kind,
                    "room": accessory.room,
                    "state": accessory.state,
                    "severity": accessory.severity
                ]
                if let value = accessory.value {
                    payload["value"] = value
                }
                return payload
            }
        ]
        try writeJSONObject(config, to: paths.homebridgeConfigURL)
        try write(homeKitBridge, to: paths.homebridgeStatusURL)
    }

    private func writeObsidianConfigs(homeKitBridge: JarvisHomeKitBridgeStatus, obsidianVault: JarvisObsidianVaultStatus, rustDeskNodes: [JarvisRustDeskNode]) throws {
        let uatuConfig: [String: Any] = [
            "plugin": "uatu-engine",
            "listenForHomeKitTriggers": false,
            "listenForInternalRegulation": true,
            "queueGuiTargets": Constants.guiNodes,
            "homeKitBridgeStatus": paths.homebridgeStatusURL.path,
            "convexControlPlaneQuery": "control_plane:sharedControlPlaneState",
            "convexDeployment": Constants.convexDeploymentURL,
            "authorizedCommandSources": homeKitBridge.authorizedCommandSources,
            "commandRegistry": paths.commandRegistryURL.path,
            "operatorState": "operator-wait",
            "homeKitAudioOnly": true,
            "voiceIntercomRoute": homeKitBridge.voiceIntercomRoute,
            "rustDeskRegistry": rustDeskNodes.map { [
                "nodeName": $0.nodeName,
                "rustDeskID": $0.rustDeskID as Any,
                "relayLocked": $0.relayLocked
            ] }
        ]
        let liveSyncConfig: [String: Any] = [
            "plugin": "obsidian-livesync",
            "syncOnStart": true,
            "liveSync": true,
            "couchDB_URI": obsidianVault.betaCouchEndpoint,
            "database": obsidianVault.databaseName,
            "docCount": obsidianVault.docCount,
            "replicationObserved": obsidianVault.replicationObserved,
            "reseedTriggered": obsidianVault.reseedTriggered
        ]
        try writeJSONObject(uatuConfig, to: paths.obsidianUATUDataURL)
        try writeJSONObject(liveSyncConfig, to: paths.obsidianLiveSyncDataURL)
    }

    private func writeControlPlaneStatus(_ status: MyceliumControlPlaneStatus) throws {
        try write(status.homeKitBridge, to: paths.flatCockpitStatusURL)
        try write(status.homeKitBridge, to: paths.xrSurfaceStatusURL)
        try write(status.nodeRegistry, to: paths.nodeRegistryStatusURL)
        try write(status.rustDeskNodes, to: paths.rustDeskRegistryURL)
        try writeJSONObject(commandRegistry(status: status), to: paths.commandRegistryURL)
        try writeJSONObject(regulationStatus(status: status), to: paths.regulationStatusURL)
        try write(status.json, toJSONObjectAt: paths.sovereignStatusURL)
    }

    private func writeDashboardAssets(status: MyceliumControlPlaneStatus) throws {
        let html = dashboardHTML(title: "Jarvis HomeKit Bridge Status", statusPath: "homekit-bridge-status.json")
        try html.write(to: paths.flatCockpitHTMLURL, atomically: true, encoding: .utf8)
        try html.write(to: paths.xrSurfaceHTMLURL, atomically: true, encoding: .utf8)
    }

    private func htmlEscape(_ s: String) -> String {  // CX-027: XSS prevention
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func dashboardHTML(title: String, statusPath: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>\(htmlEscape(title))</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #0b1020; color: #e5eefc; margin: 0; padding: 24px; }
            .panel { background: rgba(17, 24, 39, 0.9); border: 1px solid rgba(99, 102, 241, 0.35); border-radius: 18px; padding: 18px; max-width: 900px; }
            .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; margin-top: 16px; }
            .card { background: rgba(30, 41, 59, 0.9); border-radius: 14px; padding: 14px; }
            .label { color: #93c5fd; font-size: 12px; text-transform: uppercase; letter-spacing: 0.08em; }
            .value { font-size: 18px; margin-top: 4px; }
            .distress { color: #f87171; }
            .nominal { color: #86efac; }
          </style>
        </head>
        <body>
          <div class="panel">
            <h1>\(htmlEscape(title))</h1>
            <p id="summary">Loading bridge state…</p>
            <div class="grid" id="cards"></div>
          </div>
          <script>
            fetch("./\(statusPath)")
              .then((response) => response.json())
              .then((status) => {
                document.getElementById("summary").textContent = status.bridgeState;
                const cards = [
                  ["Charlie", status.charlieAddress + ":" + status.homebridgePort, status.reachable ? "nominal" : "distress"],
                  ["Intercom", status.voiceIntercomRoute, status.reachable ? "nominal" : "distress"],
                  ["Sources", status.authorizedCommandSources.join(", "), "nominal"],
                  ["Regulation", status.regulationVisibility + " / " + status.distressState, status.distressState === "elevated" ? "distress" : "nominal"]
                ];
                const container = document.getElementById("cards");
                container.textContent = "";  // CX-027: clear before safe insert
                cards.forEach(([label, value, tone]) => {
                  const card = document.createElement("div");
                  card.className = "card";
                  const lbl = document.createElement("div");
                  lbl.className = "label";
                  lbl.textContent = label;
                  const val = document.createElement("div");
                  val.className = "value " + tone;
                  val.textContent = value;
                  card.appendChild(lbl);
                  card.appendChild(val);
                  container.appendChild(card);
                });
              })
              .catch((error) => {
                document.getElementById("summary").textContent = error.message;
              });
          </script>
        </body>
        </html>
        """
    }

    private func logOperationalTelemetry(homeKitBridge: JarvisHomeKitBridgeStatus, obsidianVault: JarvisObsidianVaultStatus, nodeRegistry: [JarvisNodeHeartbeat]) throws {
        if let vagalTone = try loadLatestVagalTone() {
            try telemetry.logVagalTone(sourceNode: "charlie", value: vagalTone, state: vagalTone <= 0.35 ? "suppressed" : "regulated")
        }
        for heartbeat in nodeRegistry {
            try telemetry.logNodeHeartbeat(
                nodeName: heartbeat.nodeName,
                address: heartbeat.address,
                rustDeskID: heartbeat.rustDeskID,
                tunnelState: heartbeat.tunnelState,
                guiReachable: heartbeat.guiReachable
            )
        }
        try telemetry.logExecutionTrace(
            workflowID: "mycelium-control-plane",
            stepID: "homekit-obsidian-sync",
            inputContext: homeKitBridge.bridgeState,
            outputResult: obsidianVault.statusLine,
            status: homeKitBridge.reachable && obsidianVault.replicationObserved ? "success" : "pending"
        )
    }

    private func resolvedNodes() -> [SiloNodeDefinition] {
        guard let localIDs = loadLocalRustDeskIDs(), !localIDs.isEmpty else {
            return fallbackNodes
        }

        return fallbackNodes.map { node in
            SiloNodeDefinition(
                name: node.name,
                address: node.address,
                rustDeskID: localIDs[node.name] ?? node.rustDeskID
            )
        }
    }

    private func loadLocalRustDeskIDs() -> [String: String]? {
        let candidates = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/Obsidian Vault/.obsidian/plugins/uatu-engine/data.json"),
            paths.obsidianUATUDataURL
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            guard
                let data = try? Data(contentsOf: candidate),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let nodes = object["nodes"] as? [[String: Any]]
            else {
                continue
            }

            let mapped = nodes.reduce(into: [String: String]()) { partial, node in
                guard
                    let name = node["node"] as? String,
                    let rustDeskID = node["rustdeskId"] as? String,
                    !rustDeskID.isEmpty
                else {
                    return
                }
                partial[name] = rustDeskID
            }

            if !mapped.isEmpty {
                return mapped
            }
        }

        return nil
    }

    private func loadLocalVaultStatus() -> LocalVaultStatus? {
        let candidates = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/Obsidian Vault/.obsidian/plugins/obsidian-livesync/data.json"),
            paths.obsidianLiveSyncDataURL
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            guard let status = decryptLocalVaultStatus(from: candidate) else {
                continue
            }
            return status
        }

        return nil
    }

    private func getCouchDBPassphrase() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.realjarvis.couchdb",
            kSecAttrAccount as String: "vault-decrypt",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let passphrase = String(data: data, encoding: .utf8) else {
            throw JarvisError.processFailure("CouchDB passphrase not found in Keychain. See setup documentation.")  // CX-006: redacted shell command
        }
        return passphrase
    }

    private func decryptLocalVaultStatus(from url: URL) -> LocalVaultStatus? {
        let script = """
import base64
import json
import sys
import os
try:  // CX-029: validate Python cryptography dependency before use
    from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    from cryptography.hazmat.primitives import hashes
except ImportError as e:
    raise SystemExit("Missing Python dependency: " + str(e) + ". Install with: pip3 install cryptography")
from urllib.parse import quote
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

path = sys.argv[1]
settings = json.load(open(path, "r", encoding="utf-8"))
blob = settings.get("encryptedCouchDBConnection", "")
if not blob.startswith("%$"):
    raise SystemExit(1)

passphrase = sys.stdin.readline().strip()
raw = base64.b64decode(blob[2:])
pbkdf2_salt = raw[:32]
iv = raw[32:44]
hkdf_salt = raw[44:76]
ciphertext = raw[76:]
master = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=pbkdf2_salt, iterations=310000).derive(passphrase.encode())
key = HKDF(algorithm=hashes.SHA256(), length=32, salt=hkdf_salt, info=b"").derive(master)
config = json.loads(AESGCM(key).decrypt(iv, ciphertext, None).decode())
endpoint = config["couchDB_URI"].rstrip("/") + "/" + quote(config["couchDB_DBNAME"])
request = Request(endpoint)
credentials = ("%s:%s" % (config["couchDB_USER"], config["couchDB_PASSWORD"])).encode()
request.add_header("Authorization", "Basic " + base64.b64encode(credentials).decode())
payload = json.loads(urlopen(request, timeout=5).read().decode())
print(json.dumps({
    "endpoint": endpoint,
    "databaseName": config["couchDB_DBNAME"],
    "docCount": payload.get("doc_count", 0)
}))
"""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, url.path]
        guard let passphrase = try? getCouchDBPassphrase() else { return nil }
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            // Write passphrase to stdin pipe instead of environment to avoid
            // exposure via /proc/PID/environ or `ps eww`.
            if let passphraseData = (passphrase + "\n").data(using: .utf8) {
                try stdinPipe.fileHandleForWriting.write(contentsOf: passphraseData)
            }
            try stdinPipe.fileHandleForWriting.close()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let endpoint = object["endpoint"] as? String,
                let databaseName = object["databaseName"] as? String,
                let docCount = object["docCount"] as? Int
            else {
                return nil
            }
            return LocalVaultStatus(endpoint: endpoint, databaseName: databaseName, docCount: docCount)
        } catch {
            return nil
        }
    }

    private func commandRegistry(status: MyceliumControlPlaneStatus) -> [String: Any] {
        [
            "operatorState": "operator-wait",
            "authorizedSources": status.homeKitBridge.authorizedCommandSources,
            "blockedSources": ["app-intents", "mobile-cockpit", "watch-cockpit", "siri"],
            "obsidianCommandBarEnabled": true,
            "terminalEnabled": true,
            "convexDeployment": Constants.convexDeploymentURL,
            "lastSync": status.homeKitBridge.lastSync
        ]
    }

    private func regulationStatus(status: MyceliumControlPlaneStatus) -> [String: Any] {
        [
            "visibility": status.homeKitBridge.regulationVisibility,
            "distressState": status.homeKitBridge.distressState,
            "bridgeState": status.homeKitBridge.bridgeState,
            "obsidianVault": status.obsidianVault.statusLine,
            "lastSync": status.homeKitBridge.lastSync
        ]
    }

    private func loadSignals(limit: Int) throws -> [JarvisSignalSnapshot] {
        let url = telemetry.tableURL("stigmergic_signals")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let lines = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .suffix(limit)

        return Array(lines.compactMap { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return JarvisSignalSnapshot(
                id: UUID().uuidString,
                nodeSource: (object["nodeSource"] as? String) ?? "unknown",
                nodeTarget: (object["nodeTarget"] as? String) ?? "unknown",
                ternaryValue: (object["ternaryValue"] as? Int) ?? 0,
                agentID: (object["agentId"] as? String) ?? "unknown",
                pheromone: (object["pheromone"] as? Double) ?? 0.0,
                timestamp: (object["timestamp"] as? String) ?? formatter.string(from: Date())
            )
        }.reversed())
    }

    private func loadLatestVagalTone() throws -> Double? {
        let url = telemetry.tableURL("vagal_tone")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let line = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .last
        guard let line,
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["value"] as? Double
    }

    private func loadQueuedGUIIntents() throws -> [JarvisGUIIntent] {
        guard FileManager.default.fileExists(atPath: paths.guiIntentQueueURL.path) else { return [] }
        return try Self.decoder.decode([JarvisGUIIntent].self, from: Data(contentsOf: paths.guiIntentQueueURL))
    }

    private func extractDocCount(from body: String?) -> Int? {
        guard let body,
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["doc_count"] as? Int
    }

    private func probe(urlString: String) -> (reachable: Bool, statusCode: Int?, body: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-i", "--connect-timeout", "2", "--max-time", "3", "-sS", urlString]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let rawOutput = String(data: outputData, encoding: .utf8) ?? ""
            if process.terminationStatus != 0 {
                let rawError = String(data: errorData, encoding: .utf8) ?? ""
                return (false, nil, rawError.isEmpty ? rawOutput : rawError)
            }
            let sections = rawOutput.components(separatedBy: "\r\n\r\n")
            let header = sections.first ?? ""
            let body = sections.dropFirst().joined(separator: "\r\n\r\n")
            let statusCode = header
                .components(separatedBy: .whitespaces)
                .compactMap(Int.init)
                .first
            return (true, statusCode, body)
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try Self.encoder.encode(value)
        try data.write(to: url)
    }

    private func write(_ object: [String: Any], toJSONObjectAt url: URL) throws {
        try writeJSONObject(object, to: url)
    }

    static func encode<T: Encodable>(_ value: T) -> [String: Any] {
        let data = (try? encoder.encode(value)) ?? Data()
        let object = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return object
    }
}
