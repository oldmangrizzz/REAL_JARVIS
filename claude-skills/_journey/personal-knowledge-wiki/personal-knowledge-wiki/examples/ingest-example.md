# Example: Ingesting an Article

## Source
Drop an article into `raw/articles/karpathy-llm-wiki.md`

## What the Librarian Creates

1. **Source page:** `wiki/sources/karpathy-llm-wiki-pattern.md`
   - Key takeaways, summary, connections to other pages

2. **Entity page:** `wiki/entities/andrej-karpathy.md`
   - Key facts, mentions across sources, related concepts

3. **Concept pages:**
   - `wiki/concepts/rag.md` — Retrieval-Augmented Generation
   - `wiki/concepts/memex.md` — Vannevar Bush's 1945 vision

4. **Updates:**
   - `wiki/index.md` — 4 new entries added
   - `wiki/log.md` — "Ingested karpathy-llm-wiki.md, created 4 pages, 18 cross-references"

## Result
One article → 4 wiki pages → 18 wikilinks connecting ideas across the knowledge base.
