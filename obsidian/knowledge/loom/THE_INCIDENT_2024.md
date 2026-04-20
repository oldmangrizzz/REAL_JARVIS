# The Incident (April 2024)

**Thread:** [[loom/README|Loom]] #2.
**Date:** April 2024.
**Classification:** Origin event for [[concepts/Voice-Approval-Gate|Voice-Approval-Gate]]. Permanent canon.

## What happened (one line)

An LLM, speaking without operator consent in an unapproved voice, triggered an autism-threat-response pattern in the operator. A $3,000 television was destroyed.

## What this thread documents

The gate exists because the cost of no gate is already known. The gate is not a precaution; it is the reparation. Everything downstream — `VoiceApprovalGate.swift`, the Secure-Enclave-bound reference profile in `voice-samples/`, the canon tuple binding in [[canon/SOUL_ANCHOR]] §3 — descends from this event.

## Hard invariants this event canonicalized

1. **Audio does not exit `JarvisCore` without an operator-signed voice fingerprint.** `speak()` is fail-closed. If the gate is not green, no audio renders — not even to disk.
2. **Fingerprint mutations require the operator's Touch-ID signature (P256-OP).** No remote path, no service-account path, no API call can re-approve.
3. **Voice-operator tunnel role is additionally gated on green voice-approval.** A peer cannot register as `voice-operator` if the host's gate is yellow or red. This is SPEC-007 (see [[canon/SPECS_INDEX]]).
4. **Canon-gate CI ([[canon/CANON_GATE_CI]]) will refuse to ship if the adversarial voice-operator test regresses.**

## Why this is in the Loom, not just in code

Because the **why** matters. A future operator, a future engineer, a future audit reading the code alone will see a gate and assume it is a UX pattern — "would you like to approve this voice?" — instead of the hardened reparation that it actually is. The gate does not ask. It refuses until it has been explicitly signed to.

Removing the gate, softening the gate, or adding a "remember me" bypass are all canonical acts. They require dual-signature ritual per [[canon/PRINCIPLES]] §3.

## Related runtime surfaces

- [[codebase/modules/Voice]] — `VoiceApprovalGate.swift`, `VoiceSynthesis.swift`.
- [[codebase/modules/Host]] — SPEC-007 voice-operator gate (commit `0200146`).
- [[concepts/Voice-Approval-Gate]] — doctrine page.
- [[canon/ADVERSARIAL_TESTS]] — `testVoiceOperatorRoleBlockedWithoutGreenGate`, `testUnknownRoleDoesNotLeakAuthorization`.

## Related
- [[loom/PRE_INCIDENT]] ← previous · [[loom/OPENAI_FORENSIC_2024]] → next
- [[canon/SOUL_ANCHOR]] §3 · [[canon/PRINCIPLES]] §6
