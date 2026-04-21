# MK2-EPIC-09 – One‑Command Deployment & Smoke Suite for Mark II

**Author:** [Your Name]  
**Date:** 2026‑04‑21  
**Status:** Draft → Review → Approved  

---

## 1. Overview

Mark II introduces a unified, one‑command deployment flow that automatically provisions the target environment, ships the build, runs a comprehensive smoke suite, and rolls back on failure. The new flow is built around three core artifacts:

| Artifact | Purpose |
|----------|---------|
| **Unified Smoke Runner** (`smoke-runner`) | Executes all smoke tests (unit, integration, end‑to‑end) against the freshly deployed stack. |
| **Ship Script with Rollback** (`ship.sh`) | Packages, uploads, and deploys the build; monitors health; triggers rollback if any smoke test fails. |
| **Convex Recording** (`convex-record`) | Captures deterministic execution traces of the deployed services for later replay and debugging. |

These artifacts are versioned, stored in the `artifacts/` directory, and referenced by the CI pipeline via a single `make deploy` target.

---

## 2. Goals

| Goal | Success Metric |
|------|-----------------|
| **One‑Command Deploy** | `make deploy` completes successfully in < 15 min on a clean environment. |
| **Automatic Rollback** | Any smoke failure triggers a rollback to the previous stable release within 5 min. |
| **Unified Smoke Suite** | All existing smoke tests (unit, integration, e2e) run under a single runner with a unified report. |
| **Deterministic Debugging** | Convex recordings are generated for every deployment and stored in the artifact store. |
| **Zero‑Downtime** | No user‑visible outage (> 5 s) during ship or rollback. |

---

## 3. Scope

- **In‑Scope**  
  - Refactor existing smoke tests to be consumable by `smoke-runner`.  
  - Implement `ship.sh` with pre‑flight checks, health probes, and rollback logic.  
  - Add Convex instrumentation to all Mark II services and integrate `convex-record`.  
  - Update CI/CD pipeline (`.github/workflows/deploy.yml`) to use the new flow.  
  - Documentation and training material for developers and ops.

- **Out‑of‑Scope**  
  - Migration of legacy Mark I services not covered by Convex.  
  - Full blue‑green deployment strategy (future EPIC).  
  - Multi‑region rollouts (future EPIC).

---

## 4. Architecture

```
+-------------------+      +-------------------+      +-------------------+
|   CI Pipeline    | ---> |   ship.sh (CLI)   | ---> |   Target Cluster   |
+-------------------+      +-------------------+      +-------------------+
          |                         |                         |
          |                         v                         v
          |                +-------------------+      +-------------------+
          |                |  Unified Smoke   |      |  Convex Recorder  |
          |                |   Runner (smoke‑run) |  | (convex‑record)   |
          |                +-------------------+      +-------------------+
          |                         |                         |
          |                         v                         v
          |                +-------------------+      +-------------------+
          |                |   Test Report (HTML/JSON)   |
          |                +-------------------+      +-------------------+
          |                         |
          |                         v
          |                +-------------------+
          |                |   Rollback Logic  |
          |                +-------------------+
          |                         |
          +------------------------>|
```

- **ship.sh**: Bash script orchestrating build upload, `kubectl`/`helm` deployment, health checks, and invoking `smoke-runner`.  
- **smoke-runner**: Go binary that discovers test binaries via a manifest (`smoke-tests.yaml`), runs them in parallel, aggregates results, and exits with a non‑zero status on any failure.  
- **convex-record**: Sidecar container injected into each service pod; records execution traces to a shared PersistentVolumeClaim and pushes them to the artifact store after deployment.

---

## 5. Component Details

### 5.1 Unified Smoke Runner (`smoke-runner`)

- **Language**: Go 1.22 (static binary, no runtime dependencies).  
- **Inputs**: `smoke-tests.yaml` (list of test executables, env vars, timeout).  
- **Features**  
  - Parallel execution with configurable concurrency.  
  - Real‑time streaming of test output to CI logs.  
  - JUnit‑compatible XML and HTML summary generation.  
  - Exit code propagation for CI gating.  
- **Artifacts**: `bin/smoke-runner` (Linux‑amd64), `smoke-tests.yaml`.

### 5.2 Ship Script with Rollback (`ship.sh`)

- **Language**: Bash 5.2 (POSIX‑compatible).  
- **Workflow**  
  1. **Package** – Build Docker images, push to registry, generate Helm chart version.  
  2. **Deploy** – `helm upgrade --install` with `--wait` and health probes.  
  3. **Smoke** – Invoke `smoke-runner`.  
  4. **Success** – Tag release as `stable`.  
  5. **Failure** – Run `helm rollback` to previous revision, capture logs, mark CI as failed.  
- **Safety** – Uses a lock file (`/tmp/ship.lock`) to prevent concurrent deployments to the same environment.  
- **Parameters** – `ENV`, `VERSION`, `DRY_RUN`, `NO_ROLLBACK`.

### 5.3 Convex Recording (`convex-record`)

- **Implementation** – Sidecar container built from `convex/recorder:latest`.  
- **Configuration** – Environment variable `CONVEX_OUTPUT=/convex/traces/${RELEASE_TAG}`.  
- **Lifecycle** – Starts with the pod, records all inbound/outbound RPCs, writes to a shared PVC, and on pod termination uploads to S3 (`s3://mk2-artifacts/convex/${RELEASE_TAG}`).

### 5.4 Supporting Artifacts

| Artifact | Path | Description |
|----------|------|-------------|
| `bin/smoke-runner` | `artifacts/bin/` | Executable for the unified runner. |
| `smoke-tests.yaml` | `artifacts/` | Manifest of smoke test binaries. |
| `ship.sh` | `scripts/` | Deployment orchestrator. |
| `convex-record` Dockerfile | `containers/convex/` | Builds the sidecar image. |
| `release-notes.md` | `docs/` | Auto‑generated release notes with Convex trace links. |

All artifacts are version‑controlled and published to the internal artifact repository via CI.

---

## 6. Implementation Plan

| Phase | Tasks | Owner | Duration |
|-------|-------|-------|----------|
| **0 – Prep** | Create `artifacts/` layout, add CI secrets, update README. | DevOps | 1 wk |
| **1 – Smoke Runner** | - Scaffold Go module.<br>- Implement manifest parser.<br>- Parallel execution engine.<br>- Reporting (JUnit, HTML).<br>- Unit tests. | Backend Team | 2 wks |
| **2 – Ship Script** | - Write `ship.sh` skeleton.<br>- Integrate Helm deployment.<br>- Add health probes.<br>- Implement rollback logic.<br>- Add lock handling.<br>- Dry‑run validation. | Ops Team | 2 wks |
| **3 – Convex Integration** | - Build sidecar image.<br>- Modify Helm chart to inject sidecar.<br>- Configure PVC & S3 upload.<br>- Verify trace generation. | Platform Team | 2 wks |
| **4 – CI Pipeline** | - Add `make deploy` target.<br>- Wire `ship.sh` → `smoke-runner` → Convex.<br>- Store artifacts (runner binary, traces).<br>- Add badge for last deployment status. | CI Team | 1 wk |
| **5 – Migration** | - Convert existing smoke tests to binaries.<br>- Populate `smoke-tests.yaml`.<br>- Run pilot deployments on staging. | QA + Dev | 1 wk |
| **6 – Verification** | - Execute full end‑to‑end smoke on production.<br>- Simulate failures to test rollback.<br>- Review Convex trace accessibility. | QA | 1 wk |
| **7 – Documentation** | - Update `README.md`, `docs/DEPLOYMENT.md`.<br>- Conduct training session. | Docs Team | 1 wk |
| **8 – Release** | Tag `v2.0.0`, publish artifacts, announce. | Release Manager | 1 day |

**Total Estimated Time:** ~10 weeks.

---

## 7. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Rollback Failure** – Helm rollback may not revert all resources (CRDs, PVCs). | Medium | High (service outage) | - Pre‑flight snapshot of Helm release history.<br>- Store previous image tags and force‑redeploy on rollback.<br>- Automated smoke after rollback to verify health. |
| **Convex Overhead** – Sidecar may increase pod startup latency. | Low | Medium | - Benchmark sidecar start‑up; keep trace buffer size < 5 MB.<br>- Enable sidecar only on `ENV=staging|prod`. |
| **Runner Resource Exhaustion** – Parallel tests may exhaust CI runners. | Medium | Medium | - Configurable concurrency (`MAX_CONCURRENCY`).<br>- Auto‑scale CI runners based on queue length. |
| **Lock Contention** – Multiple developers triggering `make deploy` simultaneously. | Low | Low | - Central lock stored in Redis; provide clear error message and retry advice. |
| **Artifact Drift** – Mismatch between `smoke-runner` version and test binaries. | Low | Medium | - Pin runner version in `smoke-tests.yaml` via `runner_version` field.<br>- CI validates version compatibility before deployment. |
| **Security** – Storing Convex traces may expose sensitive data. | Low | High | - Encrypt traces at rest (S3 SSE‑KMS).<br>- Redact PII via Convex filter before upload. |

---

## 8. Verification & Testing

1. **Unit Tests** – `smoke-runner` unit suite (Go `testing`).  
2. **Integration Tests** – Deploy a minimal stack to a disposable namespace, run `ship.sh --dry-run`.  
3. **Smoke Suite** – Execute `make deploy` on staging; verify:  
   - All tests pass (`smoke-runner` exit 0).  
   - Deployment version is tagged `stable`.  
   - Convex traces appear in S3 and are linked in release notes.  
4. **Rollback Scenario** – Introduce a failing smoke test (e.g., break a health endpoint). Expect:  
   - `ship.sh` detects failure, triggers `helm rollback`.  
   - Post‑rollback health probes succeed.  
   - CI job fails with clear rollback log.  
5. **Performance** – Measure total deployment time; must stay < 15 min.  
6. **Load Test** – Run `make deploy` concurrently on three separate environments; ensure lock works and no cross‑environment interference.  

All verification steps are codified in `tests/verification/` and executed automatically on every PR merge to `main`.

---

## 9. Timeline & Milestones

| Milestone | Date (2026) |
|-----------|-------------|
| Architecture Sign‑off | 2026‑05‑05 |
| Smoke Runner MVP | 2026‑05‑19 |
| Ship Script MVP | 2026‑06‑02 |
| Convex Sidecar Ready | 2026‑06‑16 |
| Full CI Integration | 2026‑06‑23 |
| End‑to‑End Validation | 2026‑06‑30 |
| Production Rollout (v2.0.0) | 2026‑07‑07 |

---

## 10. Dependencies

- **Helm 3.12** – Required for `helm rollback` semantics.  
- **Kubernetes 1.28+** – Sidecar injection and PVC support.  
- **Convex SDK v0.9** – For trace collection.  
- **GitHub Actions Runner Pool** – Minimum 3 concurrent runners for parallel smoke execution.  

---

## 11. Open Issues

1. **Trace Retention Policy** – Need to define how long Convex recordings are kept.  
2. **Multi‑Region Support** – Future EPIC will extend rollback across regions.  
3. **Feature Flag for Convex** – Decide on rollout strategy (gradual vs. all‑at‑once).  

---

## 12. Approvals

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Product Owner |  |  |  |
| Engineering Lead |  |  |  |
| Platform Lead |  |  |  |
| Security Lead |  |  |  |

--- 

*End of Document*