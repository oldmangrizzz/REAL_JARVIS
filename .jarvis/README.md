# .jarvis/

JARVIS runtime and state directory.

## Tracked (committed to git)

Config templates and manifests:
- `capabilities.json` — Feature capability manifest
- `control-plane/` — Control plane configuration templates
- `soul_anchor/` — Identity and genesis manifests (not encrypted; not secrets)

## Runtime Only (not committed)

Add to `.gitignore` — these are generated/transient:
- `alignment_tax/` — Metrics and alignment traces
- `artifacts/` — Build artifacts and deployment reports
- `*.log` — All runtime logs (interface, voice-bridge, validation, etc.)
- `*.pid` — Process ID files
- `nim/` — Generated Nim client code
- `storage/` — Runtime caches, voice recordings, tunnel secret
- `telemetry/` — Execution telemetry and signal logs
- `validation_logs/` — Build/test output logs
- `voice/` — Cached voice samples

## Secrets (DO NOT TRACK)

- `storage/tunnel/secret` — Tunnel authentication secret
  - Managed outside git
  - Rotated per SOUL_ANCHOR.md signature protocol
