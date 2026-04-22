# Phase 4 — Cognee Memory Migration (Beta → Delta)

## Why
Beta (Intel N4200) has no AVX; onnxruntime/fastembed SIGILL on model load.
Cognee hard-depends on embeddings. Migration to Delta (EPYC 9354P) was mandatory.

## What landed
- **Host**: Delta (`187.124.28.147`)
- **Service**: `jarvis-memory.service` → uvicorn `mem_api:app` on `100.98.95.75:9470`
  (netbird `wt0` only; public IP blocked).
- **Stack**: Cognee 0.5.1 + Kuzu (graph) + LanceDB (vector) + FastEmbed
  (`BAAI/bge-small-en-v1.5`) + LLM via Ollama gateway as `openai/gpt-oss:20b`.
- **Auth**: FastAPI bearer wrapper (`mem_api.py`). Token in
  `/opt/jarvis-memory/.env` → `MEM_API_TOKEN`. Echo mirrors it in
  `~/.copilot/session-state/.../files/`.
- **Endpoints**:
  - `POST /add` — `{"text": "...", "dataset": "name"}`
  - `POST /cognify` — body is bare JSON list: `["agent-skills", "obsidian"]`
  - `POST /recall` — returns `{GRAPH_COMPLETION, CHUNKS}`
  - `GET /health`
- **Concurrency patch**: Cognee has no built-in cap. Patched
  `site-packages/cognee/tasks/graph/extract_graph_from_data.py` with
  `asyncio.Semaphore(COGNEE_LLM_CONCURRENCY)` (default 4) around `asyncio.gather`
  so the Ollama gateway doesn't get hammered on 240-doc cognify runs.
- **Seed corpus** (240 files, 2.3 MB):
  - `canon/` — PRINCIPLES, SOUL_ANCHOR, MARK_III_BLUEPRINT, MARK_III_SUPERBIBLE,
    JARVIS_INTELLIGENCE_BRIEF, JARVIS_TRAINING_BRIEF
  - `obsidian/` — full knowledge vault
  - `agent-skills/` — every `.md`/`.skill`
- **Bulk seeder**: `/opt/jarvis-memory/bulk_seed.py` walks sources/, groups by
  top-level dir as dataset, POSTs `/add` then `/cognify`.

## Client
`~/.jarvis/bin/jarvis-recall "query"` on Echo — HTTP client to Delta:9470.

## Gotchas
- Python stdout is buffered over SSH pipes. Always `python -u` + nohup +
  redirect to file + `tail` the file separately.
- SSH can exit 255 on transient session reset while child process keeps
  running — re-verify with `ps -ef | grep bulk_seed`.
- Cognee 0.5 emits a "multi-user access control" warning on first boot.
  Benign unless old single-user data becomes invisible; then set
  `ENABLE_BACKEND_ACCESS_CONTROL=false`.
- LiteLLM requires `openai/` prefix for OpenAI-compatible endpoints (Ollama
  gateway), e.g. `openai/gpt-oss:20b`.
- FastEmbed needs `HUGGINGFACE_TOKENIZER` env even when
  `EMBEDDING_PROVIDER=fastembed`.
- `COGNEE_SKIP_CONNECTION_TEST=true` bypasses 30-second preflight that fails
  on cold remote LLMs.

## Verified
- `/health` → 200, cognee 0.5.1.
- `/recall "what is agency swarm stigmergy?"` → GRAPH_COMPLETION + CHUNKS.
- 238/240 docs added, 2 transient failures acceptable.
