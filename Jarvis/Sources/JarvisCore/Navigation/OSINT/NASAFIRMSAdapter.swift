import Foundation

/// NAV-001 Phase D: NASA FIRMS (Fire Information for Resource Management) adapter.
///
/// Wraps the `firms.nasa` registry source. Fetches active-fire hotspots
/// from MODIS/VIIRS for situational awareness. Registry host:
/// `firms.modaps.eosdis.nasa.gov`.
///
/// Fail-closed: every URL passes through `OSINTFetchGuard`. Malformed
/// JSON throws `.malformedPayload`.
public struct NASAFIRMSAdapter: HazardAdapter, Sendable {
    public let sourceKey: String = "firms.nasa"

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
        let urlString = "https://firms.modaps.eosdis.nasa.gov/api/country/csv/DEMO_KEY/VIIRS_SNPP_NRT/USA/1"
        guard let url = URL(string: urlString) else {
            throw OSINTAdapterError.hostNotAuthorized("firms.modaps.eosdis.nasa.gov")
        }
        let authResult = guard_.authorize(url: url, principal: principal)
        switch authResult {
        case .success: break
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

        do {
            let raw = try decoder.decode([FIRMSFirePoint].self, from: data)
            return raw.map { point in
                HazardOverlayFeature(
                    id: point.id,
                    sourceKey: sourceKey,
                    category: .fire,
                    severity: point.confidence > 80 ? .critical : .elevated,
                    geometry: .point(lat: point.latitude, lon: point.longitude),
                    observedAt: point.observedAt,
                    ttl: 600,
                    summary: "Active fire detection — confidence \(point.confidence)%"
                )
            }
        } catch {
            throw OSINTAdapterError.malformedPayload("FIRMS parse failed: \(error.localizedDescription)")
        }
    }
}

/// FIRMS fire point JSON structure (mirrors fixture).
private struct FIRMSFirePoint: Codable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let confidence: Int
    let observedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, confidence
        case latitude = "lat"
        case longitude = "lon"
        case observedAt = "observed_at"
    }
}