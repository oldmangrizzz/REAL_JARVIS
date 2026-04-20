# OSINT

**Path:** `Jarvis/Sources/JarvisCore/OSINT/`
**Files:**
- `OSINTSourceRegistry.swift` — pinned catalog of sanctioned data sources.
- `WebContentFetchPolicy.swift` — gate for arbitrary public-web reads surfaced by a search provider.

## Doctrine (operator-authoritative)
> **Open sources only — gray, not black.**
> Public feeds with full attribution and license compliance. No
> scraped TOS-walled content, no dark-web feeds, no unauthorized scopes.

Every network fetch that backs a map layer, OSINT lookup, traffic
overlay, or situational-awareness feed MUST resolve through one of the
two gates below. Anything else is denied fail-closed.

## Two complementary fetch gates

| Gate                    | Used for                                     | Rule                         |
| ----------------------- | -------------------------------------------- | ---------------------------- |
| `OSINTFetchGuard`       | Structured APIs (TxDOT, FIRMS, OSM, …)       | Host allowlist in registry   |
| `WebContentFetchPolicy` | Arbitrary public pages from a search result  | Provenance + robots.txt + TOS |

## Key types

### `OSINTSource` / `OSINTSourceRegistry`
A pinned record per source: `key`, `name`, `category`, `endpointHosts`,
`license`, `attribution`, `homepage`, `rateLimitHint`, `operatorGated`,
`notes`. Registry exposes lookup by key, by category, and by host —
the host path is what `OSINTFetchGuard.authorize(url:)` calls.

`OSINTCategory`: `baseMap`, `traffic`, `cameras`, `hazards`, `weather`,
`imagery`, `elevation`, `airspace`, `seismic`, `civic`, and friends.

### `WebContentFetchPolicy` + `SearchProvenance`
Every arbitrary-web read must carry a `SearchProvenance` stamp (which
provider, which query, when). URLs with no provenance are rejected —
prevents blind scraping, keeps every read auditable.

**Compliance envelope (non-negotiable):**
- Honor `robots.txt`. If disallowed, do not fetch.
- Identify with a stable User-Agent including a contact URL.
- Rate-limit per-host (default ≤ 1 req/s, configurable).
- Never bypass authentication, paywalls, or login gates.
- Never redistribute fetched content outside the operator's own storage.

## Invariants
- The registry is **tier-agnostic** — the same catalog backs operator,
  companion, and responder surfaces. Per-source `operatorGated` exists
  for future scoped API keys but is off by default.
- Any fetcher that can make an outbound HTTP call MUST route through
  one of the two gates. There is no "just this once" direct-fetch path.
- Attribution text travels with the data into the UI layer — license
  compliance is not optional.

## Related
- [[codebase/modules/Credentials]] — `MapboxCredentials` is the primary
  credential class consumed by `baseMap` sources.
- `Tests/JarvisCoreTests/OSINTSourceRegistryTests.swift` — registry + authorization.
- [[concepts/Companion-OS-Tier]] — operator/companion/responder principal model.
- GLM `NAV-001-EXECUTE-PR1` — upcoming consumer of the registry via
  `HazardOverlayFeature` adapters in PR4.
