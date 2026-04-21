import Foundation

/// NAV-001 Phase D: TxDOT DriveTexas hazard adapter.
///
/// Wraps the `txdot.drivetexas` registry source. Fetches traffic
/// incidents, road closures, and message sign data from TxDOT.
/// Registry hosts: `drivetexas.org`, `its.txdot.gov`.
///
/// Fail-closed: every URL passes through `OSINTFetchGuard`. Malformed
/// JSON throws `.malformedPayload`.
public struct TxDOTDriveTexasAdapter: HazardAdapter, Sendable {
    public let sourceKey: String = "txdot.drivetexas"

    private let guard_: OSINTFetchGuard
    private let transport: any HazardTransport
    private let decoder: JSONDecoder

    public init(
        registry: OSINTSourceRegistry = .canonical,
        transport: any HazardTransport = URLSessionHazardTransport()
    ) {
        self.guard_ = OSINTFetchGuard(registry: registry)
        self.transport = transport
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func fetch(principal: Principal) async throws -> [HazardOverlayFeature] {
        let urlString = "https://drivetexas.org/api/incidents"
        guard let url = URL(string: urlString) else {
            throw OSINTAdapterError.hostNotAuthorized("drivetexas.org")
        }
        // Fail-closed: authorize through OSINTFetchGuard.
        let authResult = guard_.authorize(url: url, principal: principal)
        switch authResult {
        case .success:
            break
        case .failure(let denial):
            throw OSINTAdapterError.hostNotAuthorized(denial.description)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let data: Data
        do {
            data = try await transport.fetch(request)
        } catch {
            throw OSINTAdapterError.transportFailed(error.localizedDescription)
        }

        // Parse TxDOT incident array.
        do {
            let raw = try decoder.decode([TxDOTIncident].self, from: data)
            return raw.map { incident in
                HazardOverlayFeature(
                    id: incident.id,
                    sourceKey: sourceKey,
                    category: .traffic,
                    severity: mapSeverity(incident.severity),
                    geometry: .point(lat: incident.latitude, lon: incident.longitude),
                    observedAt: incident.observedAt,
                    ttl: 300,
                    summary: incident.summary
                )
            }
        } catch {
            throw OSINTAdapterError.malformedPayload("TxDOT parse failed: \(error.localizedDescription)")
        }
    }

    private func mapSeverity(_ raw: String) -> HazardSeverity {
        switch raw.lowercased() {
        case "critical", "severe", "fatal": return .critical
        case "elevated", "major", "serious": return .elevated
        default: return .info
        }
    }
}

/// TxDOT incident JSON structure (mirrors fixture).
private struct TxDOTIncident: Codable, Sendable {
    let id: String
    let severity: String
    let latitude: Double
    let longitude: Double
    let observedAt: Date
    let summary: String

    enum CodingKeys: String, CodingKey {
        case id, severity, summary
        case latitude = "lat"
        case longitude = "lon"
        case observedAt = "observed_at"
    }
}