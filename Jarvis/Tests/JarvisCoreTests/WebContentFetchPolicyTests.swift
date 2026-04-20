import XCTest
@testable import JarvisCore

/// SPEC-MAP Phase 1.5: Web-content fetch discipline.
///
/// Structured-API allowlisting is the right rule for known feeds; it is
/// the wrong rule for ad-hoc research reads that mirror what a human
/// operator does with a search engine. This suite locks the parallel
/// discipline: every page read must trace back to a sanctioned search
/// provider via a SearchProvenance stamp.
final class WebContentFetchPolicyTests: XCTestCase {

    private func provenance() -> SearchProvenance {
        SearchProvenance(
            providerSourceKey: "search.brave",
            query: "fire station 4 houston",
            surfacedAt: "2026-04-20T14:00:00Z"
        )
    }

    // MARK: - Provenance is mandatory

    func testMissingProvenanceDenied() {
        let policy = WebContentFetchPolicy(registry: .canonicalWithSearch)
        let url = URL(string: "https://en.wikipedia.org/wiki/Fire_station")!
        let r = policy.authorize(url: url, provenance: nil, principal: .operatorTier)
        if case .failure(.missingProvenance) = r { /* ok */ } else {
            XCTFail("no provenance ⇒ deny (audit trail required); got \(r)")
        }
    }

    func testUnknownProviderDenied() {
        let policy = WebContentFetchPolicy(registry: .canonicalWithSearch)
        let bad = SearchProvenance(
            providerSourceKey: "search.shady-scraper",
            query: "x", surfacedAt: "2026-04-20T14:00:00Z"
        )
        let url = URL(string: "https://example.com/page")!
        let r = policy.authorize(url: url, provenance: bad, principal: .operatorTier)
        if case .failure(.unknownProvider(let k)) = r {
            XCTAssertEqual(k, "search.shady-scraper")
        } else {
            XCTFail("unknown provider must be denied; got \(r)")
        }
    }

    // MARK: - Scheme + URL validation

    func testNonHTTPSchemeDenied() {
        let policy = WebContentFetchPolicy(registry: .canonicalWithSearch)
        let url = URL(string: "ftp://example.com/file")!
        let r = policy.authorize(url: url, provenance: provenance(), principal: .operatorTier)
        if case .failure(.nonHTTPScheme(let s)) = r {
            XCTAssertEqual(s, "ftp")
        } else {
            XCTFail("non-http scheme must be denied; got \(r)")
        }
    }

    // MARK: - Happy path — arbitrary public URL is allowed with provenance

    func testArbitraryPublicURLAllowedWithProvenance() {
        // The whole point of this gate: a URL that is NOT in the
        // structured-API allowlist can still be read IF it came from a
        // sanctioned search. roadsideamerica.com is explicitly on the
        // direct-API denylist — but a search-surfaced read of one of
        // its public pages IS allowed (and the fetcher will honor
        // robots.txt and rate-limits when it actually retrieves it).
        let policy = WebContentFetchPolicy(registry: .canonicalWithSearch)
        let url = URL(string: "https://www.roadsideamerica.com/story/12345")!
        let r = policy.authorize(url: url, provenance: provenance(), principal: .operatorTier)
        if case .success(let permit) = r {
            XCTAssertEqual(permit.provenance.providerSourceKey, "search.brave")
            XCTAssertEqual(permit.url, url)
        } else {
            XCTFail("search-surfaced public URL must be readable; got \(r)")
        }
    }

    // MARK: - Operator-gated provider blocks non-operator

    func testOperatorGatedProviderBlocksCompanion() {
        let policy = WebContentFetchPolicy(registry: .canonicalWithSearch)
        let url = URL(string: "https://example.com/page")!
        let r = policy.authorize(
            url: url,
            provenance: provenance(),
            principal: .companion(memberID: "melissa")
        )
        if case .failure(.operatorOnlyProvider(let k)) = r {
            XCTAssertEqual(k, "search.brave")
        } else {
            XCTFail("operator-gated provider must block companion; got \(r)")
        }
    }

    func testOperatorGatedProviderBlocksResponder() {
        let policy = WebContentFetchPolicy(registry: .canonicalWithSearch)
        let url = URL(string: "https://example.com/page")!
        let r = policy.authorize(
            url: url,
            provenance: provenance(),
            principal: .responder(role: .emtp)
        )
        if case .failure(.operatorOnlyProvider) = r { /* ok */ } else {
            XCTFail("operator-gated provider must block responder; got \(r)")
        }
    }

    // MARK: - Search providers are registered

    func testSearchProvidersInCanonicalWithSearch() {
        let r = OSINTSourceRegistry.canonicalWithSearch
        XCTAssertNotNil(r.source(forKey: "search.brave"))
        XCTAssertNotNil(r.source(forKey: "search.google-cse"))
        XCTAssertNotNil(r.source(forKey: "search.duckduckgo-ia"))
    }

    func testPrimarySearchProvidersAreOperatorGated() {
        // The API keys belong to the operator — providers that require
        // authentication must be operator-gated. The URLs returned by
        // a search can still be read by any principal (subject to
        // fetch policy), but INVOCATION of the search itself needs the
        // operator's key.
        let r = OSINTSourceRegistry.canonicalWithSearch
        XCTAssertTrue(r.source(forKey: "search.brave")?.operatorGated ?? false)
        XCTAssertTrue(r.source(forKey: "search.google-cse")?.operatorGated ?? false)
    }

    func testCanonicalWithoutSearchDoesNotLeakProviders() {
        // .canonical (no-search variant) should not include search
        // providers — contexts that don't need search shouldn't accept
        // fetches against search-provider hosts.
        let r = OSINTSourceRegistry.canonical
        XCTAssertNil(r.source(forKey: "search.brave"))
        XCTAssertNil(r.source(forKey: "search.google-cse"))
    }
}
