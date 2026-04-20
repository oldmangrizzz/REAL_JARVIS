import XCTest
@testable import JarvisCore

/// SPEC-MAP Phase 1: OSINT source registry discipline.
///
/// The registry is the canon gate for every external data fetch backing
/// map layers, traffic overlays, and situational-awareness feeds.
/// Doctrine: open sources only — gray, not black. A fetch to an
/// unlisted host must fail closed; operator-gated sources must reject
/// non-operator principals.
final class OSINTSourceRegistryTests: XCTestCase {

    func testCanonicalRegistryIncludesCoreOpenSources() {
        let r = OSINTSourceRegistry.canonical
        // Must carry the feeds the operator explicitly endorsed.
        XCTAssertNotNil(r.source(forKey: "osm.tiles"))       // fallback map
        XCTAssertNotNil(r.source(forKey: "mapbox.tiles"))    // primary map
        XCTAssertNotNil(r.source(forKey: "txdot.drivetexas")) // Texas traffic
        XCTAssertNotNil(r.source(forKey: "firms.nasa"))      // fire awareness
        XCTAssertNotNil(r.source(forKey: "noaa.nws"))        // weather
    }

    func testEveryCanonicalSourceHasLicenseAndAttribution() {
        for (_, src) in OSINTSourceRegistry.canonical.sources {
            XCTAssertFalse(src.license.isEmpty, "\(src.key) missing license")
            XCTAssertFalse(src.attribution.isEmpty, "\(src.key) missing attribution")
            XCTAssertFalse(src.homepage.isEmpty, "\(src.key) missing homepage (for TOS verification)")
            XCTAssertFalse(src.endpointHosts.isEmpty, "\(src.key) has no endpoint hosts")
        }
    }

    func testHostLookupMatchesDirectAndSubdomain() {
        let r = OSINTSourceRegistry.canonical
        XCTAssertEqual(r.source(forHost: "api.mapbox.com")?.key, "mapbox.tiles")
        // Subdomain suffix match — tile.openstreetmap.org is registered;
        // a.tile.openstreetmap.org must resolve to the same source.
        XCTAssertEqual(r.source(forHost: "a.tile.openstreetmap.org")?.key, "osm.tiles")
        XCTAssertNil(r.source(forHost: "evil-tile-mirror.example.com"))
    }

    // MARK: - Fetch guard

    func testGuardDeniesUnlistedHost() {
        let guardian = OSINTFetchGuard()
        let url = URL(string: "https://not-in-registry.example.com/x.json")!
        let result = guardian.authorize(url: url, principal: .operatorTier)
        switch result {
        case .failure(.unlistedHost(let h)):
            XCTAssertEqual(h, "not-in-registry.example.com")
        default:
            XCTFail("unlisted host must be denied (gray-not-black doctrine); got \(result)")
        }
    }

    func testGuardAllowsListedHostForAnyTier() {
        let guardian = OSINTFetchGuard()
        let url = URL(string: "https://api.weather.gov/alerts/active")!
        let principals: [Principal] = [
            .operatorTier,
            .companion(memberID: "melissa"),
            .guestTier,
            .responder(role: .emt)
        ]
        for p in principals {
            let r = guardian.authorize(url: url, principal: p)
            if case .failure = r {
                XCTFail("NOAA public weather must be open to \(p); got \(r)")
            }
        }
    }

    func testGuardDeniesInvalidURL() {
        let guardian = OSINTFetchGuard()
        // URL without host (file scheme) must be rejected.
        let url = URL(string: "file:///tmp/x")!
        let r = guardian.authorize(url: url, principal: .operatorTier)
        if case .failure(.invalidURL) = r { /* ok */ }
        else if case .failure(.unlistedHost) = r { /* also acceptable */ }
        else { XCTFail("invalid/no-host URL must be denied; got \(r)") }
    }

    func testOperatorGatedSourceRejectsNonOperator() {
        // Build a custom registry with an operator-gated entry to verify
        // the gate works. None of the canonical sources are gated today
        // (they're all public), but the mechanism must exist for the
        // moment we add any scoped API key.
        let gated = OSINTSource(
            key: "test.gated", name: "Gated Test", category: .imagery,
            endpointHosts: ["gated.example.com"], license: "test",
            attribution: "test", homepage: "https://gated.example.com",
            operatorGated: true
        )
        let guardian = OSINTFetchGuard(registry: OSINTSourceRegistry(sources: [gated]))
        let url = URL(string: "https://gated.example.com/v1/thing")!

        let companion = guardian.authorize(url: url, principal: .companion(memberID: "m"))
        if case .failure(.operatorOnly(let k)) = companion {
            XCTAssertEqual(k, "test.gated")
        } else {
            XCTFail("companion must be denied operator-gated source; got \(companion)")
        }

        let responder = guardian.authorize(url: url, principal: .responder(role: .emtp))
        if case .failure(.operatorOnly) = responder { /* ok */ } else {
            XCTFail("responder must be denied operator-gated source; got \(responder)")
        }

        let op = guardian.authorize(url: url, principal: .operatorTier)
        if case .success = op { /* ok */ } else {
            XCTFail("operator must pass operator-gated source; got \(op)")
        }
    }

    func testAttributionsAreStableSorted() {
        let a = OSINTSourceRegistry.canonical.attributions
        XCTAssertEqual(a, a.sorted())
        XCTAssertFalse(a.isEmpty)
    }
}
