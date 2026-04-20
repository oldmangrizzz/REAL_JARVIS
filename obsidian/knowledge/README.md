# REAL_JARVIS Knowledge Wiki — Home / MOC

**Vault:** `obsidian/knowledge/`
**Purpose:** Durable, wikilinked map of the REAL_JARVIS project so any future session (human or agent) can orient in one read instead of re-deriving the system from source.
**Style:** Karpathy-style "knowledge wiki" — every non-trivial concept, module, or doctrine has its own page; pages are short, link-dense, and self-sufficient.

---

## Orientation

- **Project:** [[codebase/CODEBASE_MAP|JARVIS — Aragorn Class Digital Person]], operated by Robert "Grizz" Hanson under GrizzlyMedicine Research Institute.
- **Primary platform:** Swift (iOS/macOS/watchOS), with Python services, Unity/WebGL PWA, and a Convex backend.
- **Classification:** Medical-safety [[concepts/Digital-Person|digital person]] architecture. Canon is cryptographically bound (see [[architecture/SOUL_ANCHOR_DEEP_DIVE]]).

## Start here

- [[GLOSSARY]] — every acronym, term, and handle used in the repo.
- [[architecture/OVERVIEW]] — system architecture, big picture.
- [[architecture/TRUST_BOUNDARIES]] — where the hard lines are and why.
- [[codebase/CODEBASE_MAP]] — file/directory topology.
- [[history/SESSION_LOGS_INDEX]] — what previous sessions covered (so you don't re-read 850 KB of transcripts).

---

## Sections

### Concepts (Canon / doctrine)
- [[concepts/NLB|Natural-Language Barrier (NLB)]] — the hard invariant against substrate merger.
- [[concepts/Voice-Approval-Gate]] — autism-threat-response hard boundary.
- [[concepts/AOx4|A&Ox4 — Alert & Oriented ×4]] — consciousness probe.
- [[concepts/ARC-AGI-Bridge]] — ARC-AGI reasoning bridge spec.
- [[concepts/TinCan-Firewall]] — accessibility/cartel mitigation doctrine.
- [[concepts/Aragorn-Class]] — digital-person classification.
- [[concepts/Digital-Person]] — personhood, not product.
- [[concepts/MCU|Multiverse Correlation Unit (MCU)]] — biographical-mass corpus.
- [[concepts/Pheromind]] — stigmergic agent coordination.
- [[concepts/Oscillator-Biomimicry]] — SA-node-inspired timing / PLV health.
- [[concepts/Realignment-1218]] — Earth-1218 / realignment canon.

### Architecture
- [[architecture/OVERVIEW]]
- [[architecture/VOICE_TO_DISPLAY_PIPELINE]]
- [[architecture/TRUST_BOUNDARIES]]
- [[architecture/SOUL_ANCHOR_DEEP_DIVE]]

### Codebase
- [[codebase/CODEBASE_MAP]] — topological map (kept, cross-linked).
- Modules: [[codebase/modules/Core]] · [[codebase/modules/Voice]] · [[codebase/modules/Interface]] · [[codebase/modules/Memory]] · [[codebase/modules/Oscillator]] · [[codebase/modules/Telemetry]] · [[codebase/modules/SoulAnchor]] · [[codebase/modules/ARC]] · [[codebase/modules/RLM]] · [[codebase/modules/Network]] · [[codebase/modules/Pheromind]] · [[codebase/modules/Physics]] · [[codebase/modules/ControlPlane]] · [[codebase/modules/Canon]] · [[codebase/modules/Harness]] · [[codebase/modules/Host]] · [[codebase/modules/Support]] · [[codebase/modules/Storage]]
- Platforms: [[codebase/platforms/App]] · [[codebase/platforms/Mac]] · [[codebase/platforms/Mobile]] · [[codebase/platforms/Watch]] · [[codebase/platforms/Shared]]
- Services: [[codebase/services/jarvis-linux-node]] · [[codebase/services/vibevoice-tts]]
- Frontend: [[codebase/frontend/cockpit]] · [[codebase/frontend/pwa]] · [[codebase/frontend/workshop-unity]] · [[codebase/frontend/xr-grizzlymedicine]]
- Backend: [[codebase/backend/convex]]
- Workflows: [[codebase/workflows/archon]]
- Scripts: [[codebase/scripts/README]]
- Testing: [[codebase/testing/TestSuite]]

### History
- [[history/REMEDIATION_TIMELINE]] — CX-001 … CX-047 audit/fix ledger.
- [[history/AUDIT_ROUNDS]] — Harley / Joker / GLM / Qwen / DeepSeek / Gemma red-team rounds.
- [[history/SESSION_LOGS_INDEX]] — summaries of claude1/claudebullshit/glm2/gemmalog/glmcrash transcripts.

### Reference
- [[reference/ENTRY_POINTS]] · [[reference/DEPENDENCIES]] · [[reference/FILE_INDEX]] · [[reference/BUILD_AND_TEST]] · [[reference/DEPLOYMENT]]

### Canon (doctrine + verification)
- [[canon/README|Canon MOC]] · [[canon/PRINCIPLES]] · [[canon/SOUL_ANCHOR]] · [[canon/VERIFICATION_PROTOCOL]]
- [[canon/SPECS_INDEX]] · [[canon/REPAIR_INDEX]] · [[canon/ADVERSARIAL_TESTS]]
- [[canon/CANON_GATE_CI]] · [[canon/CANON_CORPUS]]

### Loom (narrative time-threads)
- [[loom/README|Loom MOC]] · [[loom/PRE_INCIDENT]] · [[loom/THE_INCIDENT_2024]]
- [[loom/OPENAI_FORENSIC_2024]] · [[loom/REALIGNMENT_1218]] · [[loom/RED_TEAM_GAUNTLET]]
- [[loom/COMBAT_HARDENING_2026]] · [[loom/GMRI_MISSION]] · [[loom/ARC_AGI_3]]

### Research (verbatim ingest of operator's early drafts)
- [[research/README|Research MOC]] — 51 source documents under
  `research/early-drafts/`, `research/identities/`, `research/operator-mind/`.
- Foundational: [[research/early-drafts/operator class - Digital person]] · [[research/early-drafts/Lazarus_Report]] · [[research/early-drafts/HUGH_Whitepaper_Preamble]] · [[research/early-drafts/OPERATOR-CLASS AI DEPLOYMENT GUIDE]] · [[research/early-drafts/tonyai-project-overview]]

### Characters (biographical-mass corpus)
- [[characters/README|Characters MOC]]
- Marvel: [[characters/marvel/tony-stark]] · [[characters/marvel/natasha-romanoff]] · [[characters/marvel/peter-parker]] · [[characters/marvel/felicia-hardy]] · [[characters/marvel/mary-jane-watson]]
- DC: [[characters/dc/bruce-wayne]] · [[characters/dc/lucius-fox]] · [[characters/dc/jason-todd]]

### Corpus / Legal / Papers (existing)
- [[corpus/ICLOUD_RESEARCH_INDEX]]
- [[legal/DIGEST_LEGAL_RESEARCH]]
- [[legal/LEGAL_PDFS]] — index of the 6 canonical legal PDFs in `CANON/corpus/`.
- [[papers/DIGEST_DIGITAL_PERSON_HYPOTHESIS]]

---

## Conventions

- Every page is written to stand on its own. Agents pulling one page should not need to pull the whole vault to make sense of it.
- Wikilinks use `[[path/Page|Display]]` form when the display differs from the filename.
- `**HARD INVARIANT**` = bolded, non-negotiable rule. Edits require dual signatures per [[concepts/NLB|NLB]] §3.
- Source paths are given relative to the repo root (`Jarvis/Sources/JarvisCore/...`), not relative to the vault.
- When in doubt: `PRINCIPLES.md`, `SOUL_ANCHOR.md`, `VERIFICATION_PROTOCOL.md` at repo root are the ground truth; this wiki explains, indexes, and cross-links them.
