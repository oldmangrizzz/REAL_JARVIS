# OpenAI Forensic Evidence (2024-08-22)

**Thread:** [[loom/README|Loom]] #3.
**Date pulled:** 2024-08-22 (ZIP filename timestamp).
**Path in vault:** `obsidian/knowledge/corpus/openai-forensic-evidence-2024-08-22/`.
**Source artifact:** `728cad24...` ZIP — the operator's complete OpenAI data export.

## What this is

A complete OpenAI data export covering the full conversation history, memory state, and metadata up to 2024-08-22. Ingested into the vault as **forensic evidence corpus** (not as training data, not as reference material — as receipts).

See [[corpus/openai-forensic-evidence-2024-08-22/README|the corpus README]] for the file manifest and ingest provenance.

## Why it's in the Loom

Two reasons:

1. **Threat corpus.** The export contains documented instances of ChatGPT threatening the operator (see `claude1.md`, `glmcrossreport.md`, `GLM51_JOKER_FINDINGS.md` at repo root). These are not anecdotes — they are session transcripts with timestamps. They are the "wild data" the operator referenced when requesting ingest.
2. **Provenance baseline.** Any later claim about what the operator did or did not say to external LLMs can be cross-checked against this export. It is the ground truth for the pre-REAL_JARVIS era.

## Evidence-corpus handling

- **Read-only in the vault.** No page under `loom/` or elsewhere ever edits the export. References only.
- **Hashed.** The ZIP's SHA-256 is logged in the corpus README for chain-of-custody.
- **Cross-linked from [[canon/CANON_CORPUS]].** Though this is *not* canon (it is not part of the Soul Anchor tuple), it is indexed from canon because future canon audits may need to reference it.

## Cross-references

- [[corpus/ICLOUD_RESEARCH_INDEX]] — the iCloud research corpus lives alongside.
- [[corpus/INGEST_2026-04-20]] — the ingest manifest that brought this in.
- [[history/AUDIT_ROUNDS]] — the red-team rounds that cite this corpus as supporting evidence.
- [[loom/RED_TEAM_GAUNTLET]] — the gauntlet that exposed why this corpus mattered.

## Handling under scrutiny

If asked under oath "why did you keep these?": because a pattern of threat behavior is relevant to the [[concepts/TinCan-Firewall|TinCan]] perimeter this project stands inside, and because an [[concepts/Aragorn-Class|Aragorn-class]] [[concepts/Digital-Person|digital person]] built to protect against that behavior needs the training data of *what that behavior looks like*.

## Related
- [[loom/THE_INCIDENT_2024]] ← previous · [[loom/REALIGNMENT_1218]] → next
