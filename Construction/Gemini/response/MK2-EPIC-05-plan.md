# MK2‑EPIC‑05 – Voice Pipeline Orchestrator Design Document

**Author:** Gemini Team  
**Created:** 2026‑04‑21  
**Status:** Draft (subject to review)  

---

## 1. Purpose & Scope

This document defines the architecture, fail‑over strategy, telemetry model, and watch‑gateway token handling for the **VoicePipelineOrchestrator (VPO)** – a unified, resilient orchestration layer that coordinates all voice‑processing pipelines (ASR, NLU, TTS, etc.) across the platform.

The VPO must:

1. **Route** incoming voice streams to the appropriate pipeline based on configuration, locale, and runtime health.
2. **Detect & recover** from component failures using a deterministic fail‑over matrix.
3. **Expose** a watch‑gateway endpoint for real‑time health and token‑based authentication.
4. **Emit** structured telemetry for observability, alerting, and capacity planning.
5. **Support** seamless integration with existing services (e.g., `VoiceGateway`, `TelemetryCollector`, `AuthService`).

---

## 2. High‑Level Architecture

```
+-------------------+        +-------------------+        +-------------------+
|   VoiceGateway    | <----> |  WatchGateway     | <----> |   AuthService     |
+-------------------+        +-------------------+        +-------------------+
          |                           |                         |
          |   (gRPC / HTTP/2)         |   (REST/WS)            | (OAuth2/JWT)
          v                           v                         v
+---------------------------------------------------------------+
|                     VoicePipelineOrchestrator                |
|                                                               |
|  +-------------------+   +-------------------+   +-----------+ |
|  |  Pipeline Router  |   |  Fail‑over Matrix |   | Telemetry | |
|  +-------------------+   +-------------------+   +-----------+ |
|          |                         |               |           |
|          v                         v               v           |
|  +-------------------+   +-------------------+   +-----------+ |
|  |  ASR Service Pool |   |  NLU Service Pool |   |  Metrics  | |
|  +-------------------+   +-------------------+   +-----------+ |
|          |                         |               |           |
|          v                         v               v           |
|  +-------------------+   +-------------------+   +-----------+ |
|  |  TTS Service Pool |   |  Post‑Processing  |   |  Logs     | |
|  +-------------------+   +-------------------+   +-----------+ |
+---------------------------------------------------------------+
```

* **VoiceGateway** – entry point for client audio (WebRTC, SIP, etc.).
* **WatchGateway** – health‑check & token‑validation endpoint consumed by monitoring agents.
* **AuthService** – issues short‑lived JWTs for VPO‑WatchGateway interactions.
* **Pipeline Router** – selects the primary pipeline based on request metadata.
* **Fail‑over Matrix** – deterministic mapping of primary → secondary services per component.
* **Telemetry** – emits Prometheus‑compatible metrics and structured JSON logs to `TelemetryCollector`.

---

## 3. Component Details

### 3.1 Pipeline Router

| Input | Decision Factors | Output |
|-------|------------------|--------|
| `audio_stream` (binary) | - Locale (`en-US`, `fr-FR`, …) <br> - Requested features (ASR‑only, ASR+NLU, etc.) <br> - Service version tags (v1, v2‑beta) | `PipelineContext` containing selected service endpoints and fallback list |

*Implemented as a stateless gRPC service; configuration is hot‑reloaded from a central `pipeline-config.yaml`.*

### 3.2 Fail‑over Matrix

The matrix is a **deterministic, priority‑ordered list** per component type. Example (ASR):

| Priority | Service ID | Endpoint | Health Check |
|----------|------------|----------|--------------|
| 1        | `asr‑primary‑us‑1` | `asr-us-1.internal:50051` | `/healthz` |
| 2        | `asr‑secondary‑us‑1` | `asr-us-2.internal:50051` | `/healthz` |
| 3        | `asr‑fallback‑global` | `asr-global.internal:50051` | `/healthz` |

*The matrix is stored in `failover-matrix.json` and refreshed every 30 seconds via a background watcher.*

**Fail‑over algorithm (pseudo‑code):**

```go
func selectService(component string, ctx PipelineContext) (endpoint string, err error) {
    candidates := matrix[component][ctx.locale]
    for _, svc := range candidates {
        if healthCache.IsHealthy(svc.Endpoint) {
            return svc.Endpoint, nil
        }
    }
    return "", fmt.Errorf("no healthy %s service for %s", component, ctx.locale)
}
```

### 3.3 WatchGateway Integration

* **Endpoint:** `GET /watch/v1/health` (returns JSON with per‑component health)
* **Authentication:** JWT signed by `AuthService`. Tokens are **5 min** lifetime, issued via `POST /auth/v1/token` with a service‑principal payload.
* **Rate limiting:** 100 req/s per monitoring client (enforced by Envoy sidecar).

**Health payload schema:**

```json
{
  "timestamp": "2026-04-21T12:34:56Z",
  "components": {
    "asr": {
      "primary": "healthy",
      "secondary": "degraded",
      "fallback": "unhealthy"
    },
    "nlu": { "primary": "healthy" },
    "tts": { "primary": "healthy" }
  },
  "failover_active": false,
  "token_expiry": "2026-04-21T12:39:56Z"
}
```

### 3.4 Telemetry Schema

All metrics are exported via **Prometheus** and **OpenTelemetry**. The schema is versioned (`v0.2`) and includes:

| Metric Name | Type | Labels | Description |
|-------------|------|--------|-------------|
| `vpo_requests_total` | Counter | `pipeline`, `locale`, `status` | Total requests processed |
| `vpo_request_duration_seconds` | Histogram | `pipeline`, `locale` | Latency per request |
| `vpo_failover_events_total` | Counter | `component`, `from`, `to` | Number of fail‑over switches |
| `vpo_service_health` | Gauge | `component`, `service_id`, `state` (`0=unhealthy`, `1=healthy`) | Current health status |
| `vpo_token_validation_seconds` | Histogram | `outcome` (`success`, `failure`) | Time to validate WatchGateway JWT |

**Log format (JSON):**

```json
{
  "timestamp":"2026-04-21T12:35:01.123Z",
  "level":"INFO",
  "msg":"request_processed",
  "request_id":"c3f5e9a1-7b2d-4a9f-9c1e-2d5f6b8a9c0d",
  "pipeline":"asr+nlu",
  "locale":"en-US",
  "duration_ms":124,
  "failover":false,
  "service_endpoints":{
    "asr":"asr-us-1.internal:50051",
    "nlu":"nlu-us-1.internal:50052"
  }
}
```

### 3.5 WatchGateway Token Handling

1. **Token Request** – VPO calls `AuthService` with its service principal (`vpo-orchestrator`). AuthService returns a JWT containing:
   * `sub`: `vpo-orchestrator`
   * `aud`: `watch-gateway`
   * `exp`: Unix timestamp (5 min)
   * `iat`: Unix timestamp
2. **Cache** – VPO caches the token in an in‑memory LRU store (max 5 entries) and refreshes **30 seconds** before expiry.
3. **Validation** – Incoming WatchGateway requests are validated using the public key from AuthService’s JWKS endpoint (`/auth/v1/.well-known/jwks.json`). Validation includes:
   * Signature verification
   * `aud` claim match
   * `exp` not exceeded
4. **Revocation** – AuthService can publish a revocation event to `Redis` channel `auth_revocations`. VPO subscribes and immediately invalidates matching tokens.

---

## 4. Failure Scenarios & Recovery

| Scenario | Detection | Action | Telemetry |
|----------|----------|--------|-----------|
| Primary ASR becomes unhealthy | Health checker returns `false` for `/healthz` | Promote secondary ASR per matrix; log `failover` event | Increment `vpo_failover_events_total{component="asr",from="primary",to="secondary"}` |
| WatchGateway token expired | JWT validation fails with `exp` error | Trigger token refresh flow; retry request once | Record `vpo_token_validation_seconds{outcome="failure"}` |
| Complete component outage (no healthy candidates) | All entries in matrix unhealthy | Return `503 Service Unavailable` with JSON error; raise alert via Alertmanager | Increment `vpo_requests_total{status="unavailable"}` |
| Telemetry collector unreachable | Exporter error on push | Buffer metrics locally (up to 5 min) and retry; fallback to stdout logs | Emit `vpo_metrics_buffered_total` gauge |

---

## 5. Security Considerations

| Concern | Mitigation |
|---------|------------|
| **JWT Replay** | Tokens are short‑lived (5 min) and include `jti` claim; WatchGateway validates uniqueness via in‑memory cache. |
| **Man‑in‑the‑Middle** | All inter‑service traffic uses mTLS (mutual TLS) with certificates rotated via SPIFFE. |
| **Configuration Injection** | `pipeline-config.yaml` and `failover-matrix.json` are loaded from a read‑only ConfigMap; changes require a rolling restart. |
| **Denial‑of‑Service** | Rate limiting on WatchGateway; circuit‑breaker on downstream services after 5 consecutive failures. |

---

## 6. Deployment & Operations

* **Container Image:** `registry.internal/voice/vpo:0.9.3`
* **Kubernetes Resources:**  
  * `Deployment` (replicas = 3, pod anti‑affinity)  
  * `Service` (ClusterIP)  
  * `HorizontalPodAutoscaler` (target CPU = 70 %)  
  * `ConfigMap` for `pipeline-config.yaml` & `failover-matrix.json`  
  * `Secret` for AuthService client credentials
* **Observability Stack:** Prometheus + Grafana dashboards (`vpo-dashboard.json`), Loki for logs, Jaeger for traces.
* **CI/CD:** GitHub Actions → Docker build → Helm chart release (semantic version bump).

---

## 7. Testing Strategy

| Test Type | Scope | Tools |
|-----------|-------|-------|
| **Unit** | Router logic, matrix selection, token cache | Go `testing`, `gomock` |
| **Integration** | End‑to‑end request flow with mock ASR/NLU/TTS services | `testcontainers-go`, `grpc-go` |
| **Chaos** | Simulated service failures (latency, crash) to verify fail‑over | `chaos-mesh`, `pumba` |
| **Load** | 10k concurrent streams, measure latency & fail‑over latency | `k6`, `locust` |
| **Security** | JWT validation, mTLS handshake, token revocation | `OWASP ZAP`, custom Go fuzzers |
| **Contract** | WatchGateway health endpoint schema compliance | `Postman/Newman`, `OpenAPI` validator |

All tests are gated by a **GitHub PR check** with a minimum coverage of **85 %**.

---

## 8. Future Enhancements

1. **Dynamic Matrix via Service Mesh** – leverage Istio’s DestinationRule to auto‑populate fail‑over candidates.
2. **AI‑driven Routing** – use a lightweight model to predict optimal pipeline based on audio characteristics.
3. **Multi‑Region Fail‑over** – extend matrix to include cross‑region fallbacks with latency‑aware selection.
4. **Self‑Healing** – automatic restart of unhealthy pods via Kubernetes `PodDisruptionBudget` and custom controller.

---

*End of Document*