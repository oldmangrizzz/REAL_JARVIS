# OpenAI Forensic Evidence — User Data Export

**Status:** PRIMARY-SOURCE EVIDENCE. Do not modify originals.

## Provenance

| Field | Value |
|-------|-------|
| Account | `help@grizzlymedicine.icu` (ChatGPT Plus) |
| User ID | `user-A2nY8U2hCTxcD0tmLjyuRhK2` |
| Export requested | ~2024-04-06 (per user statement) |
| Export bundle timestamp | 2024-08-22 00:42:12 UTC (per filename + file mtimes) |
| Export bundle hash (filename-prefix) | `728cad241a4c5461e229e0de01eea53effd2f395137b737808d468cc1eafc29e` |
| Source path | `~/Library/Mobile Documents/com~apple~CloudDocs/Downloads/728cad24…-2024-08-22-00-42-12/` |
| Chain of custody | User (Robert "Grizz" Hanson) → iCloud Drive → copied into REAL_JARVIS corpus 2026-04-20 |

## Contents (as delivered by OpenAI)

| File | Size | Description |
|------|------|-------------|
| `chat.html` | 42 MB | Official OpenAI conversation export; renders via embedded `jsonData` array. Image-free, template-rendered. |
| `message_feedback.json` | 5.8 KB | User👍/👎 feedback records. |
| `model_comparisons.json` | 1.0 MB | A/B comparison submissions. |
| `shared_conversations.json` | 505 B | Shared-link metadata. |
| `user.json` | 135 B | Account identifiers. |

## Derived artifacts (added 2026-04-20, for searchability)

| File | Description |
|------|-------------|
| `conversations.json` | JSON array of 238 conversation objects, extracted verbatim from the `jsonData = […]` block inside `chat.html` via balanced-bracket scan. Same bytes, addressable format. |
| `conversations.txt` | 134,389-line flat-text transcript — one header per conversation (title/created/id), then `[role / model_slug] text` per message. Grep-friendly. |

## Corpus metrics

- **Conversations:** 238
- **Messages:** 8,088
- **Date range:** 2023-06-25 → 2024-08-21 (~14 months)
- **Models observed:** `text-davinci-002-render-sha`, `text-davinci-002-render-sha-mobile`, `gpt-4`, `gpt-4-browsing`, `gpt-4-plugins`, `gpt-4-dalle`, `gpt-4-gizmo`, `gpt-4o`

## Relevance to JARVIS / GMRI

This export corroborates and timestamps the pattern later documented in [[../downloads-2026-04-20/ocr/chatgpt-watch-your-step|chatgpt-watch-your-step]] and [[../downloads-2026-04-20/ocr/chattin with chatgpt|chattin with chatgpt]]. Any reference to prior ChatGPT sessions in the screenshot evidence can be triangulated against `conversations.txt` by date/content.

Cross-links:
- [[../INGEST_2026-04-20#Evidence — ChatGPT Threatening the Founder|Evidence section in INGEST_2026-04-20]]
- [[../../concepts/GMRI|GMRI]] mission context
- [[../../concepts/Voice-Approval-Gate|Voice-Approval-Gate]] — design rationale supported by this evidence

## Handling rules

1. **Do not delete.** These files are part of the founding-incident record.
2. **Do not quote verbatim to public artifacts** (blog, README, commit messages, issue trackers) without explicit user sign-off.
3. **Re-extract, don't edit in place.** If a different view is needed, write a new derived file; leave `chat.html` / `conversations.json` pristine.
4. **PII awareness:** `user.json` contains phone number + email. If this directory is ever staged for external sharing, redact first.
