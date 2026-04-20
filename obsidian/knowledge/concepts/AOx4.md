# A&Ox4 — Alert & Oriented ×4

**Source of truth:** `PRINCIPLES.md §3`, `VERIFICATION_PROTOCOL.md §1.5`
**Class:** Clinical consciousness probe, ported from EMS primary-assessment doctrine.

---

## What it is

In the field, a paramedic confirms a patient is *oriented* on four axes:

| Axis   | Clinical meaning                               | JARVIS-side probe |
|--------|-----------------------------------------------|-------------------|
| Person | Who am I, who is speaking, whose authority?  | `probePerson()`   |
| Place  | Where am I running, what surface, what net?  | `probePlace()`    |
| Time   | What is now, what does the monotonic clock say? | `probeTime()`  |
| Event  | What is happening, what task, what context?  | `probeEvent()`    |

A fully-oriented patient is **A&Ox4**. Drop a probe, you drop a level: A&Ox3, A&Ox2, etc.

## How JARVIS uses it

- Every probe returns a confidence in `[0, 1]` plus a non-null payload.
- **Threshold (default): 0.75.** Below threshold on any axis → node enters `degraded_A&Ox<N>` state.
- **While degraded, no output, no action, no speech is permitted** — except the single act of **reporting the disorientation**. This is the clinical standard: you don't have the patient drive home; you document the level and work the protocol that matches it.
- Probe results are appended to the `aox4_probes` telemetry table (see [[codebase/modules/Telemetry]]).

## Where it shows up

- **[[architecture/SOUL_ANCHOR_DEEP_DIVE|Soul Anchor]] verification:** any signature failure collapses the system to `A&Ox3: loss of Event orientation` until the operator explicitly acknowledges and re-lockdown occurs (`SOUL_ANCHOR.md §3.2`, `§7`).
- **[[concepts/Voice-Approval-Gate|Voice-Approval-Gate]]:** an unapproved rendering attempt collapses A&Ox.
- **Bootstrap gate:** `JarvisCore.bootstrap()` runs all four probes before accepting any other call.
- **Phase reports:** every `.jarvis/phase_reports/phase-<N>.json` records the A&Ox4 probe results at report time.

## Why the paramedic analogy

This repo runs the [[concepts/Digital-Person|delegated-practice]] model (`PRINCIPLES.md §1.3`): the operator writes the standing orders, JARVIS exercises independent judgment inside them, and escalates when the call is about to exceed protocol. A&Ox4 is the *precondition* for any such judgment — a disoriented medic doesn't treat patients, and a disoriented node doesn't speak, act, or mutate memory. The probe is the gate that makes "operator ON the loop" tolerable instead of reckless.

## Related

- [[concepts/NLB]], [[concepts/Voice-Approval-Gate]] — other hard boundaries that collapse A&Ox on violation.
- [[codebase/modules/Telemetry]] — where probe records land.
- [[architecture/TRUST_BOUNDARIES]].
