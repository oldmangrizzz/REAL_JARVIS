import Foundation

/// NAV-001 Phase D: NOAA/NWS weather hazard adapter.
///
/// Wraps the `noaa.nws` registry source. Fetches active weather alerts
/// from the National Weather Service API. Registry hosts:
/// `api.weather.gov`, `radar.weather.gov`.
///
/// Fail-closed: every URL passes through `OSINTFetchGuard`. Malformed
/// JSON throws `.malformedPayload`.
public struct NOAAWeatherAdapter: HazardAdapter, Sendable {
    public let sourceKey: String = "noaa.nws"

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
        let urlString = "https://api.weather.gov/alerts/active"
        guard let url = URL(string: urlString) else {
            throw OSINTAdapterError.hostNotAuthorized("api.weather.gov")
        }
        let authResult = guard_.authorize(url: url, principal: principal)
        switch authResult {
        case .success: break
        case .failure(let denial):
            throw OSINTAdapterError.hostNotAuthorized(denial.description)
        }

        var request = URLRequest(url: url)
        request.setValue("RealJarvis/1.0 (contact@realjarvis.ai)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        let data: Data
        do {
            data = try await transport.fetch(request)
        } catch {
            throw OSINTAdapterError.transportFailed(error.localizedDescription)
        }

        do {
            let response = try decoder.decode(NOAAAlertsResponse.self, from: data)
            return response.features.map { alert in
                HazardOverlayFeature(
                    id: alert.id,
                    sourceKey: sourceKey,
                    category: .weather,
                    severity: mapSeverity(alert.severity),
                    geometry: .point(lat: alert.latitude, lon: alert.longitude),
                    observedAt: alert.observedAt,
                    ttl: 600,
                    summary: alert.headline
                )
            }
        } catch {
            throw OSINTAdapterError.malformedPayload("NOAA parse failed: \(error.localizedDescription)")
        }
    }

    private func mapSeverity(_ raw: String) -> HazardSeverity {
        switch raw.lowercased() {
        case "extreme", "critical": return .critical
        case "severe", "major", "elevated": return .elevated
        default: return .info
        }
    }
}

/// NOAA alerts API response structure (mirrors fixture).
private struct NOAAAlertsResponse: Codable, Sendable {
    let features: [NOAAAlert]
}

private struct NOAAAlert: Codable, Sendable {
    let id: String
    let severity: String
    let latitude: Double
    let longitude: Double
    let observedAt: Date
    let headline: String

    enum CodingKeys: String, CodingKey {
        case id, severity, headline
        case latitude = "lat"
        case longitude = "lon"
        case observedAt = "observed_at"
    }
}