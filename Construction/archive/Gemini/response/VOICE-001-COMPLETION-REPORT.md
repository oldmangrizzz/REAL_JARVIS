# [VOICE-001] F5-TTS Migration & Hardening Completion Report

**Status:** COMPLETE (Production Combat Ready)
**Priority:** P0
**Canon Version:** persona-frame-v3-f5tts-cfg2.0-nfe32

## 1. Executive Summary
The JARVIS voice pipeline has been successfully migrated from the unstable VibeVoice-1.5B model to the F5-TTS (SWivid) engine. This transition delivers sub-realtime latency on T4 hardware, superior prosody, and English-stable zero-shot cloning. Beyond the baseline migration, the system has undergone Operation [F5-FRACTURE] (Red Team assessment), resulting in significant hardening of the service layer and watchdog automation.

## 2. Hardened Architecture (Final State)
| Layer | Component | Status | Hardening Measures |
|---|---|---|---|
| **Service** | `services/f5-tts/` | **ACTIVE** | 2MB Base64 payload capping; UUID-based file isolation; singleton-safe threading. |
| **Automation** | `scripts/tts-watchdog.sh` | **ACTIVE** | Atomic env updates; strict variable validation; launchd integration. |
| **Logic** | `JarvisCore/Voice/` | **UPDATED** | `persona-frame-v3` bump; auto-selection of `f5ttsLocked` parameters. |
| **Gate** | `VoiceApprovalGate` | **RESET** | `approval.json` wiped; re-audition mandatory per canon safety rules. |

## 3. Red Team Assessment & Remediation (Op [F5-FRACTURE])
*   **Vulnerability:** DoS via Base64 Buffer Bloat.
    *   **Fix:** Enforced `max_length=2097152` on `reference_audio_b64` in `app.py`.
*   **Vulnerability:** Identity Swap via Temporary File Collision.
    *   **Fix:** Switched from PID/Time-based naming to `uuid.uuid4()` for all materialized reference WAVs.
*   **Vulnerability:** "Silent Death" in Watchdog State Drift.
    *   **Fix:** Added multi-variable sanity checks before `tts.env` modification to prevent bridge-disablement on network/CLI failure.

## 4. Deploy Runbook
### First-Time Bring-up
```bash
# 1. CD to service
cd services/f5-tts/

# 2. Build & Push (ensure GCP_PROJECT_ID is set)
docker build -t "us-central1-docker.pkg.dev/$GCP_PROJECT_ID/jarvis/f5-tts:latest" .
docker push "us-central1-docker.pkg.dev/$GCP_PROJECT_ID/jarvis/f5-tts:latest"

# 3. Fire-up Instance
./deploy/gcp-up.sh
```

### Day-to-Day Operation
*   The watchdog `scripts/tts-watchdog.sh` (driven by launchd) handles IP discovery, bearer retrieval from Secret Manager, and voice-bridge restarts automatically.

## 5. Audition + Approval Flow (Action Required)
Since the voice fingerprint has changed, the Operator MUST re-audition to unblock the `/speak` path:
1.  **Audition:** `Jarvis voice-audition "System identity confirmed. Transition to F5-TTS complete."`
2.  **Verify:** Listen to the generated WAV in `.jarvis/voice/auditions/`.
3.  **Approve:** `Jarvis voice-approve grizzly "f5-tts matrix-01 2026-04-20"`

## 6. Test Evidence
*   **Unit Tests:** 3 new tests in `F5TTSBackendTests.swift` (parameter mapping, payload building, pipeline selection).
*   **Canon Gate:** Test floor bumped to **222** tests. No regressions in legacy suites.

## 7. Rollback Plan
To revert to VibeVoice in <5 min:
1.  `cd services/vibevoice-tts/ && ./deploy/gcp-up.sh`
2.  Point `scripts/tts-watchdog.sh` constants back to `jarvis-vibevoice-t4`.
3.  Restart watchdog.

---
**Turnover complete.** Ready for PM notification.
