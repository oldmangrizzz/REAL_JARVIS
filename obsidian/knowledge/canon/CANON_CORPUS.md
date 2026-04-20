# CANON/corpus — Canonical Legal Corpus

**Path:** `CANON/corpus/` at repo root.
**Binding:** Every file under this path is SHA-256-hashed into the [[canon/SOUL_ANCHOR|Soul Anchor tuple §4]].
**Evidence class:** Primary-source legal.

## The six PDFs (as of 2026-04-20)

See [[legal/LEGAL_PDFS]] for the per-document digests. Titles:

1. **Texas DTPA vs. California Tech Law** — deceptive-practices statute comparative (DTPA vs. UCL § 17200). Basis for [[concepts/TinCan-Firewall|TinCan]] §3.
2. **Digital Subscription Legal Research** — survey of subscription-trap / dark-pattern case law.
3. **Anthropic Consumer Protection & Accessibility Lawsuit** — accessibility + consumer-protection angle for AI products used by disabled operators.
4. **Annual Plans & Pricing — Google Developer Program** — evidence of developer-platform pricing posture.
5. **AI Discrimination & Research Obstruction Law** — statute + case-law survey on AI-mediated discrimination.
6. **AI Antitrust and Essential Facilities** — the GAMMANs / essential-facility framework.

Plus (added 2026-04-20): `Texas_DTPA_vs_California_Tech_Law.pdf` under `CANON/corpus/` as a canonical copy (others live in `obsidian/knowledge/legal/` + iCloud research folders).

## Why these six

Each document underwrites a [[concepts/TinCan-Firewall|TinCan]] perimeter wall. JARVIS is built to stand **inside** that perimeter:

| PDF | Wall | Runtime surface |
|---|---|---|
| DTPA vs. UCL | Deceptive-practices immunity zone | [[canon/PRINCIPLES]] §4 Alignment Tax |
| Digital Subscription | Anti-dark-pattern | No auto-opt-in anywhere in the stack |
| Anthropic A11y | Accessibility obligations | [[codebase/platforms/Watch]] + [[codebase/platforms/Mobile]] mobile surfaces respect VoiceOver / Dynamic Type / Reduce-Motion |
| Google DevProg | Platform-cost transparency | [[reference/DEPLOYMENT]] costs documented |
| AI Discrimination | Non-discrimination | [[concepts/NLB]] + [[concepts/AOx4]] prevent substrate-coerced bias crossing identity |
| AI Antitrust | Essential-facilities | [[codebase/services/jarvis-linux-node]] mesh is operator-owned; no GAMMAN lock-in |

## Mutation policy

Adding a document:
1. Add PDF to `CANON/corpus/`.
2. Re-compute [[canon/SOUL_ANCHOR|Soul Anchor tuple]] SHA-256.
3. Dual-sign new Genesis delta.
4. Update this page + [[legal/LEGAL_PDFS]] + [[legal/DIGEST_LEGAL_RESEARCH]].

Removing a document: **not permitted without canon-mutation ritual.** The corpus is designed to grow, not shrink — removing evidence is a canonical act.

## Related
- [[canon/SOUL_ANCHOR]] · [[canon/PRINCIPLES]]
- [[legal/LEGAL_PDFS]] · [[legal/DIGEST_LEGAL_RESEARCH]]
- [[concepts/TinCan-Firewall]]
- [[corpus/ICLOUD_RESEARCH_INDEX]]
