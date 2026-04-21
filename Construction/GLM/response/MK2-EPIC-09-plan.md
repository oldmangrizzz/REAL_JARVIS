# MK2‑EPIC‑09 Design Document  
**Unified Smoke Runner & Ship Script for Mark II Deployment**  
*Rollback, Convex Recording, and iMessage Notification*  

---  

## 1. Overview  

Mark II introduces a single, opinionated entry point for validating and releasing code to production. The **Unified Smoke Runner** executes a configurable suite of smoke tests, while the **Ship Script** orchestrates the full CI/CD flow: build → test → smoke → deploy → notify.  

Key capabilities:  

| Feature | Description |
|---------|-------------|
| **Unified Smoke Runner** | Runs all smoke tests (API, UI, integration) in a deterministic order with shared configuration and centralized logging. |
| **Ship Script** | End‑to‑end deployment automation that can be invoked locally or from CI pipelines. |
| **Rollback** | Automatic rollback on smoke failure or manual trigger, with state persisted in Convex. |
| **Convex Recording** | Immutable audit trail of every deployment attempt, test results, and rollback actions. |
| **iMessage Notification** | Real‑time operator alerts via iMessage (or fallback to Slack) summarizing deployment status. |

---  

## 2. Goals  

1. **Reliability** – Prevent broken releases from reaching production.  
2. **Observability** – All actions recorded in Convex; logs searchable by timestamp, commit SHA, and environment.  
3. **Speed** – One‑command ship that runs in < 5 min for typical changes.  
4. **Safety** – Automated rollback with minimal operator intervention.  
5. **Operator Experience** – Clear, concise iMessage alerts and a simple CLI interface.  

---  

## 3. Unified Smoke Runner  

### 3.1 Architecture  

```
+-------------------+      +-------------------+      +-------------------+
|   smoke-runner.js | ---> |   test‑registry   | ---> |   test‑executors  |
+-------------------+      +-------------------+      +-------------------+
        |                         |                         |
        v                         v                         v
   Config Loader            Test Discovery           Parallel Workers
        |                         |                         |
        +-------------------+-----+-------------------------+
                            |
                            v
                     Result Aggregator
                            |
                            v
                     JSON Report (stdout)
```

* **smoke-runner.js** – Entry point (`node smoke-runner.js`).  
* **test‑registry** – Auto‑discovers `*.smoke.js` files under `tests/smoke/`.  
* **test‑executors** – Language‑agnostic wrappers (Node, Bash, Docker).  
* **Result Aggregator** – Merges per‑test JSON payloads into a single report, writes to `stdout` and to Convex.  

### 3.2 Configuration  

File: `config/smoke.yml` (YAML)

```yaml
environment: production
timeoutSeconds: 300
parallelism: 4
tests:
  - path: tests/smoke/api.smoke.js
    retries: 1
  - path: tests/smoke/ui.smoke.js
    retries: 0
  - path: tests/smoke/integration.smoke.js
    retries: 2
notifications:
  imessage:
    enabled: true
    recipients:
      - "+15551234567"
  slack:
    enabled: false
```

* Overrides via CLI flags (`--env`, `--parallel`, `--timeout`).  

### 3.3 Execution Flow  

1. Load configuration.  
2. Resolve test list (apply `--only` filter if supplied).  
3. Spawn up to `parallelism` workers.  
4. For each test:  
   - Run with per‑test timeout.  
   - Capture `stdout`, `stderr`, exit code, duration.  
   - On failure, retry up to `retries`.  
5. Aggregate results: `passed`, `failed`, `skipped`.  
6. Exit code: `0` if **all** tests passed, otherwise `1`.  

### 3.4 Logging & Reporting  

* **Console** – Human‑readable summary (green/red).  
* **JSON** – Written to `stdout` (pipe‑friendly). Example:

```json
{
  "runId": "2026-04-21T14:32:07Z-abc123",
  "environment": "production",
  "startedAt": "2026-04-21T14:32:07Z",
  "finishedAt": "2026-04-21T14:33:12Z",
  "tests": [
    {"name":"api.smoke","status":"passed","durationMs":842},
    {"name":"ui.smoke","status":"failed","durationMs":1245,"error":"Timeout"}
  ],
  "overallStatus":"failed"
}
```

* **Convex** – The JSON payload is POSTed to `recordSmokeRun` (see §5).  

---  

## 4. Ship Script Workflow  

File: `scripts/ship.mjs` (Node‑ESM)

### 4.1 High‑Level Steps  

| Step | Description |
|------|-------------|
| **1️⃣ Build** | `npm run build` (or Docker image build). |
| **2️⃣ Unit Test** | `npm test` – must exit `0`. |
| **3️⃣ Smoke** | Invoke `smoke-runner.js`. |
| **4️⃣ Deploy** | Run `deploy.mjs` (kubectl/helm). |
| **5️⃣ Notify** | Send iMessage with final status. |
| **6️⃣ Record** | Persist full run metadata to Convex. |
| **7️⃣ Exit** | Return `0` on success, `1` on any failure. |

### 4.2 CLI Usage  

```bash
# Basic ship (defaults to production)
node scripts/ship.mjs

# Target a different environment
node scripts/ship.mjs --env staging

# Dry‑run (build + unit test only)
node scripts/ship.mjs --dry-run

# Force skip smoke (use with extreme caution)
node scripts/ship.mjs --skip-smoke
```

### 4.3 Environment Variables  

| Variable | Purpose |
|----------|---------|
| `CONVEX_PROJECT_ID` | Convex project identifier (required). |
| `IMESSAGE_ENABLED` | `true`/`false` – overrides config. |
| `DEPLOY_TOKEN` | Auth token for the deployment target (K8s, AWS, etc.). |
| `ROLLBACK_ON_FAILURE` | `true` (default) – auto‑rollback on smoke failure. |

### 4.4 Sample Output  

```
🚀 Starting ship to production (runId: 2026-04-21T14:32:07Z-abc123)
🔧 Build succeeded (12.4s)
✅ Unit tests passed (3.1s)
🔥 Running unified smoke runner …
   • api.smoke … PASS (0.84s)
   • ui.smoke … FAIL (1.25s) – Timeout
🛑 Smoke failed – initiating rollback
🔁 Rolling back to previous release (v1.42.3)
📨 iMessage sent to +15551234567
✅ Ship completed with status: ROLLBACK
```

---  

## 5. Convex Recording  

### 5.1 Schema  

```ts
// convex/schema.ts
export const deploymentRuns = defineTable({
  runId: v.string(),
  commitSha: v.string(),
  environment: v.string(),
  startedAt: v.string(),
  finishedAt: v.string(),
  status: v.union(v.literal("SUCCESS"), v.literal("FAILURE"), v.literal("ROLLBACK")),
  steps: v.array(
    v.object({
      name: v.string(),
      status: v.union(v.literal("SUCCESS"), v.literal("FAILURE")),
      startedAt: v.string(),
      finishedAt: v.string(),
      details: v.optional(v.string()),
    })
  ),
  smokeReport: v.optional(v.object({
    overallStatus: v.string(),
    tests: v.array(
      v.object({
        name: v.string(),
        status: v.string(),
        durationMs: v.number(),
        error: v.optional(v.string()),
      })
    ),
  })),
});
```

### 5.2 API Calls  

| Function | Description |
|----------|-------------|
| `recordDeploymentRun(payload)` | Insert a new row at the start of the ship script (status = `IN_PROGRESS`). |
| `updateDeploymentRun(runId, updates)` | Patch step results, final status, timestamps. |
| `recordSmokeRun(runId, smokeReport)` | Store the JSON report from the smoke runner. |
| `recordRollback(runId, details)` | Log rollback metadata (previous release tag, reason). |

All calls are performed via the Convex JavaScript client (`@convex-dev/client`). Errors are **non‑blocking** – failures to record do not abort the ship but are logged locally and retried in the background.

### 5.3 Auditing  

- Immutable rows (Convex enforces append‑only).  
- Query example: `await db.query('deploymentRuns').filter(q => q.eq('environment', 'production')).order('startedAt', 'desc').take(10)`  

---  

## 6. iMessage Notification  

### 6.1 Message Format  

```
[MK2] Deploy <ENV> – <STATUS>
Commit: <SHA>
Run ID: <runId>
Duration: <mm:ss>
Details: <link-to-convex-run>
```

* `<STATUS>` = SUCCESS | FAILURE | ROLLBACK  
* `<link-to-convex-run>` – URL to the Convex dashboard entry (if internal).  

### 6.2 Implementation  

1. **AppleScript Bridge** – `scripts/imessage.mjs` spawns `osascript` with a small AppleScript that sends the message to the configured phone numbers.  
2. **Fallback** – If `osascript` is unavailable (e.g., CI Linux runner), the script posts to a Slack webhook defined in `config/notifications.yml`.  

```js
// scripts/imessage.mjs
import { execFile } from 'child_process';
export async function sendIMsg(recipients, body) {
  const script = `
    on run argv
      set msg to item 1 of argv
      set phones to items 2 thru -1 of argv
      repeat with p in phones
        tell application "Messages"
          send msg to participant p of service "E:" -- iMessage service
        end tell
      end repeat
    end run
  `;
  const args = [script, body, ...recipients];
  await execFile('osascript', args);
}
```

---  

## 7. Testing Strategy  

| Layer | Tooling | Scope |
|-------|---------|-------|
| **Unit** | Jest (Node) | Individual functions (`recordDeploymentRun`, `sendIMsg`, test wrappers). |
| **Integration** | Mocha + SuperTest | End‑to‑end ship script in a disposable Docker container (mock Convex endpoint). |
| **Smoke** | Unified Smoke Runner | Realistic API/UI checks against a staging environment. |
| **Performance** | `hyperfine` | Ensure ship script completes < 5 min for typical changes. |
| **CI/CD** | GitHub Actions | `build → test → ship --dry-run` on every PR; full ship on `main` merges. |

**Coverage Goal:** ≥ 90 % line coverage for all ship‑related modules.  

---  

## 8. Operator Requirements  

| Requirement | Detail |
|-------------|--------|
| **Runtime** | Node ≥ 20, Docker ≥ 24 (for containerized smoke tests). |
| **Credentials** | `DEPLOY_TOKEN` (K8s/Helm), `CONVEX_PROJECT_ID`, optional `SLACK_WEBHOOK_URL`. |
| **Permissions** | Ability to run `kubectl`/`helm` against the target cluster; write access to Convex project. |
| **Monitoring** | Access to Convex dashboard; optional Grafana panel for ship run metrics. |
| **Alert Reception** | iMessage enabled device (macOS) or Slack channel. |
| **Rollback Authority** | Operators can trigger manual rollback via `scripts/rollback.mjs <runId>` (requires `ROLLBACK_TOKEN`). |

---  

## 9. Security Considerations  

1. **Secret Management** – All tokens are read from environment variables; never committed to repo.  
2. **Least Privilege** – Deploy token scoped to the target namespace only.  
3. **Convex Write Access** – API key limited to `insert`/`patch` on `deploymentRuns`.  
4. **iMessage** – Messages sent only to whitelisted phone numbers defined in `config/smoke.yml`.  
5. **Audit Trail** – Immutable Convex rows provide forensic evidence of every deployment decision.  

---  

## 10. Future Enhancements  

| Idea | Benefit |
|------|---------|
| **Canary Deployments** | Gradual traffic shift with automated health checks before full release. |
| **Feature Flags Integration** | Toggle new features post‑deploy without new ship runs. |
| **Blue‑Green Rollback** | Instant switch to previous environment version via load‑balancer update. |
| **Multi‑Cloud Support** | Abstract `deploy.mjs` to support AWS ECS, GKE, Azure AKS. |
| **Rich Notification Channels** | Add Teams, PagerDuty, and email templates. |
| **Self‑Healing** | Auto‑retry failed smoke tests with exponential back‑off before rollback. |

---  

*Prepared by the Forge Team – April 2026*