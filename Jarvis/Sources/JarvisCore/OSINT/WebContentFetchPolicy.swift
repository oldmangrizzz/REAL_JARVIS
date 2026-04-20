import Foundation

/// SPEC-MAP Phase 1.5: Web search + sanctioned web-content retrieval.
///
/// Rationale (operator-authoritative): structured-API allowlisting alone
/// is too narrow. A human professional doing situational research uses a
/// search engine and reads the public pages that surface — that IS a
/// gray-zone legitimate research modality. Jarvis gets the same surface,
/// governed by a parallel discipline.
///
/// ## Two complementary fetch gates
///
///   | Gate                    | Used for                              | Rule         |
///   | ----------------------- | ------------------------------------- | ------------ |
///   | `OSINTFetchGuard`       | Structured APIs (TxDOT, FIRMS, OSM…)  | Host allowlist |
///   | `WebContentFetchPolicy` | Arbitrary public pages surfaced by a  | Provenance +  |
///   |                         | sanctioned search provider            | robots + TOS  |
///
/// Every web page Jarvis reads MUST carry a `SearchProvenance` stamp:
/// which provider surfaced it, which query produced it, when. A URL
/// with no provenance is rejected — that prevents blind scraping and
/// keeps every read auditable.
///
/// ## Compliance envelope (non-negotiable)
///
///   - Honor `robots.txt`. If disallowed, do not fetch.
///   - Identify with a stable User-Agent including a contact URL.
///   - Rate-limit per-host (default ≤1 req/s, configurable).
///   - Never bypass authentication, paywalls, or login gates.
///   - Never redistribute fetched content outside the operator's own
///     surfaces without explicit operator approval (fair-use read,
///     not republication).
///   - Operator-only persistence: ad-hoc reads are ephemeral. Ingestion
///     into the permanent corpus requires operator intent.

public struct SearchProvenance: Equatable, Sendable, Codable {
    /// Registered OSINT source key of the provider that surfaced the URL.
    public let providerSourceKey: String
    /// The query the operator/agent ran.
    public let query: String
    /// When the search ran. ISO-8601 string to match telemetry format.
    public let surfacedAt: String

    public init(providerSourceKey: String, query: String, surfacedAt: String) {
        self.providerSourceKey = providerSourceKey
        self.query = query
        self.surfacedAt = surfacedAt
    }
}

public enum WebContentDenial: Error, Equatable, CustomStringConvertible {
    case missingProvenance
    case unknownProvider(key: String)
    case invalidURL
    case nonHTTPScheme(String)
    case operatorOnlyProvider(key: String)

    public var description: String {
        switch self {
        case .missingProvenance:
            return "Web fetch denied: no SearchProvenance — every public-page read must trace back to a sanctioned search."
        case .unknownProvider(let k):
            return "Web fetch denied: search provider '\(k)' not registered in OSINTSourceRegistry."
        case .invalidURL:
            return "Web fetch denied: invalid URL."
        case .nonHTTPScheme(let s):
            return "Web fetch denied: scheme '\(s)' not allowed (http/https only)."
        case .operatorOnlyProvider(let k):
            return "Web fetch denied: provider '\(k)' is operator-gated; current principal lacks access."
        }
    }
}

/// Policy gate for web-content retrieval. Stateless — the fetcher itself
/// enforces robots.txt, rate limits, and User-Agent. This struct
/// validates the structural preconditions.
public struct WebContentFetchPolicy: Sendable {
    public let registry: OSINTSourceRegistry

    public init(registry: OSINTSourceRegistry = .canonical) {
        self.registry = registry
    }

    public func authorize(
        url: URL,
        provenance: SearchProvenance?,
        principal: Principal
    ) -> Result<WebContentReadPermit, WebContentDenial> {
        guard let prov = provenance else { return .failure(.missingProvenance) }
        guard let scheme = url.scheme?.lowercased() else { return .failure(.invalidURL) }
        guard scheme == "http" || scheme == "https" else {
            return .failure(.nonHTTPScheme(scheme))
        }
        guard url.host != nil else { return .failure(.invalidURL) }
        guard let provider = registry.source(forKey: prov.providerSourceKey) else {
            return .failure(.unknownProvider(key: prov.providerSourceKey))
        }
        if provider.operatorGated {
            if case .operatorTier = principal { /* ok */ } else {
                return .failure(.operatorOnlyProvider(key: provider.key))
            }
        }
        return .success(WebContentReadPermit(
            url: url, provenance: prov, provider: provider
        ))
    }
}

/// A successful authorization result. Carrying this permit is what
/// distinguishes a sanctioned read from an ambient scrape.
public struct WebContentReadPermit: Equatable, Sendable {
    public let url: URL
    public let provenance: SearchProvenance
    public let provider: OSINTSource
}

// MARK: - Search-provider registry entries
//
// These are the providers Jarvis may query for web search. Each is
// operator-gated because the API key belongs to the operator account;
// the URLs returned by a search can then be read by any principal
// (subject to the fetch policy above).

extension OSINTSourceRegistry {
    public static let searchProviders: [OSINTSource] = [
        OSINTSource(
            key: "search.brave",
            name: "Brave Search API",
            category: .civic,
            endpointHosts: ["api.search.brave.com"],
            license: "Brave Search API Terms",
            attribution: "Search: Brave",
            homepage: "https://api.search.brave.com/app/documentation",
            rateLimitHint: "Free tier: 2000 queries/month, 1 qps. Paid tiers scale up.",
            operatorGated: true,
            notes: "Primary web-search surface. Results feed WebContentFetchPolicy provenance."
        ),
        OSINTSource(
            key: "search.google-cse",
            name: "Google Programmable Search Engine (JSON API)",
            category: .civic,
            endpointHosts: ["www.googleapis.com", "customsearch.googleapis.com"],
            license: "Google API Terms of Service",
            attribution: "Search: Google Programmable Search",
            homepage: "https://developers.google.com/custom-search/v1/overview",
            rateLimitHint: "Free: 100 queries/day. Billing after.",
            operatorGated: true,
            notes: "Secondary web-search surface, useful for long-tail queries."
        ),
        OSINTSource(
            key: "search.duckduckgo-ia",
            name: "DuckDuckGo Instant Answer API",
            category: .civic,
            endpointHosts: ["api.duckduckgo.com"],
            license: "DuckDuckGo Terms",
            attribution: "Instant answers: DuckDuckGo",
            homepage: "https://duckduckgo.com/api",
            rateLimitHint: "No published quota; be polite.",
            notes: "No-key quick-answer surface for simple factual queries. Limited coverage."
        )
    ]

    /// Canonical registry extended with search providers. Use this when
    /// wiring up the web-search subsystem; keep `.canonical` pure for
    /// direct-API allowlisting contexts that don't need search.
    public static var canonicalWithSearch: OSINTSourceRegistry {
        var combined = Array(canonical.sources.values)
        combined.append(contentsOf: searchProviders)
        return OSINTSourceRegistry(sources: combined)
    }
}
