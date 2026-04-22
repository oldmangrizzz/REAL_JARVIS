# OPERATOR_ACTIONS.md
**Classification:** Operational Procedures  
**Last Updated:** 2026-04-21  
**Status:** READY FOR OPERATOR REVIEW & EXECUTION  

---

## Executive Summary

This document lists all manual/human actions required before JARVIS can enter production lockdown. All development and integration work (C1-C6, H1) is **COMPLETE**. Remaining items require operator decision or execution.

**Zero updates will be provided until task completion** — per initial instructions.

---

## 1. Credentials Rotation (C2.6)

### Overview
Fifteen secrets from `.env` require rotation before production. Each credential must be:
1. Generated/refreshed in source system
2. Rotated to production values
3. Revoked from old systems
4. Stored in operator's password manager for reference

### Credentials to Rotate

| # | Credential | Source | Status | Rotation Steps |
|---|-----------|--------|--------|-----------------|
| 1 | `JARVIS_ECHO_PASSWORD` | macOS Account | PENDING | Change password; update .env |
| 2 | `JARVIS_ALPHA_SSH_KEY` | ~/.ssh/id_rsa | PENDING | Generate new; distribute to Alpha; revoke old |
| 3 | `JARVIS_DELTA_ADMIN_TOKEN` | Delta API | PENDING | Generate in panel; revoke old token |
| 4 | `JARVIS_CHARLIE_API_KEY` | Charlie VPS | PENDING | Regenerate in dashboard; revoke old |
| 5 | `JARVIS_BETA_SSH_KEY` | ~/.ssh/id_rsa | PENDING | Generate new; add to Beta authorized_keys |
| 6 | `JARVIS_FOXTROT_SSH_KEY` | Beta/Foxtrot | PENDING | Generate new; distribute to Foxtrot |
| 7 | `CONVEX_DEPLOY_KEY` | Convex project | PENDING | Generate in settings; save securely |
| 8 | `N8N_API_KEY` | n8n instance | PENDING | Regenerate in n8n; update workflows |
| 9 | `MAPBOX_TOKEN` | Mapbox account | PENDING | Rotate in dashboard |
| 10 | `HA_LONG_LIVED_TOKEN` | Home Assistant | PENDING | Generate in settings |
| 11 | `LETTA_API_KEY` | Letta service | PENDING | Rotate in project settings |
| 12 | `OLLAMA_GATEWAY_TOKEN` | Ollama Max gateway | PENDING | Regenerate in config |
| 13 | `NTFY_API_KEY` | ntfy service | PENDING | Rotate if applicable; revoke old |
| 14 | `GCP_MONITOR_SA_KEY` | GCP service account | PENDING | Regenerate and revoke old |
| 15 | `GITHUB_ACTIONS_TOKEN` | GitHub PAT | PENDING | Regenerate in GitHub; revoke old |

### Rotation Procedure (for each credential)

1. **Generate new value** in source system
2. **Test new value** with source service to confirm validity
3. **Update .env** with new value
4. **Verify deployment** by running smoke tests (DEPLOY.md §7)
5. **Revoke old value** in source system
6. **Document rotation timestamp** in password manager

**Estimated time:** ~2 hours (0.5-5 min per credential depending on system)

---

## 1.1 Git History Secret Exposure Check (C2.2 & C2.3)

### Status: CLEAN ✅

**C2.2 — `.env` history:**
```bash
$ git log --all --full-history -- .env
(no commits found)
```
**Result:** `.env` has never been committed to git history. No secrets exposure.

**C2.3 — `.jarvis/voice-bridge.env` history:**
```bash
$ git log --all --full-history -- .jarvis/voice-bridge.env
(no commits found)
```
**Result:** `.jarvis/voice-bridge.env` has never been committed. Clean.

**Conclusion:** No operator action required. Both secrets files are properly excluded and have no historical exposure.

---

## 2. Open CRITICAL Findings (Red-Team Remediation)

### Blockers: 3 CRITICAL Items Requiring Fix or Acceptance

Per CRITICAL_HIGH_AUDIT.md, three CRITICAL items are pending:

| ID | Finding | File | Status | Recommended Action |
|----|---------|------|--------|-------------------|
| **CRITICAL-001J** | MasterOscillator onTick Concurrency | `Oscillator/MasterOscillator.swift:185` | Code appears correct; comment mismatch | Update comments OR add test to verify |
| **CRITICAL-002J** | PheromindEngine Data Race | `Pheromind/PheromoneEngine.swift:40-133` | A&Ox4 gate in place; needs lock audit | Audit all state access; replace with actor if feasible |
| **CRITICAL-003J** | RLMBridge Shell Injection | `RLM/PythonRLMBridge.swift` | stdin pipe fix in place; needs verification | Run integration test with special chars |

### Decision Required
For each CRITICAL item, operator must:
- ✅ **ACCEPT** — If code review and/or tests confirm safety
- ❌ **REQUIRE FIX** — If unacceptable, submit to engineering

**Acceptance evidence must be documented** (e.g., test run output, code review notes).

---

## 3. Letta Exclusivity Verification (H2)

### Requirement
Per PRINCIPLES.md §1.1 (Natural Language Barrier): JARVIS's memory/cognitive substrate **must be exclusive** to Jarvis. No shared weights, memory, or model state with other personas/agents.

### Verification Checklist

- [ ] **LXC Container 201 (Letta)** is JARVIS-exclusive
  - Confirm via Proxmox: `pveam list | grep 201`
  - Verify no other projects/users can access
  - Document container ID in `.jarvis/secrets/letta-exclusivity.txt`

- [ ] **Ollama Gateway** (Delta:8787) serves only JARVIS models
  - Check `/opt/ollama-gateway/config.json` for whitelisted models
  - Verify model list includes only JARVIS-sanctioned models
  - Document in `.jarvis/secrets/ollama-exclusivity.txt`

- [ ] **Convex Project** (jarvis-forge-e5b07) is JARVIS-exclusive
  - Verify no shared documents with other projects
  - Check project access controls in Convex dashboard
  - Document project ID in `.jarvis/secrets/convex-exclusivity.txt`

**Deliverable:** Three `.txt` files (chmod 600) documenting exclusivity.

---

## 4. Canonical Document Signing (H1)

### Overview
PRINCIPLES.md, SOUL_ANCHOR.md, and VERIFICATION_PROTOCOL.md must be co-signed with both P-256 (Secure Enclave operational root) and Ed25519 (cold root) keys before lockdown.

### Prerequisites
Keys must exist at `~/.jarvis/keys/`:
- `p256_public.pem` (Secure Enclave public key)
- `p256_private.pem` (P-256 private key)
- `ed25519_public.pem` (Ed25519 public key)
- `ed25519_private.pem` (Ed25519 private key)

If keys do not exist, generate them:
```bash
scripts/generate_soul_anchor.sh
```

### Signing Procedure

For each canonical document:

```bash
scripts/sign_dual.sh PRINCIPLES.md
scripts/sign_dual.sh SOUL_ANCHOR.md
scripts/sign_dual.sh VERIFICATION_PROTOCOL.md
```

**Output:** Six signature files with `.p256.sig` and `.ed25519.sig` extensions

### Verification

After signing, verify signatures are valid:

```bash
scripts/verify_dual_sig.sh PRINCIPLES.md
scripts/verify_dual_sig.sh SOUL_ANCHOR.md
scripts/verify_dual_sig.sh VERIFICATION_PROTOCOL.md
```

**Expected output:** `✓ Dual signatures verified successfully` for each file.

### Post-Signing Checklist
- [ ] All 6 signature files created
- [ ] All 3 verification commands passed
- [ ] Commit signature files to main branch
- [ ] CI workflow (`.github/workflows/canon-gate.yml`) passes

---

## 5. Convex Configuration (TBD Fields)

### Missing Information

The following fields in `convex.json` and `DEPLOY.md` require operator input:

| Field | Location | Description |
|-------|----------|-------------|
| **Convex Team ID** | `convex.json:team` | From Convex dashboard → Team Settings |
| **Convex Project ID** | `convex.json:project` | E.g., "jarvis-forge-e5b07" |
| **Convex Prod URL** | `convex.json:prodUrl` | Production deployment URL |
| **Convex Dev URL** | `convex.json:devUrl` | Development/local deployment URL |
| **HA Token** | `DEPLOY.md §1.3` | Home Assistant long-lived token |

### Steps to Complete

1. Log in to https://dashboard.convex.dev
2. Navigate to project "jarvis-forge-e5b07"
3. Copy team ID, project ID, and URLs
4. Edit `convex.json` with actual values
5. Edit `DEPLOY.md` with Home Assistant token location
6. Commit changes:
   ```bash
   git add convex.json DEPLOY.md
   git commit -m "config: fill Convex and Home Assistant details"
   ```

### Verification
After filling in values, run deployment dry-run:
```bash
bash scripts/deploy-dry-run.sh
```

---

## 6. Home Assistant Integration Setup

### Long-Lived Token Creation

1. **Access Home Assistant UI**
   - Navigate to http://192.168.7.199:8123
   - Log in with admin user (grizz)

2. **Generate Token**
   - Click user icon (top-right)
   - Select "Create token"
   - Copy token value (displayed once)

3. **Store Securely**
   - Save to `~/.copilot/session-state/<session-id>/files/ha.env`
   - Format: `HA_LONG_LIVED_TOKEN="<token-value>"`
   - Permissions: `chmod 600`

4. **Verify Connection**
   - Run test command from Delta:
     ```bash
     curl -H "Authorization: Bearer $HA_LONG_LIVED_TOKEN" \
       http://192.168.7.199:8123/api/
     ```
   - Expected: `{"message":"API running"}`

---

## 7. Remaining Hardening Items (H3-H11)

The following hardening items are pending but do NOT block production:

| ID | Task | Priority | Status |
|----|------|----------|--------|
| H3 | CircuitBreaker.swift + RetryPolicy.swift | HIGH | Pending |
| H4 | Wrap Letta/n8n/Convex/Mapbox clients | HIGH | Pending |
| H5 | Replace hardcoded Delta IPs with env vars | HIGH | Pending |
| H6 | PWA SHARED_SECRET hardening | HIGH | Pending |
| H7 | Mesh display URL allowlist | HIGH | Pending |
| H8 | jarvis-node.service exponential backoff | MEDIUM | Pending |
| H9 | Memory graph eviction policy audit | MEDIUM | Pending |
| H10 | Test count reconciliation | LOW | Pending |
| H11 | Hygiene: move .md files to docs/history | LOW | Pending |

**These items can be scheduled post-launch.**

---

## 8. Production Lockdown Checklist

Before running `jarvis-lockdown`, operator must verify:

### Pre-Flight Verification
- [ ] All 15 credentials rotated and stored securely
- [ ] All 3 CRITICAL findings accepted OR fixed
- [ ] Letta/Ollama/Convex exclusivity verified
- [ ] Canonical documents signed (6 `.sig` files created)
- [ ] Convex/Home Assistant configuration complete
- [ ] Git state: all commits pushed to main, no uncommitted changes
- [ ] Tests pass: `swift test` executes without failures
- [ ] Smoke tests pass: DEPLOY.md §7 all checks green

### Lockdown Invocation
```bash
scripts/jarvis-lockdown
```

**Output:** `.jarvis/soul_anchor/genesis.json` created with dual signatures.

### Post-Lockdown Verification
- [ ] `.jarvis/soul_anchor/genesis.json` exists with both signatures
- [ ] CI workflow `canon-gate.yml` passes
- [ ] Voice canon test: `~/.jarvis/alignment_tax/voice_canon_failures.log` is empty
- [ ] Bootstrap test: `JarvisCore.bootstrap()` succeeds with genesis verification

---

## 9. Communication & Support

### Questions or Blockers?
- **Red-team findings**: Refer to CRITICAL_HIGH_AUDIT.md + REDTEAM_TRIAGE.md
- **Deployment issues**: See DEPLOY.md troubleshooting section
- **Credential rotation**: Contact relevant service administrators
- **Key generation**: See SOUL_ANCHOR.md §4

### Completion Report
Once all items are complete:

```bash
cat > /tmp/completion_report.txt << 'EOF'
OPERATOR_ACTIONS.md Completion Report
======================================

Credentials Rotated: __/__  (count)
CRITICAL Findings Status: [ ] Accepted [ ] Fixed
Letta Exclusivity: [ ] Verified
Canonical Docs Signed: [ ] Complete
Convex Config: [ ] Complete
Home Assistant Token: [ ] Stored
Pre-Flight Checks: [ ] All Passed
Lockdown Invocation: [ ] Complete
Post-Lockdown Verification: [ ] All Passed

Timestamp: ______________________
Operator Signature: ______________
EOF
```

---

## References

- **DEPLOY.md** — Comprehensive deployment runbook
- **REDTEAM_TRIAGE.md** — Red-team findings triage matrix
- **CRITICAL_HIGH_AUDIT.md** — CRITICAL/HIGH fix verification
- **PRINCIPLES.md** — JARVIS governance and operational consciousness
- **SOUL_ANCHOR.md** — Cryptographic identity binding
- **VERIFICATION_PROTOCOL.md** — Integrity verification procedures

---

**Status:** READY FOR OPERATOR EXECUTION  
**Next Step:** Execute credential rotation (Section 1) → verify findings (Section 2) → sign docs (Section 4) → run lockdown (Section 8)  
**Estimated Time to Completion:** 3-4 hours (depends on credential rotation speed)

---

## APPENDIX H5: Delta IP Configuration Audit

### Summary

**Audit Date:** 2026-04-21  
**Audit Scope:** All hardcoded IP literals matching cluster node addresses  
**Finding:** `services/voice_canon_validator.py` already uses env var pattern (`JARVIS_DELTA_HOST`).

### Audit Results

Full codebase scan for hardcoded IP literals:

```
grep -rEn "\b(192\.168\.4\.(100|151|152)|192\.168\.7\.(114|199)|76\.13\.146\.61|187\.124\.28\.147)\b"
```

**Codebase entries (deployable code):**

| File | Line | Pattern | Status | Rationale |
|------|------|---------|--------|-----------|
| `Jarvis/Sources/JarvisCore/ControlPlane/MyceliumControlPlane.swift` | 36 | `192.168.4.151` default | ✓ ENV-COMPLIANT | Already uses `JARVIS_CONTROL_HOST` env var with fallback |
| `services/jarvis-linux-node/jarvis_node.py` | 95 | `192.168.7.114` default | ✓ ENV-COMPLIANT | Already uses `JARVIS_HOST_ADDR` env var with fallback |
| `scripts/mesh-unity-build.sh` | 10-11 | `192.168.4.100/151` defaults | ✓ ENV-COMPLIANT | Already uses `ALPHA_IP`/`BETA_IP` env vars with fallbacks |
| `services/voice_canon_validator.py` | 67 | Delta host | ✓ ENV-COMPLIANT | Uses `JARVIS_DELTA_HOST` env var (no hardcoded IP) |

**Non-deployable entries (excluded from remediation):**

| Category | Files | Rationale |
|----------|-------|-----------|
| Test fixtures | `Jarvis/Tests/JarvisCoreTests/MeshDisplayDispatcherTests.swift` | IP `192.168.4.100` in test data; acceptable for unit test constant |
| Documentation / comments | `scripts/seed_letta_persona.py` lines 557-576 | Node topology reference; documentation-only, no effect on deployment |
| IDE development settings | `.claude/settings.local.json` | Developer shell commands; environment-specific, no production impact |
| Runtime state / knowledge graphs | `.jarvis/storage/knowledge-graph.json`, `.jarvis/capabilities.json` | Generated runtime data; regenerated on each boot |
| Infrastructure config | `nextcloud-alpha-setup/traefik-config.yml`, `n8n/workflows/*.json` | Infrastructure declarations; owner's responsibility |
| HomeKit metadata | `xr.grizzlymedicine.icu/homekit-bridge-status.json`, `obsidian/.obsidian/plugins/*/data.json` | Device state snapshots; transient |

### Acceptance Criteria Met

✅ No hardcoded IP literals in `services/voice_canon_validator.py`  
✅ All deployable code uses env var patterns with sensible defaults  
✅ `JARVIS_DELTA_HOST` defined in `.env.example`  
✅ `JARVIS_DELTA_HOST` documented in `DEPLOY.md` § Environment Variables  
✅ Complete audit documented  

### Operator Actions Required

**None.** H5 is fully compliant. The codebase already uses environment variables for all node addresses in deployable code.

