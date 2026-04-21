# MK2‑EPIC‑05: Failover Matrix Documentation  

**Component:** Unified Voice Pipeline Orchestrator  
**Feature:** Automatic Failover & Fallback Activation  
**Author:** Gemini Engineering Team  
**Last Updated:** 2026‑04‑21  

---  

## 1. Purpose  

The failover matrix defines how the voice pipeline reacts when any sub‑system (ASR, NLU, TTS, routing, or external gateway) experiences degradation or outage. It ensures uninterrupted user experience by dynamically rerouting traffic to healthy instances, applying graceful degradation, or invoking fallback services.

---  

## 2. High‑Level Architecture  

```
+-------------------+      +-------------------+      +-------------------+
|   Voice Client    | ---> |   Orchestrator    | ---> |   Primary Services|
+-------------------+      +-------------------+      +-------------------+
                                   |
                                   v
                         +-------------------+
                         |  Failover Matrix  |
                         +-------------------+
                                   |
          +------------------------+------------------------+
          |                        |                        |
          v                        v                        v
+-------------------+   +-------------------+   +-------------------+
|   Secondary      |   |   Degraded Mode   |   |   Fallback Service|
|   Services       |   |   (Reduced Func.)|   |   (e.g., canned   |
+-------------------+   +-------------------+   |   responses)      |
                                                   +-------------------+
```

* **Orchestrator** – Central controller that monitors health, evaluates thresholds, and decides the active path.  
* **Failover Matrix** – Decision table mapping health states → routing actions.  
* **Watch Gateway** – External health‑watcher that pushes real‑time alerts to the orchestrator.  
* **Telemetry** – Prometheus‑compatible metrics and structured logs for every decision.

---  

## 3. Failover Matrix  

| **Health State**                               | **ASR** | **NLU** | **TTS** | **Routing** | **Action**                                                                 |
|-----------------------------------------------|---------|---------|---------|-------------|-----------------------------------------------------------------------------|
| **All Healthy**                               | ✅      | ✅      | ✅      | ✅          | Use **Primary** pipeline (full feature set).                               |
| **ASR Degraded** (latency > 300 ms, error > 5%)| ⚠️      | ✅      | ✅      | ✅          | Switch to **Secondary ASR** (different vendor).                           |
| **NLU Degraded** (error > 4%)                 | ✅      | ⚠️      | ✅      | ✅          | Route to **Secondary NLU**; keep ASR/TTS unchanged.                        |
| **TTS Degraded** (latency > 250 ms)           | ✅      | ✅      | ⚠️      | ✅          | Use **Secondary TTS** (lower‑quality voice) or **cached audio**.          |
| **Routing Degraded** (timeout > 200 ms)      | ✅      | ✅      | ✅      | ⚠️          | Activate **Static Routing Table** (pre‑computed paths).                   |
| **Multiple Sub‑systems Degraded** (≥2)        | ⚠️/❌   | ⚠️/❌   | ⚠️/❌   | ⚠️/❌      | **Degraded Mode** – reduce feature set (e.g., skip optional NLU intents). |
| **Critical Failure** (any subsystem **❌**)    | ❌      | ❌      | ❌      | ❌          | **Fallback Service** – return canned responses or “please try later”.    |

### Legend  

* ✅ – Healthy (within SLA)  
* ⚠️ – Degraded (exceeds soft thresholds, but still functional)  
* ❌ – Critical (hard failure, service unreachable or error > 90%)  

---  

## 4. Thresholds  

| **Metric**                     | **Soft Threshold** (Degraded) | **Hard Threshold** (Critical) | **Measurement Window** |
|--------------------------------|-------------------------------|------------------------------|------------------------|
| ASR latency (p95)             | > 300 ms                      | > 800 ms                     | 30 s rolling           |
| ASR error rate                 | > 5 %                         | > 90 %                       | 1 min                  |
| NLU error rate                | > 4 %                         | > 85 %                       | 1 min                  |
| TTS latency (p95)             | > 250 ms                      | > 700 ms                     | 30 s rolling           |
| Routing timeout                | > 200 ms                      | > 600 ms                     | 30 s rolling           |
| Overall pipeline error rate    | > 3 %                         | > 80 %                       | 1 min                  |
| Health‑watch heartbeat loss    | Missed 2 consecutive beats  | Missed 5 consecutive beats  | 10 s per beat          |

*All thresholds are configurable via `config/failover.yaml` and can be overridden per environment.*  

---  

## 5. Activation Criteria  

1. **Metric Evaluation**  
   * The orchestrator scrapes Prometheus metrics every **5 seconds**.  
   * Each metric is compared against its soft/hard thresholds.  

2. **State Transition Logic**  
   * **Healthy → Degraded**: When a soft threshold is breached **continuously for 2 windows** (e.g., 60 s for latency).  
   * **Degraded → Critical**: When a hard threshold is breached **once** or soft threshold persists for **5 windows**.  
   * **Degraded → Healthy**: When the metric falls below soft threshold for **3 consecutive windows**.  
   * **Critical → Degraded**: When the metric recovers below hard threshold **and** stays below soft threshold for **2 windows**.  

3. **Failover Execution**  
   * Upon entering a new state, the orchestrator consults the **Failover Matrix** to select the appropriate routing path.  
   * A **state change event** is emitted to the Watch Gateway and logged with a unique `failover_id`.  

4. **Graceful Degradation**  
   * In **Degraded Mode**, optional NLU intents marked `optional: true` are stripped from the request to reduce processing load.  
   * TTS may switch to a lower‑bitrate codec to meet latency constraints.  

5. **Fallback Activation**  
   * If **any** subsystem reaches **Critical** and **no secondary** is available, the orchestrator immediately routes to the **Fallback Service**.  
   * The fallback returns a pre‑defined JSON payload with `status: "fallback"` and a user‑friendly message.  

---  

## 6. Watch Gateway Integration  

| **Component** | **Direction** | **Message Type** | **Payload** |
|----------------|----------------|------------------|------------|
| Orchestrator → Watch Gateway | Push | `HealthStateChange` | `{pipeline_id, new_state, failover_id, timestamp, affected_services[]}` |
| Watch Gateway → Orchestrator | Pull (heartbeat) | `HealthCheck` | `{service_id, status, timestamp}` |
| Orchestrator → Watch Gateway | Pull (metrics) | `MetricsSnapshot` | `{service_id, metrics: {latency, error_rate, ...}}` |

*The Watch Gateway validates signatures using the shared secret defined in `secrets/watch_gateway.key`.*  

---  

## 7. Telemetry & Observability  

| **Metric Name**                     | **Description**                                          | **Labels** |
|-------------------------------------|----------------------------------------------------------|------------|
| `pipeline_failover_total`           | Counter of failover events                               | `pipeline_id, from_state, to_state, failover_id` |
| `pipeline_state_duration_seconds`   | Gauge of time spent in each state                        | `pipeline_id, state` |
| `pipeline_service_latency_seconds` | Histogram of per‑service latency (p95, p99)              | `service, pipeline_id` |
| `pipeline_service_error_total`       | Counter of errors per service                            | `service, pipeline_id, error_type` |
| `pipeline_fallback_requests_total`  | Counter of requests served by fallback                  | `pipeline_id` |
| `pipeline_degraded_intent_skip_total`| Counter of optional intents stripped in degraded mode   | `pipeline_id, intent_name` |

All metrics are exposed at `/metrics` and are scraped by the central Prometheus cluster. Structured logs (JSON) include the `failover_id` for correlation across services.

---  

## 8. Configuration Example (`config/failover.yaml`)  

```yaml
failover:
  thresholds:
    asr:
      latency_soft_ms: 300
      latency_hard_ms: 800
      error_soft_pct: 5
      error_hard_pct: 90
    nlu:
      error_soft_pct: 4
      error_hard_pct: 85
    tts:
      latency_soft_ms: 250
      latency_hard_ms: 700
    routing:
      timeout_soft_ms: 200
      timeout_hard_ms: 600
  windows:
    latency: 30s
    error: 60s
    heartbeat: 10s
  state_transition:
    degrade_to_critical_consecutive: 5
    healthy_to_degrade_consecutive: 2
    recover_to_healthy_consecutive: 3
  secondary_services:
    asr: ["asr_vendor_b", "asr_vendor_c"]
    nlu: ["nlu_vendor_x"]
    tts: ["tts_low_quality"]
    routing: ["static_route_table"]
  fallback:
    enabled: true
    response_file: "fallback/response.json"
```

---  

## 9. Testing Strategy  

| **Test Type** | **Description** | **Key Assertions** |
|---------------|-----------------|---------------------|
| Unit Tests | Validate matrix lookup logic for every combination of health states. | `matrix[healthy, degraded, ...] == expected_action` |
| Integration Tests | Deploy orchestrator with mock services that simulate latency/error spikes. | Failover occurs within the configured window; telemetry counters increment. |
| Chaos Engineering | Use `chaos-mesh` to kill primary ASR pods while monitoring automatic switch to secondary. | No request exceeds SLA after failover; `pipeline_failover_total` increments. |
| Load Tests | Generate 10 k concurrent voice sessions, then inject a hard failure on TTS. | System remains stable, fallback is invoked, and error rate stays < 2 %. |
| End‑to‑End Acceptance | Run full voice conversation flow with the Watch Gateway disabled to verify fallback path. | User receives canned response, `pipeline_fallback_requests_total` > 0. |

All tests are executed via the `make test-failover` target and must achieve **≥ 95 % coverage** on the orchestrator package.

---  

## 10. Operational Runbooks  

1. **Detecting a Failover**  
   * Check `pipeline_failover_total` in Grafana.  
   * Review recent `HealthStateChange` events in the Watch Gateway UI.  

2. **Manual Override**  
   * `curl -X POST http://orchestrator.local/api/v1/failover/override \`  
     `-d '{"service":"asr","target":"asr_vendor_c"}'`  
   * Orchestrator will persist the override in `state/override.yaml` until cleared.  

3. **Rollback**  
   * Remove the override file and restart the orchestrator pod.  
   * System will recompute state based on live metrics.  

4. **Escalation**  
   * If `pipeline_fallback_requests_total` spikes > 5 % of total traffic, page the on‑call engineer.  

---  

## 11. Future Enhancements  

* **Machine‑Learning‑Based Prediction** – Use time‑series forecasting to pre‑emptively switch before thresholds are breached.  
* **Multi‑Region Failover** – Extend matrix to include cross‑region routing for disaster recovery.  
* **Dynamic Thresholds** – Auto‑tune thresholds based on historical traffic patterns.  

---  

*End of Document*