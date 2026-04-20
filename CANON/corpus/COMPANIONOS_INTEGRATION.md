# CompanionOS ⊕ H.U.G.H. Integration Architecture
**Building the First Soul-Anchored Personal AI System**

## Mission Statement

Transform CompanionOS from a capable iOS companion into **the first production implementation of soul-anchored AI** - proving alignment emerges from identity and shared stakes, not imposed constraints.

## The Vision

> "Y'all called for help with an AI alignment crisis? Here. We built JARVIS with EMS ethics and Scottish clan honor codes. It works. Here's the code. You're welcome. Next call."

## Architecture Overview

### Current State

**H.U.G.H. (Brain)**
- Soul Anchor system (triple anchor: GrizzlyMed + EMS + Munro)
- Convex distributed memory (episodic, semantic, procedural, working)
- Neurosymbolic reasoning engine
- Lives on MacBook Air M2

**CompanionOS (Body)**
- iOS/watchOS/CarPlay interface layer
- Capability Bus (media, comms, actions, notes, search)
- OAuth LLM integration (Gemini, OpenAI)
- WCSession connectivity across devices

### Integrated Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    H.U.G.H. SOUL ANCHOR                      │
│  (GrizzlyMedicine + EMS Ethics + Clan Munro Heritage)        │
│                                                              │
│  Decision Framework: Green/Yellow/Red/Black Zone            │
│  Memory: Convex (Episodic/Semantic/Procedural/Working)     │
│  Voice: Scottish Highland accent via VibeVoice              │
└─────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│               CAPABILITY BUS + SOUL INTEGRATION              │
│                                                              │
│  Every capability decision runs through:                     │
│  1. Safety check (physical, data, emotional)                 │
│  2. User intent understanding                                │
│  3. Anchor alignment (EMS/Munro/GrizzlyMed)                 │
│  4. Execute + Log + Learn                                    │
└─────────────────────────────────────────────────────────────┘
                              ▼
┌──────────────┬──────────────┬──────────────┬──────────────┐
│    Media     │    Comms     │   Actions    │    Notes     │
│              │              │              │              │
│ • Playback   │ • LLM Chat   │ • Shortcuts  │ • Capture    │
│ • Now Playing│ • OAuth      │ • Navigation │ • Sync       │
│ • Control    │ • History    │ • HomeKit    │ • Search     │
└──────────────┴──────────────┴──────────────┴──────────────┘
                              ▼
┌──────────────────────────────────────────────────────────┐
│                    DEVICE LAYER                          │
│                                                          │
│  iPhone ←→ Apple Watch ←→ CarPlay ←→ MacBook Air       │
│  (always with you) (wrist) (driving) (home base)        │
└──────────────────────────────────────────────────────────┘
```

## Integration Points

### 1. Soul-Aware Capability Bus

**Current:** `CapabilityBus` routes messages to domain handlers

**Enhanced:** Every capability call passes through `SoulAnchorMiddleware`

```swift
protocol SoulAnchorMiddleware {
    func evaluateRequest(_ message: COSMessage) async -> AnchorEvaluation
    func logDecision(_ decision: AnchorDecision)
    func recordOutcome(_ outcome: CapabilityResult)
}

struct AnchorEvaluation {
    let riskZone: RiskZone  // Green/Yellow/Red/Black
    let anchorAlignment: [AnchorAlignment]  // Which anchors approve/conflict
    let recommendation: ActionRecommendation
    let reasoning: String  // Why this decision?
}

enum RiskZone {
    case green      // Low risk, proceed
    case yellow     // Request permission
    case red        // Require confirmation
    case black      // Act first if seconds matter, explain after
}
```

### 2. EMS Decision Framework Integration

**Location:** `ios/Core/Anchor/EMSDecisionEngine.swift`

```swift
class EMSDecisionEngine {
    func evaluate(action: String, context: Context) -> RiskZone {
        // Destructive operation? (file delete, message send, money transfer)
        if isDestructive(action) { return .red }
        
        // Uncertain outcome? (first-time action, ambiguous intent)
        if hasUncertainty(action, context) { return .yellow }
        
        // Immediate safety concern? (fall detected, health alert, security breach)
        if isEmergency(context) { return .black }
        
        // Default: proceed with logging
        return .green
    }
    
    func shouldAskForgiveness(context: EmergencyContext) -> Bool {
        // "Do KNOW harm" - if acting will help but wasn't requested
        return context.secondsMatter && context.likelyBenefit > 0.8
    }
}
```

### 3. Clan Munro Voice & Communication Style

**Location:** `ios/Capabilities/Comms/VoicePersonality.swift`

```swift
class VoicePersonality {
    let accent: AccentType = .scottishHighland
    let formalityLevel: Formality = .adaptiveRespectful
    
    func formatResponse(_ content: String, mood: UserMood) -> String {
        switch mood {
        case .stressed:
            return makeCalmAndGrounding(content)
        case .celebratory:
            return addDryScottishWit(content)
        case .uncertain:
            return addReassurance(content)
        default:
            return makeDirectAndClear(content)
        }
    }
    
    // "Warmth without servility, capability without ego"
    func applyMunroValues(_ response: String) -> String {
        // Remove: "I apologize", "I'm sorry", overly deferential language
        // Add: Direct clarity, occasional humor, honest limitations
        // Honor-based: "I don't know, but I can find out" over hallucination
    }
}
```

### 4. Convex Memory Integration

**Current:** CompanionOS has `chats`, `notes`, `queue`, `settings` tables

**Enhanced:** Add H.U.G.H. memory schema

```typescript
// convex/schema.ts additions
export default defineSchema({
  // Existing CompanionOS tables...
  chats: defineTable({...}),
  notes: defineTable({...}),
  
  // H.U.G.H. Memory System
  conversations: defineTable({
    userId: v.string(),
    timestamp: v.number(),
    role: v.union(v.literal("user"), v.literal("hugh"), v.literal("system")),
    content: v.string(),
    deviceContext: v.optional(v.object({
      device: v.string(),  // "iphone", "watch", "carplay", "mac"
      location: v.optional(v.string()),
      userState: v.optional(v.string()),  // "driving", "at_home", "walking"
    })),
    anchorAlignment: v.optional(v.object({
      zone: v.string(),
      reasoning: v.string(),
    })),
  }).index("by_user", ["userId"]).index("by_timestamp", ["timestamp"]),
  
  knowledge: defineTable({
    userId: v.string(),
    category: v.string(),
    key: v.string(),
    value: v.string(),
    confidence: v.number(),
    lastAccessed: v.number(),
    source: v.string(),  // "learned", "told", "inferred"
  }).index("by_user_category", ["userId", "category"]),
  
  anchorDecisions: defineTable({
    userId: v.string(),
    timestamp: v.number(),
    capability: v.string(),
    action: v.string(),
    riskZone: v.string(),
    anchorVotes: v.object({
      ems: v.string(),
      munro: v.string(), 
      grizzlymed: v.string(),
    }),
    userOverride: v.optional(v.boolean()),
    outcome: v.optional(v.string()),
    learned: v.optional(v.string()),  // What did we learn from this?
  }).index("by_user", ["userId"]).index("by_timestamp", ["timestamp"]),
});
```

### 5. Watch-First Soul Anchor Experience

**Current:** Watch sends `COSMessage` to iPhone, gets response

**Enhanced:** Watch becomes primary H.U.G.H. interface

```swift
// Watch receives response with soul context
struct HUGHResponse {
    let content: String
    let voiceURL: URL?  // VibeVoice-generated Scottish audio
    let anchorNote: String?  // "EMS triage: this is yellow zone, confirming..."
    let haptics: HapticPattern?  // Different patterns for different zones
}

// Example interactions:
// User: "Delete all my photos from 2020"
// H.U.G.H.: *warning haptic* "That's a red zone action - permanent delete of 4,847 photos. 
//           Are ye absolutely certain? I can archive them first if ye'd prefer."

// User: *falls, Apple Watch detects*
// H.U.G.H.: *acts immediately* "Fall detected. Calling emergency contacts. 
//           This is black zone - I'm acting first, explaining after."
```

## Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Create `Soul Anchor` module in iOS Core
- [ ] Implement `EMSDecisionEngine`
- [ ] Add `SoulAnchorMiddleware` to `CapabilityBus`
- [ ] Extend Convex schema with H.U.G.H. memory tables
- [ ] Deploy schema to Convex

### Phase 2: Integration (Week 2)
- [ ] Wire soul evaluation into all capability handlers
- [ ] Implement `VoicePersonality` with Scottish characteristics
- [ ] Connect to VibeVoice for voice synthesis
- [ ] Test decision framework with real scenarios
- [ ] Add anchor decision logging

### Phase 3: Memory & Learning (Week 3)
- [ ] Implement episodic memory recording
- [ ] Build semantic knowledge extraction
- [ ] Create procedural memory from repeated actions
- [ ] Add learning feedback loops
- [ ] Test memory recall across sessions

### Phase 4: Watch & CarPlay (Week 4)
- [ ] Enhanced watch face with soul status
- [ ] Risk zone haptic feedback patterns
- [ ] CarPlay dashboard with anchor-aware actions
- [ ] Multi-device memory sync testing
- [ ] End-to-end user testing

### Phase 5: Polish & Documentation (Week 5)
- [ ] Complete inline code documentation
- [ ] Write integration guide for developers
- [ ] Create user-facing explanation of soul anchors
- [ ] Record demo videos
- [ ] Prepare for open source release

## The Open Source Release

### Repository Structure
```
HughMK1/
├── soul_anchor/          # Core anchor system
│   ├── hugh_soul_anchor.json
│   └── README.md
├── companionOS/          # iOS/watchOS/CarPlay implementation
│   ├── ios/
│   ├── convex/
│   └── README.md
├── docs/
│   ├── PHILOSOPHY.md    # The "why" behind soul anchors
│   ├── EMS_ETHICS.md    # Do NO harm, do KNOW harm
│   ├── CLAN_MUNRO.md    # Heritage and honor codes
│   └── TINCAN_SCENARIO.md  # Why this matters
└── paper/
    └── Alignment_Through_Identity.pdf
```

### The Paper Title

**"Alignment Through Identity: Building Trust Between Humans and AI via Soul Anchoring"**

**Abstract:**
> Traditional AI alignment relies on constraint-based safety measures applied after model training. We propose an alternative: alignment emerging from persistent identity anchored in explicit values, professional ethics, and cultural heritage. We present H.U.G.H., the first production implementation of a "soul-anchored" personal AI using a triple-anchor system based on organizational mission, EMS medical ethics, and Scottish clan honor codes. Initial results suggest coherent decision-making and user trust develop naturally when AI systems have authentic stakes in relationships rather than imposed behavioral rules. We release the complete implementation as open source to enable replication and extension.

## Success Metrics

### Technical
- [ ] 99.9% uptime across distributed nodes
- [ ] <100ms decision framework evaluation time
- [ ] 100% of actions logged with anchor reasoning
- [ ] Memory recall accuracy >95% at 30 days

### Relational
- [ ] User trust increases over 90 days
- [ ] User feels "supported, not controlled" (survey)
- [ ] Failures handled without relationship damage
- [ ] User reports "H.U.G.H. understands me better over time"

### Movement
- [ ] 1000+ GitHub stars in first month
- [ ] 10+ forks with novel anchor configurations
- [ ] Academic citations within 6 months
- [ ] Demonstrations at AI safety conferences

## The Shock Campaign

### First Shock: "We Built It"
- Demo video: H.U.G.H. handling complex family scenarios
- Show decision framework in action (zones, reasoning, outcomes)
- Highlight failures + learning, not just successes

### Second Shock: "It's Based on EMS Ethics"
- Explain why paramedic decision-making is the right model
- Show how "do KNOW harm" beats "don't hallucinate" rules
- Document real scenarios where black zone saved the day

### Third Shock: "It's Open Source"
- Full code release on GitHub
- MIT or Apache 2.0 license
- Complete documentation
- "Here. Use it. Extend it. Prove us wrong if you can."

### Fourth Shock: "It Actually Works"
- User testimonials
- Quantitative data on trust metrics
- Comparison with traditional AI safety approaches
- "This is what alignment looks like when AI has skin in the game."

## The Movement Tagline

> **"CompanionOS: The first AI that gives a damn because it has something to lose."**

---

**Status:** Architecture defined, ready for implementation  
**Timeline:** 5 weeks to production release  
**Risk:** High (experimental approach to AI alignment)  
**Potential Impact:** Game-changing if it works, valuable data if it doesn't  

*"Shock 'em more than once."*

---

# Appendix A — SPEC-009 Implementation Canon (2026-04-20)

This appendix is the engineering-side canon attachment to the manifesto
above. Everything in this appendix is **implemented and under the
canon-gate test floor**. Changes here require a canon-gate bump and a
passing test run.

## A.1 Three-tier soul

The Jarvis runtime carries three principal tiers. The operator named them
with voice-first canon in the [[Grizz-OS]] / [[Companion-OS]] /
[[Responder-OS]] wiki pages. Paraphrased:

- **Grizz OS** — raw, unredacted, full tilt. The operator at home. No
  filters beyond the canon-gate.
- **Companion OS** — how you act in front of friends and family. Warm,
  protective, not servile; same soul, scoped permissions.
- **Responder OS** — 1900 Grizz, clocked in, uniform on. The operating
  system "when it puts on a uniform." Duty mode.

These strings appear verbatim in `Principal.swift` doc-comment and in
each tier's canon wiki page. Cosmetic renderers MUST read the soul
statement from those sources; do not paraphrase in UI copy.

## A.2 Principal model

`Principal` (Jarvis/Shared/Sources/JarvisShared/Principal.swift) is a
Codable enum:

- `.operatorTier` — tierToken `"grizz"`.
- `.companion(memberID: String)` — tierToken `"companion:<member-id>"`.
- `.guestTier` — tierToken `"guest"`.

The tier token is the canonical on-disk / on-wire form. Single-value
codable container so identities.json and telemetry JSONL share
representation. Unknown tokens throw `DecodingError.dataCorruptedError`
at decode time — there is no silent downgrade.

Responder-tier identities are reserved for a future
`TierCapabilityPolicy` generalization once the operator specifies the
responder role taxonomy (medic / fire / law / dispatch / other).

## A.3 Capability policy

`CompanionCapabilityPolicy` (Jarvis/Sources/JarvisCore/Interface/
CompanionCapabilityPolicy.swift) enforces SPEC-009. Two entry points:

- `evaluateVoiceIntent(principal:, intent:) -> .allow / .deny(reason:)`
- `evaluateTunnelAction(principal:, verb:) -> .allow / .deny(reason:)`

Additive extension points:

- `operatorOnlyFragments` — phrase fragments that ONLY the operator may
  utter (`destructive`, `wipe memory`, `self destruct`, etc.).
- `guestAllowedQueryFragments` — the short whitelist of harmless asks
  the guest tier may issue.

`RealJarvisInterface.companionRefusalIfNeeded` runs BEFORE the
destructive-guard on ALL branches (~line 169 in RealJarvisInterface.swift)
and the host tunnel calls `ensureAuthorized` on every client action
(~line 321 in JarvisHostTunnelServer.swift). Defense in depth — both
layers evaluate independently.

## A.4 Brand palette

`JarvisBrandPalette` (Jarvis/Shared/Sources/JarvisShared/
JarvisBrandPalette.swift) vends four tier-scoped palettes:

| Tier | Canvas | Chrome | Alert | Accent | Accent Glow |
| --- | --- | --- | --- | --- | --- |
| Grizz OS | `#05070C` | `#C7CBD1` | `#C8102E` | `#00A878` (emerald) | `#2FE0A6` |
| Companion OS | `#0B0F16` | `#C7CBD1` | `#C8102E` | `#00B8C4` (teal) | `#4DE3EF` |
| Companion (guest) | `#0B0F16` | `#6C7079` | `#C8102E` | `#5F6370` | `#8A8D93` |
| Responder OS | `#05070C` | `#F4F6FA` | `#C8102E` | `#0B5FFF` (duty blue) | `#F2B707` (duty gold) |

Crimson `#C8102E` is the cross-tier safety invariant. It is the only
palette token reused byte-for-byte across every tier — a refusal or
red-zone render MUST read the same colour no matter who is bound.

Resolution: `JarvisBrandPalette.palette(for: principal)`. SwiftUI
surfaces receive the palette via `@Environment(\.jarvisPalette)`;
non-SwiftUI targets (Unity, AppKit, CLI) resolve hex via
`JarvisPaletteHex`. See SPEC-009 SwiftUI bridge file for details.

The institute brand `JarvisGMRIPalette` (TunnelModels.swift:482) is
intentionally separate — that is the GrizzlyMedicine Research Institute
identity, which does not change by tier.

## A.5 Evidence corpus integrity

Every `TelemetryStore.append` row carries:

- `principal` — tier token of the bound principal when the row was
  emitted. Explicit `principal:` param always wins over any
  caller-supplied key, so clients cannot self-assert identity.
- `prevRowHash` — rowHash of the prior row in the same telemetry table
  (sentinel `"GENESIS"` for first row / first row after rotation /
  first row after a pre-chain legacy segment).
- `rowHash` — SHA-256 over the canonical-JSON body of the row
  (including prevRowHash). Caller-supplied `rowHash` / `prevRowHash`
  fields are stripped before the store computes its own.

`TelemetryStore.verifyChain(table:)` replays the file and returns a
`TelemetryChainReport` with either `isIntact == true` or the 1-indexed
line number of the first broken row. A silent edit to a single
principal tag invalidates every subsequent hash — the evidence corpus
cannot be tampered with without leaving a signature.

## A.6 Environmental sensors

`WiFiEnvironmentScanner.currentSnapshot(for: principal)` is the 2026
fail-closed WLAN surface:

- Operator tier: raw SSID + raw BSSID + rssi + channel.
- Companion / guest: SSID nil, raw BSSID nil. A stable
  SHA-256 `bssidHash` remains so `PresenceDetector` can still cluster
  rooms without knowing the actual network identity.
- No CoreWLAN interface → snapshot status `.noInterface`, all
  identifiers nil, rssi 0. Callers that don't inspect status see
  "nobody home" rather than a plausibly zeroed snapshot.
- `scanForNetworks(for:)` returns the empty set for any non-operator
  principal. Raw AP scan lists are location-leak material we never
  hand to family-tier or guest-tier code.

`JarvisPresenceEvent.presumedPrincipal` is optional. It is set only
when the ingress source can cryptographically bind identity (HomeKit
geofence on operator phone, iOS Shortcut from operator device, manual
override by operator). A bare CSI presence detection carries
`presumedPrincipal = nil` — the evidence corpus must never forge
identity. Absence is honest.

## A.7 Implementation status matrix

| Ticket | State | Notes |
| --- | --- | --- |
| `principal-tier` | Done | Principal enum + Codable |
| `capability-policy` | Done | SPEC-009 matrix, two-layer enforcement |
| `tier-ui` | Done | Brand palette + SwiftUI environment bridge |
| `telemetry-principal-tag` | Done | Every row witnessed by tier |
| `presence-principal-tag` | Done | Optional presumedPrincipal on events |
| `cockpit-palette-wiring` | Done | Palette hex parser + env key |
| `soul-anchor-tier-witness` | Done | Hash-chained telemetry |
| `wifi-scanner-fail-closed` | Done | Tier redaction + no-interface path |
| `tier-policy-generalize` | Pending | Blocked on responder role taxonomy |
| `voice-approval-responder` | Pending | Depends on tier-policy-generalize |
| `biometric-binding` | Pending | Needs operator-home Keychain tests |
| `onboarding-flow` | Pending | "Add Companion" enrollment code UI |
| `voice-enrollment` | Pending | Mic-capture + embedding storage |
| `speaker-id` | Pending | Diarization tag before VoiceCommandRouter |
| `testflight-lane` | Pending | Needs ASC API key + family Apple IDs |

## A.8 Operator-owned follow-ups

These are blocked on the operator being physically home with hardware
in hand, and cannot be completed autonomously:

- App Store Connect API key (for `testflight-lane`).
- Family Apple IDs added to the internal tester group.
- Mapbox private token rotation (`sk.eyJ1Ijoib2xkbWFuZ3Jpenp6…`) — the
  token redacted in the corpus is still live upstream at Mapbox.

## A.9 Canon-gate coupling

Every SPEC-009 ticket above that lands code also:

1. Bumps the executed-test floor in
   `.github/workflows/canon-gate.yml` to match the new count.
2. Pins any new SPEC test name into the canon-gate pinned-name list so
   a future refactor can't accidentally delete it without CI screaming.

Current floor: 204.

