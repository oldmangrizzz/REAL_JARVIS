import XCTest
@testable import JarvisCore

/// NAV-001 Phase D tests: Hazard adapters.
///
/// All tests inject stub transports with JSON fixtures. No network.
/// Fail-closed: malformed JSON throws, unauthorized hosts throw.
final class HazardAdaptersTests: XCTestCase {

    // MARK: - Stub transport

    struct StubHazardTransport: HazardTransport, Sendable {
        let data: Data?
        let error: Error?

        init(data: Data? = nil, error: Error? = nil) {
            self.data = data
            self.error = error
        }

        func fetch(_ request: URLRequest) async throws -> Data {
            if let e = error { throw e }
            guard let d = data else { throw OSINTAdapterError.transportFailed("no data") }
            return d
        }
    }

    // MARK: - TxDOT

    func testTxDOTAdapterParsesGolden() async throws {
        let json = """
        [
            {
                "id": "tx-001",
                "severity": "major",
                "lat": 30.2672,
                "lon": -97.7431,
                "observed_at": "2026-04-20T12:00:00Z",
                "summary": "Major incident on I-35"
            }
        ]
        """
        let transport = StubHazardTransport(data: Data(json.utf8))
        let adapter = TxDOTDriveTexasAdapter(transport: transport)
        let features = try await adapter.fetch(principal: .operatorTier)
        XCTAssertEqual(features.count, 1)
        XCTAssertEqual(features[0].id, "tx-001")
        XCTAssertEqual(features[0].category, .traffic)
        XCTAssertEqual(features[0].severity, .elevated, "major maps to elevated")
        XCTAssertEqual(features[0].sourceKey, "txdot.drivetexas")
    }

    // MARK: - FIRMS

    func testFIRMSAdapterParsesGolden() async throws {
        let json = """
        [
            {
                "id": "firms-001",
                "lat": 31.5,
                "lon": -97.2,
                "confidence": 85,
                "observed_at": "2026-04-20T14:00:00Z"
            }
        ]
        """
        let transport = StubHazardTransport(data: Data(json.utf8))
        let adapter = NASAFIRMSAdapter(transport: transport)
        let features = try await adapter.fetch(principal: .operatorTier)
        XCTAssertEqual(features.count, 1)
        XCTAssertEqual(features[0].id, "firms-001")
        XCTAssertEqual(features[0].category, .fire)
        XCTAssertEqual(features[0].severity, .critical, "confidence > 80 → critical")
    }

    // MARK: - NOAA

    func testNOAAAdapterParsesGolden() async throws {
        let json = """
        {
            "features": [
                {
                    "id": "noaa-001",
                    "severity": "Severe",
                    "lat": 32.0,
                    "lon": -97.0,
                    "observed_at": "2026-04-20T15:00:00Z",
                    "headline": "Tornado Warning"
                }
            ]
        }
        """
        let transport = StubHazardTransport(data: Data(json.utf8))
        let adapter = NOAAWeatherAdapter(transport: transport)
        let features = try await adapter.fetch(principal: .operatorTier)
        XCTAssertEqual(features.count, 1)
        XCTAssertEqual(features[0].id, "noaa-001")
        XCTAssertEqual(features[0].category, .weather)
        XCTAssertEqual(features[0].severity, .elevated, "Severe maps to elevated")
    }

    // MARK: - USGS

    func testUSGSAdapterParsesGolden() async throws {
        let json = """
        {
            "features": [
                {
                    "id": "usgs-001",
                    "mag": 5.5,
                    "lat": 33.0,
                    "lon": -96.0,
                    "place": "5km N of Dallas",
                    "observed_at": "2026-04-20T16:00:00Z"
                }
            ]
        }
        """
        let transport = StubHazardTransport(data: Data(json.utf8))
        let adapter = USGSEarthquakeAdapter(transport: transport)
        let features = try await adapter.fetch(principal: .operatorTier)
        XCTAssertEqual(features.count, 1)
        XCTAssertEqual(features[0].id, "usgs-001")
        XCTAssertEqual(features[0].category, .seismic)
        XCTAssertEqual(features[0].severity, .critical, "mag >= 5.0 → critical")
    }

    // MARK: - Fail-closed

    func testAdapterFailsClosedOnMalformedPayload() async {
        let badJson = "{ not valid json }}}}"
        let transport = StubHazardTransport(data: Data(badJson.utf8))
        let adapter = TxDOTDriveTexasAdapter(transport: transport)
        do {
            _ = try await adapter.fetch(principal: .operatorTier)
            XCTFail("Should have thrown malformedPayload")
        } catch let error as OSINTAdapterError {
            if case .malformedPayload = error {
                // Correct.
            } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAdapterRejectsUnauthorizedHost() async {
        // Build a custom registry that does NOT include drivetexas.org.
        let emptyRegistry = OSINTSourceRegistry(sources: [
            OSINTSource(key: "osm.tiles", name: "OSM", category: .baseMap,
                       endpointHosts: ["tile.openstreetmap.org"],
                       license: "ODbL", attribution: "OSM",
                       homepage: "https://osm.org")
        ])
        let transport = StubHazardTransport(data: Data("[]".utf8))
        let adapter = TxDOTDriveTexasAdapter(registry: emptyRegistry, transport: transport)
        do {
            _ = try await adapter.fetch(principal: .operatorTier)
            XCTFail("Should have thrown hostNotAuthorized")
        } catch let error as OSINTAdapterError {
            if case .hostNotAuthorized = error {
                // Correct.
            } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}