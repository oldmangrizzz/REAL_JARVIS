# Navigation Module (NAV-001)

**Owner:** GLM (engine-core). Qwen (UX-001) consumes public protocols; do not modify contract types without surfacing in Open Questions.

**Status:** Shipped in NAV-001 single-pass. Engine-core complete. Runtime wiring is a follow-up ticket after surfaces (Qwen UX-001) land.

---

## What It Is

The Navigation module provides tile-based map rendering, deterministic shortest-path routing with tier-gated profiles, OSINT hazard overlay fusion, and scene briefing — the engine side of Real Jarvis' universal navigation stack. No UI code; Qwen owns surfaces.

## Public Protocols (frozen — Qwen consumes these)

| Protocol/Struct | Purpose | Phase |
|-----------------|---------|-------|
| `MapTileProvider` | Tile source abstraction with health probing | A |
| `TileProviderOrchestrator` | Fail-over orchestration with audit logging | A |
| `RoutingProfile` | Tier-gated edge weighting | B/C |
| `RoadGraph` | Graph abstraction for routing (tests inject `InMemoryRoadGraph`) | B |
| `UniversalRouter` | Deterministic Dijkstra router | B |
| `HazardOverlayFeature` | Situational-awareness hazard data point | D |
| `HazardAdapter` | OSINT source adapter protocol | D |
| `ScenePreSearch` | Tier-gated hazard fusion → `SceneBriefing` | E |
| `SceneBriefing` | Fused snapshot for surface rendering | E |

## Tier Gating

Tier access enters through two points only:

1. **`RoutingProfile.principalScope`** — exhaustive `Set<PrincipalCategory>` allow-lists. No default fallthrough.
2. **`DefaultScenePreSearch.allowedSourceKeys(for:)`** — per-category adapter filtering.

### ScenePreSearch Tier Policy

| Category | Hazard Layers |
|----------|---------------|
| `.grizz` (operator) | traffic + fire + weather + seismic (full fusion) |
| `.companion` | traffic + fire + weather (seismic excluded — lower relevance for family routing) |
| `.responder` | traffic + fire + weather + seismic (EMS-relevant situational awareness) |
| `.guest` | empty briefing (no hazard data) |

## OSINT Sources Used

All adapters route through `OSINTFetchGuard.authorize(url:principal:)` — fail-closed on unlisted hosts.

| Adapter | Registry Key | Source |
|---------|-------------|--------|
| `TxDOTDriveTexasAdapter` | `txdot.drivetexas` | TxDOT DriveTexas (already in canonical) |
| `NASAFIRMSAdapter` | `firms.nasa` | NASA FIRMS (already in canonical) |
| `NOAAWeatherAdapter` | `noaa.nws` | NOAA NWS (already in canonical) |
| `USGSEarthquakeAdapter` | `usgs.quake` | USGS Earthquake Hazards (already in canonical) |

No registry additions were needed — all four were already present in `OSINTSourceRegistry.canonical`.

## Parallel-Track Notes

- **Qwen (UX-001)** owns all surfaces: `NavigationCockpitView`, CarPlay, PWA, Unity. Consumes `MapTileProvider`, `HazardOverlayFeature`, `SceneBriefing`, `RoutingProfile` as opaque types.
- **DeepSeek (VOICE-001)** owns F5-TTS swap. Unrelated to this module.
- **Do not wire into `JarvisRuntime`** in this PR. The engine stands alone; runtime wiring is a downstream ticket.

## Test Matrix

| Test Suite | Count | Hermetic |
|-----------|-------|----------|
| `MapTileProviderTests` | 10 | Yes — stub transport |
| `UniversalRouterTests` | 6 | Yes — in-memory graph |
| `RoutingProfilesTests` | 4 | Yes — unit |
| `HazardAdaptersTests` | 6 | Yes — stub transport + fixtures |
| `ScenePreSearchTests` | 4 | Yes — stub adapters |

## EMS Profile — Operator-Teachable Parameters

`EMSPreferredProfile.taughtParameters` is `[String: Double]`, in-memory only. Persistence is a downstream ticket. Comment in code: `// CANON: operator-teachable; persistence ticket pending`.

## Hazard Repulsion

The `EMSPreferredProfile` repels edges with the `affectedByHazard` attribute matching a hazard ID in the active context. Production implementations would use spatial proximity (lat/lon distance between edge geometry and hazard geometry). The current `InMemoryRoadGraph` test fixture uses explicit attribute marking for deterministic testing.