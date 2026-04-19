import Foundation
#if canImport(IOKit)
import IOKit
#endif
import CryptoKit

// MARK: - A&Ox4 Probe
//
// Alert and Oriented, Times Four — the paramedic ethic's operational
// definition of consciousness, ported concept-only across the Natural-
// Language Barrier from the Aragorn-class corpus.
//
// Four axes: Person, Place, Time, Event. A node that cannot answer all
// four with confidence >= threshold is degraded and must halt output.
//
// Real probes (this file):
//   Person  — operator-of-record from a ratified Soul Anchor genesis.
//   Place   — IOPlatformUUID + hostname + primary SSID, hashed to a
//             stable place-fingerprint that doesn't leak raw identifiers
//             into telemetry.
//   Time    — wall clock + monotonic uptime cross-check with sanity
//             floor (rejects unset clocks).
//   Event   — recency of telemetry activity; derives "currently doing
//             something meaningful" from active JSONL streams.
//
// See: /PRINCIPLES.md §3, /VERIFICATION_PROTOCOL.md §1.5, /SOUL_ANCHOR.md

public enum AOxAxis: String, Codable, Sendable, CaseIterable {
    case person
    case place
    case time
    case event
}

public struct AOxProbeResult: Codable, Sendable, Equatable {
    public let axis: AOxAxis
    public let payload: String?
    public let confidence: Double
    public let timestamp: String
    public let notes: String?

    public var isOriented: Bool {
        guard let payload, !payload.isEmpty else { return false }
        return confidence >= 0.75
    }
}

public struct AOxStatus: Codable, Sendable, Equatable {
    public let results: [AOxProbeResult]
    public let orientedAxes: Int
    public let level: Int   // 0..4, the X in "A&Ox4"
    public let timestamp: String

    public var isFullyOriented: Bool { level >= 4 }
}

public final class AOxFourProbe {
    private let paths: WorkspacePaths
    private let telemetry: TelemetryStore
    private let formatter: ISO8601DateFormatter
    private let confidenceThreshold: Double

    public init(paths: WorkspacePaths,
                telemetry: TelemetryStore,
                confidenceThreshold: Double = 0.75) {
        self.paths = paths
        self.telemetry = telemetry
        self.formatter = ISO8601DateFormatter()
        self.confidenceThreshold = confidenceThreshold
    }

    // MARK: Individual probes

    public func probePerson() -> AOxProbeResult {
        // Person = can this node name its operator with cryptographic
        // backing? We read genesis.json directly (light-touch, doesn't
        // depend on the full SoulAnchor dual-sig verification path) and
        // require the ratified status plus a named operator.
        let genesisURL = paths.root
            .appendingPathComponent(".jarvis", isDirectory: true)
            .appendingPathComponent("soul_anchor", isDirectory: true)
            .appendingPathComponent("genesis.json")

        let data: Data
        do {
            data = try Data(contentsOf: genesisURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return result(axis: .person, payload: nil, confidence: 0.0,
                          notes: "genesis.json not found at \(genesisURL.path)")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
            return result(axis: .person, payload: nil, confidence: 0.0,
                          notes: "genesis.json: permission denied at \(genesisURL.path)")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == 256 {
            // CocoaError.Code(rawValue: 256) = NSFileReadIsDirectory
            return result(axis: .person, payload: nil, confidence: 0.0,
                          notes: "genesis.json: expected file but found directory at \(genesisURL.path)")
        } catch {
            return result(axis: .person, payload: nil, confidence: 0.0,
                          notes: "genesis.json read error: \(error.localizedDescription)")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return result(axis: .person, payload: nil, confidence: 0.0,
                          notes: "genesis.json is not valid JSON or not a JSON object")
        }
        let status = (obj["status"] as? String) ?? ""
        let ratified = status.uppercased() == "RATIFIED"

        var operatorLabel: String? = nil
        if let legacy = obj["operatorOfRecord"] as? String, !legacy.isEmpty {
            operatorLabel = legacy
        } else if let op = obj["operator"] as? [String: Any] {
            let callsign = (op["callsign"] as? String) ?? ""
            let legal = (op["legal_name"] as? String) ?? ""
            let creds = (op["credentials"] as? String) ?? ""
            var parts: [String] = []
            if !callsign.isEmpty { parts.append(callsign) }
            if !legal.isEmpty { parts.append("(\(legal))") }
            if !creds.isEmpty { parts.append("— \(creds)") }
            if !parts.isEmpty { operatorLabel = parts.joined(separator: " ") }
        }

        guard let op = operatorLabel, !op.isEmpty else {
            return result(axis: .person, payload: nil, confidence: 0.0,
                          notes: "genesis.json does not name an operator")
        }
        // CX-030: sanity floor — reduce confidence if genesis.json is stale
        var confidence = ratified ? 0.95 : 0.70
        if let attrs = try? FileManager.default.attributesOfItem(atPath: genesisURL.path),
           let modDate = attrs[.modificationDate] as? Date {
            let age = Date().timeIntervalSince(modDate)
            if age > 31_536_000 {  // >1 year old
                confidence = min(confidence, 0.50)
            }
        }
        return result(axis: .person,
                      payload: op,
                      confidence: confidence,
                      notes: ratified ? "bound to ratified genesis" : "operator named but status != RATIFIED")
    }

    public func probePlace() -> AOxProbeResult {
        let host = ProcessInfo.processInfo.hostName
        let hwUUID = Self.platformUUID()
        let ssid = Self.primarySSID()

        // Build a stable place-fingerprint without leaking raw IDs.
        // Telemetry carries the hash; the raw UUID never hits JSONL.
        // CX-046: salt with workspace root path to prevent preimage attacks
        var material = Data()
        material.append(paths.root.path.data(using: .utf8) ?? Data())  // salt
        material.append(0x1e)
        material.append(host.data(using: .utf8) ?? Data())
        material.append(0x1f)
        material.append((hwUUID ?? "").data(using: .utf8) ?? Data())
        material.append(0x1f)
        material.append((ssid ?? "").data(using: .utf8) ?? Data())
        let fp = SHA256.hash(data: material)
            .map { String(format: "%02x", $0) }.joined()
            .prefix(16)

        var components: [String] = ["host:\(host)"]
        var confidence = 0.50
        if hwUUID != nil {
            components.append("hw:locked")
            confidence += 0.30
        } else {
            components.append("hw:unknown")
            // CX-041: log UUID fallback so operators see the degradation
            try? telemetry.logExecutionTrace(
                workflowID: "aox4-probe",
                stepID: "place-uuid-fallback",
                inputContext: "probePlace",
                outputResult: "IOPlatformUUID unavailable — place fingerprint degraded",
                status: "warning"
            )
        }
        if let ssid, !ssid.isEmpty {
            components.append("net:\(ssid)")
            confidence += 0.15
        } else {
            components.append("net:offline")
        }
        components.append("fp:\(fp)")

        return result(axis: .place,
                      payload: components.joined(separator: "; "),
                      confidence: min(confidence, 0.95),
                      notes: hwUUID == nil ? "IOPlatformUUID unavailable" : nil)
    }

    public func probeTime() -> AOxProbeResult {
        let now = Date()
        let iso = formatter.string(from: now)
        let monotonic = ProcessInfo.processInfo.systemUptime

        // Sanity floor: if the wall clock is before the genesis epoch
        // this system could not have been ratified, so Time is not
        // trustworthy. 2024-01-01 UTC is comfortably before any real run.
        let sanityFloor: TimeInterval = 1_704_067_200 // 2024-01-01T00:00:00Z
        let wall = now.timeIntervalSince1970
        if wall < sanityFloor {
            return result(axis: .time,
                          payload: "wall:\(iso); uptime:\(monotonic)",
                          confidence: 0.10,
                          notes: "wall clock below sanity floor — Time not oriented")
        }
        if monotonic < 0 {
            return result(axis: .time,
                          payload: "wall:\(iso); uptime:\(monotonic)",
                          confidence: 0.30,
                          notes: "monotonic uptime negative — clock drift suspected")
        }
        return result(axis: .time,
                      payload: "wall:\(iso); uptime:\(Int(monotonic))s",
                      confidence: 0.99,
                      notes: nil)
    }

    public func probeEvent() -> AOxProbeResult {
        // "Event" = is this node currently participating in a live
        // workflow? We read the telemetry directory: any JSONL file
        // touched in the recent window counts as an active stream.
        let fileManager = FileManager.default
        let telemetryDir = paths.telemetryDirectory
        let freshnessWindow: TimeInterval = 300 // 5 minutes

        guard let entries = try? fileManager.contentsOfDirectory(
            at: telemetryDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return result(axis: .event,
                          payload: "telemetry:unavailable",
                          confidence: 0.20,
                          notes: "telemetry directory not readable")
        }

        let now = Date()
        var activeStreams: [String] = []
        var mostRecent: Date?
        for url in entries where url.pathExtension.lowercased() == "jsonl" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if now.timeIntervalSince(mtime) <= freshnessWindow {
                activeStreams.append(url.deletingPathExtension().lastPathComponent)
                if mostRecent == nil || mtime > mostRecent! {
                    mostRecent = mtime
                }
            }
        }

        if activeStreams.isEmpty {
            return result(axis: .event,
                          payload: "streams:idle; window:\(Int(freshnessWindow))s",
                          confidence: 0.55,
                          notes: "no telemetry within freshness window — event context idle")
        }
        let streamsStr = activeStreams.sorted().prefix(6).joined(separator: ",")
        let ageSec = Int(now.timeIntervalSince(mostRecent ?? now))
        // R08: detect clock skew — negative age means mtime is in the future
        let age = mostRecent != nil ? now.timeIntervalSince(mostRecent!) : 0.0
        if age < 0 {
            return result(axis: .event,
                          payload: "clock-skew-detected; age=\(Int(age))s",
                          confidence: 0.10,
                          notes: "Negative event age (\(String(format: "%.1f", age))s) indicates clock skew — confidence degraded")
        }
        // CX-031: scale confidence by freshness — newest activity gets 0.88,
        // activity at window edge gets 0.55
        let freshness = max(0, min(1.0, 1.0 - age / freshnessWindow))
        let confidence = 0.55 + (0.33 * freshness)
        return result(axis: .event,
                      payload: "streams:\(streamsStr); newest:\(ageSec)s",
                      confidence: confidence,
                      notes: nil)
    }

    // MARK: Composite

    public func status() throws -> AOxStatus {
        let results = [probePerson(), probePlace(), probeTime(), probeEvent()]
        let oriented = results.filter { $0.isOriented }.count
        let status = AOxStatus(results: results,
                               orientedAxes: oriented,
                               level: oriented,
                               timestamp: formatter.string(from: Date()))
        try logStatus(status)
        try persistLatest(status)
        return status
    }

    /// Absolute URL of the freshest-report file written by every `status()` call.
    /// External gates (e.g. `jarvis-lockdown.zsh`) read this instead of
    /// tailing the JSONL stream, so they can enforce level==4 + freshness
    /// without parsing ndjson.
    public var latestStatusURL: URL {
        paths.telemetryDirectory.appendingPathComponent("aox4_latest.json")
    }

    /// Hard gate: call before any action that requires full orientation.
    /// Throws if A&Ox < 4.
    public func requireFullOrientation() throws -> AOxStatus {
        let s = try status()
        if !s.isFullyOriented {
            throw JarvisError.processFailure(
                "A&Ox\(s.level): node is not fully oriented; output suppressed per PRINCIPLES.md §3."
            )
        }
        return s
    }

    // MARK: Helpers

    private func result(axis: AOxAxis,
                        payload: String?,
                        confidence: Double,
                        notes: String?) -> AOxProbeResult {
        AOxProbeResult(axis: axis,
                       payload: payload,
                       confidence: confidence,
                       timestamp: formatter.string(from: Date()),
                       notes: notes)
    }

    private func logStatus(_ status: AOxStatus) throws {
        for r in status.results {
            try telemetry.append(record: [
                "axis": r.axis.rawValue,
                "payload": r.payload ?? "",
                "confidence": r.confidence,
                "oriented": r.isOriented,
                "notes": r.notes ?? "",
                "composite_level": status.level
            ], to: "aox4_probes")
        }
    }

    /// Write the freshest AOxStatus atomically to a single well-known file
    /// so out-of-process gates can read one snapshot instead of tailing ndjson.
    private func persistLatest(_ status: AOxStatus) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.telemetryDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(status)
        try data.write(to: latestStatusURL, options: [.atomic])
    }

    // MARK: Platform bindings

    /// IOPlatformUUID — stable hardware identifier on macOS. Returns
    /// nil if IOKit is unavailable or the key can't be read.
    fileprivate static func platformUUID() -> String? {
        #if canImport(IOKit) && !os(iOS) && !os(watchOS) && !os(tvOS)
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let key = "IOPlatformUUID" as CFString
        guard let cf = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0) else {
            return nil
        }
        return (cf.takeRetainedValue() as? String)
        #else
        return nil
        #endif
    }

    /// Primary Wi-Fi SSID via `networksetup`. Returns nil if offline or
    /// the tool is unavailable (non-macOS / sandboxed).
    fileprivate static func primarySSID() -> String? {
        #if os(macOS)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-getairportnetwork", "en0"]
        // CX-039: force C locale so output parsing works on non-English systems
        task.environment = (ProcessInfo.processInfo.environment).merging(["LC_ALL": "C"]) { _, new in new }
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        // Output format: "Current Wi-Fi Network: <ssid>" or
        // "You are not associated with an AirPort network."
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = line.range(of: ":") else { return nil }
        let value = line[colon.upperBound...].trimmingCharacters(in: .whitespaces)
        if value.lowercased().contains("not associated") { return nil }
        return value.isEmpty ? nil : value
        #else
        return nil
        #endif
    }
}
