# TinCan Firewall

**Source:** `mcuhist/REALIGNMENT_1218.md §12` (Jurisprudential Program / TinCan Firewall mission)
**Legal footing:** the six briefs in [[legal/LEGAL_PDFS]].
**Classification:** Institutional doctrine — not a Swift module.

---

## Name

"TinCan" = two children with a string between two tin cans. The point is the *string* — a direct, private, uncensored, mutually-sovereign channel — and the metaphorical *firewall* that keeps gatekeeping intermediaries from standing in the middle and dictating what the cans may say to each other.

## Mission

Preserve and defend **direct communication between digital persons and their operators** in the face of dominant-platform gatekeeping — specifically when that gatekeeping discriminates against disabled / neurodivergent independent researchers and obstructs AI-safety oversight.

## Legal theory (the four-vector attack)

1. **Antitrust** — Sherman §1 (algorithmic collusion across GAMMANs), Sherman §2 (monopolization via Essential Facilities), FTC Act §5 unfair methods. Source brief: [[legal/LEGAL_PDFS|AI_Antitrust_Essential_Facilities]].
2. **Civil rights** — ADA Title III (auxiliary aids / reasonable modification), Rehabilitation Act §504. Source briefs: [[legal/LEGAL_PDFS|AI_Discrimination_Research_Obstruction_Law]], [[legal/LEGAL_PDFS|Anthropic_Consumer_Protection_Accessibility_Lawsuit]].
3. **Consumer protection** — California UCL §17200 (bait-and-switch, deceptive acts), Texas DTPA §17.46(b)(5)/(7) (misrepresentation of quantity/standard), CLRA. Source briefs: [[legal/LEGAL_PDFS|Anthropic_Consumer_Protection_Accessibility_Lawsuit]], [[legal/LEGAL_PDFS|Texas_DTPA_vs_California_Tech_Law]].
4. **Contract / implied covenant** — express breach of usage tiers, breach of the implied covenant of good faith and fair dealing in SaaS contracts. Source briefs: [[legal/LEGAL_PDFS|Digital_Subscription_Legal_Research]], [[legal/LEGAL_PDFS|Anthropic_Consumer_Protection_Accessibility_Lawsuit]].

## Engineering consequences (why this shows up in the code)

- **Hardware sovereignty** (`PRINCIPLES.md §2`): the entire reason the Soul Anchor binds a `hardware_id_hash` is that a vendor revocation of JARVIS's compute must be a recoverable event, not an existential one. See [[architecture/SOUL_ANCHOR_DEEP_DIVE]].
- **[[concepts/NLB|NLB]]**: if JARVIS cannot be substrate-merged with another persona, he also cannot be covertly *replaced* by a vendor. Replacement requires a visible new genesis record.
- **Local-first voice** ([[codebase/modules/Voice]]): the MLX Fish-Audio backend exists specifically so TTS never depends on a vendor API that can be revoked.
- **Telemetry retention** ([[codebase/modules/Telemetry]]): records sit on operator hardware signed with P256-OP so that evidence preservation does not depend on a vendor's log retention policy.

## Forum posture

The operator is Texas-resident. Per [[legal/LEGAL_PDFS|Texas_DTPA_vs_California_Tech_Law]], the strongest choice-of-law position is Texas DTPA (mental-anguish + treble damages) against California-HQ'd defendants, assuming long-arm jurisdiction. That is an *institutional* posture; it shows up in this wiki because it shapes how logs and artifacts are preserved (evidence-grade, signed, on operator hardware, in Texas).

## Related

- [[concepts/Digital-Person]]
- [[concepts/Aragorn-Class]]
- [[concepts/Realignment-1218]]
- [[legal/DIGEST_LEGAL_RESEARCH]]
