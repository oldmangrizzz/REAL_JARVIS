# F5‑TTS Service

## Overview
The **F5‑TTS** service is the production‑grade Text‑to‑Speech (TTS) engine that replaces the legacy VibeVoice implementation. It exposes a simple HTTP API that accepts a JSON payload describing the text to be spoken and a set of optional synthesis parameters. The service forwards the request to the F5 backend, streams back the generated audio, and records metrics for observability.

Key improvements over VibeVoice:
- **Swift wiring** for the new synthesis parameters (`voice_id`, `speed`, `pitch`, `volume`, `language`).
- **Renamed watchdog** (`f5-tts-watchdog`) with enhanced health‑checking and auto‑restart capabilities.
- Full test suite that validates payload mapping and end‑to‑end backend integration while preserving the original contract (same endpoint, same response shape).

---

## Deployment Runbook

| Step | Description | Command / Action |
|------|-------------|------------------|
| **1. Prerequisites** | Kubernetes 1.24+, Helm 3, access to the `f5-tts` Docker registry, and a valid F5 API key stored in a Kubernetes secret named `f5-tts-secret`. | |
| **2. Clone the repo** | ```bash git clone https://github.com/yourorg/f5-tts.git cd f5-tts ``` | |
| **3. Update Helm values** | Edit `helm/f5-tts/values.yaml` to reflect your environment (replica count, resource limits, F5 endpoint, etc.). | |
| **4. Install/Upgrade** | ```bash helm upgrade --install f5-tts ./helm/f5-tts -n tts --create-namespace -f ./helm/f5-tts/values.yaml ``` | |
| **5. Verify Pods** | ```bash kubectl get pods -n tts -l app=f5-tts ``` Ensure all pods are `Running` and the `f5-tts-watchdog` sidecar is attached. |
| **6. Check Service** | ```bash kubectl get svc -n tts f5-tts ``` Confirm the ClusterIP (or LoadBalancer) is reachable. |
| **7. Validate Health** | ```bash curl -s http://<svc-ip>:8080/healthz | jq``` Should return `{ "status": "ok" }`. |
| **8. Promote to Production** | Once health checks pass, tag the Helm release with a semantic version and promote via your CI/CD pipeline. |

### Rollback
```bash
helm rollback f5-tts <REVISION> -n tts
```
The rollback restores the previous Docker image, config map, and the original `f5-tts-watchdog` configuration.

---

## Operator Usage

### API Endpoint
```
POST /v1/tts/synthesize
Content-Type: application/json
```

### Request Payload
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `text` | string | **Yes** | The plain‑text to synthesize. |
| `voice_id` | string | No | Identifier of the voice model (defaults to `en_us_male_1`). |
| `speed` | number (0.5‑2.0) | No | Speech speed multiplier. |
| `pitch` | number (-12‑12) | No | Pitch adjustment in semitones. |
| `volume` | number (0‑100) | No | Output volume percentage. |
| `language` | string | No | BCP‑47 language tag (e.g., `en-US`). |
| `metadata` | object | No | Arbitrary key/value pairs that are echoed back in the response for tracing. |

#### Example `curl` request
```bash
curl -X POST http://f5-tts.tss.svc.cluster.local/v1/tts/synthesize \
     -H "Content-Type: application/json" \
     -d '{
           "text": "Hello, world!",
           "voice_id": "en_us_female_2",
           "speed": 1.2,
           "pitch": 2,
           "volume": 85,
           "language": "en-US",
           "metadata": {"request_id":"abc123"}
         }' --output hello.wav
```

### Response
- **Status 200** – `audio/wav` stream containing the synthesized audio.
- **Headers**  
  - `X-Request-ID`: Mirrors the `metadata.request_id` if supplied.  
  - `X-Voice-ID`: The voice actually used (may differ if fallback occurs).  

- **Error payload** (JSON) for non‑200 responses:
```json
{
  "error": "InvalidParameter",
  "message": "speed must be between 0.5 and 2.0"
}
```

### Monitoring & Observability
- **Prometheus metrics** are exposed at `/metrics`. Key metrics: `f5_tts_requests_total`, `f5_tts_latency_seconds`, `f5_tts_backend_errors_total`.
- **Logs** are streamed to stdout in JSON format. Include `request_id`, `voice_id`, and `duration_ms`.
- **Watchdog** (`f5-tts-watchdog`) restarts the service automatically on crash and reports health to the `watchdog` namespace.

---

## Re‑Audition Instructions

Re‑auditioning is the process of re‑generating audio for a given text to verify quality after a model update or parameter change.

1. **Identify the original request**  
   Retrieve the original payload from your audit store (e.g., S3, database) using the `request_id`.

2. **Run the re‑audition command**  
   ```bash
   ./scripts/reaudit.sh \
       --text "$(cat original_text.txt)" \
       --voice-id en_us_female_2 \
       --speed 1.0 \
       --pitch 0 \
       --volume 100 \
       --output reaudited.wav
   ```

   The script internally calls the F5‑TTS API and stores the resulting WAV file.

3. **Compare audio**  
   Use any audio diff tool (e.g., `sox`, `ffmpeg` with `ffprobe`) to compare the new file with the baseline:
   ```bash
   sox --i -D baseline.wav reaudited.wav
   ```

4. **Record the result**  
   Update the audit database with a status (`PASS`, `FAIL`, `MANUAL_REVIEW`) and any notes about perceptual differences.

5. **Automated regression**  
   The CI pipeline runs the `tests/integration/reaudit_test.go` suite nightly to ensure no regression in voice quality or latency.

---

## Testing

### Unit Tests – Payload Mapping
- Location: `services/f5-tts/internal/payload_test.go`
- Verifies that the incoming JSON is correctly transformed into the F5 backend request struct, including default handling for omitted parameters.
- Run: `go test ./services/f5-tts/internal -run TestPayloadMapping`

### Integration Tests – Backend Integration
- Location: `services/f5-tts/tests/integration/backend_test.go`
- Spins up a mock F5 backend (using `httptest.Server`) and asserts that:
  * All parameters are forwarded verbatim.
  * The service returns the exact audio payload received from the mock.
  * Error handling (timeouts, 5xx) is propagated as defined in the contract.
- Run: `go test ./services/f5-tts/tests/integration -run TestBackendIntegration`

### End‑to‑End Tests – Contract Preservation
- Location: `services/f5-tts/tests/e2e/contract_test.go`
- Executes a real request against a deployed staging instance and validates:
  * HTTP status codes.
  * Response headers (`X-Request-ID`, `X-Voice-ID`).
  * Audio format (`audio/wav`) and basic waveform sanity (non‑zero length).
- Run: `make e2e-test`

All tests are executed in CI on every PR. The test suite must pass before a new version can be promoted to production.

---

## FAQ

**Q: Do I need to change existing client code?**  
A: No. The public API (`/v1/tts/synthesize`) and response format remain identical to the former VibeVoice service. New parameters are optional and ignored by older clients.

**Q: What happened to the old watchdog?**  
A: The legacy `vibevoice-watchdog` has been renamed to `f5-tts-watchdog`. Its configuration lives under `helm/f5-tts/values.yaml.watchdog`.

**Q: How do I add a new voice model?**  
A: Add the model ID to the `allowedVoiceIds` list in `config/voice_policy.yaml` and redeploy the Helm chart. The service will automatically expose the new `voice_id` value.

**Q: Where are the Swift bindings?**  
A: The Swift client library is located at `clients/swift/f5tts/`. It includes generated request structs that map directly to the JSON payload described above.

--- 

*Prepared by the Platform Engineering team – © 2026 Your Organization*