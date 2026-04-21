import Foundation

/// NAV-001 Phase D: USGS Earthquake Hazards adapter.
///
/// Wraps the `usgs.quake` registry source. Fetches recent earthquake
/// data from the USGS GeoJSON feed. Registry host:
/// `earthquake.usgs.gov`.
///
/// Fail-closed: every URL passes through `OSINTFetchGuard`. Malformed
/// JSON throws `.malformedPayload`.
///
/// Note: Earthquake data feeds into `ScenePreSearch` tier policy.
/// Operator tier gets seismic; companion tier does not (documented in
/// module wiki).
public struct USGSEarthquakeAdapter: HazardAdapter, Sendable {
    public let sourceKey: String = "usgs.quake"

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
        let urlString = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&minmagnitude=2.5"
        guard let url = URL(string: urlString) else {
            throw OSINTAdapterError.hostNotAuthorized("earthquake.usgs.gov")
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
            let response = try decoder.decode(USGSQuakeResponse.self, from: data)
            return response.features.map { feature in
                HazardOverlayFeature(
                    id: feature.id,
                    sourceKey: sourceKey,
                    category: .seismic,
                    severity: feature.magnitude >= 5.0 ? .critical : (feature.magnitude >= 3.5 ? .elevated : .info),
                    geometry: .point(lat: feature.latitude, lon: feature.longitude),
                    observedAt: feature.observedAt,
                    ttl: 900,
                    summary: "M\(String(format: "%.1f", feature.magnitude)) earthquake — \(feature.place)"
                )
            }
        } catch {
            throw OSINTAdapterError.malformedPayload("USGS parse failed: \(error.localizedDescription)")
        }
    }
}

/// USGS earthquake GeoJSON response structure (mirrors fixture).
private struct USGSQuakeResponse: Codable, Sendable {
    let features: [USGSQuakeFeature]
}

private struct USGSQuakeFeature: Codable, Sendable {
    let id: String
    let magnitude: Double
    let latitude: Double
    let longitude: Double
    let place: String
    let observedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, place
        case magnitude = "mag"
        case latitude = "lat"
        case longitude = "lon"
        case observedAt = "observed_at"
    }
}