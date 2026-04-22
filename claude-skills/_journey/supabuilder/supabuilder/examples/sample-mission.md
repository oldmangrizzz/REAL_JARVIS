# Sample Mission: Add Sharing Feature

This walkthrough shows a `new-feature` mission flowing through the Supabuilder pipeline with file-based handoffs.

---

## 1. User Initiates

> "I want users to be able to share milestone photos with family members"

## 2. Orchestrator Routes

The orchestrator classifies this as `new-feature` (Group 2) and creates:

```
supabuilder/missions/2026-04-10_new-feature_milestone-sharing/
├── mission.json
├── journal.md
├── _overview.md
├── strategy/
├── specs/
├── prototypes/
├── diagrams/
```

**mission.json:**
```json
{
  "id": "2026-04-10_new-feature_milestone-sharing",
  "type": "new-feature",
  "status": "active",
  "created": "2026-04-10",
  "current_agent": "strategist",
  "current_phase": "think",
  "pipeline": ["strategist", "pm", "designer", "pm", "architect", "techpm", "build", "qa"],
  "decisions": [],
  "ticket_tracker": null
}
```

## 3. Strategist — Think Phase

**NEXT_PHASE.md:**
```markdown
## Current Phase
Agent: strategist
Phase: think
Mission: 2026-04-10_new-feature_milestone-sharing
Pipeline position: 1/8 — strategist
Status: active

## Context
User wants to add milestone photo sharing with family members.
No existing strategy docs — first time using Supabuilder on this project.
Product wiki: supabuilder/product-wiki/
```

The Strategist boots, reads CLAUDE.md for its identity, reads NEXT_PHASE.md, and begins:
- Interviews the user about product vision and sharing context
- Researches competitive landscape (how other apps handle sharing)
- Explores 2-3 strategic directions (link sharing vs in-app sharing vs social integration)
- Presents recommendation to user → user approves

## 4. Strategist — Deliver Phase

Strategist produces `strategy/strategic-brief.md` and updates:

**handoff.md:**
```markdown
## Latest Handoff
From: strategist
Mission: 2026-04-10_new-feature_milestone-sharing
Phase completed: deliver

## Summary
Evaluated 3 sharing approaches. Recommended link-based sharing for v1 (simplest, widest reach).

## Deliverables
- missions/2026-04-10_new-feature_milestone-sharing/strategy/strategic-brief.md
- missions/2026-04-10_new-feature_milestone-sharing/diagrams/sharing-strategy.excalidraw

## Decisions
- Link-based sharing chosen over in-app (lower complexity, no auth needed for recipients)
- Social media integration deferred to v2

## Flags
- None

## For Next Agent
PM should scope the link sharing flow: generation, expiration, permissions, recipient experience.
```

**NEXT_PHASE.md** updated to: `Agent: pm, Phase: think`

User reviews and confirms → pipeline advances.

## 5. PM First Pass — Think + Deliver

PM boots, reads handoff, interviews user about sharing requirements:
- Who can share? (all users or specific roles)
- What can be shared? (individual photos, albums, milestones)
- Recipient experience (view only? comment? download?)
- Privacy controls (expiration, revocation)

Produces `specs/product-brief.md` with user stories, scope (in/out/later), success definition.

**handoff.md** updated. **NEXT_PHASE.md** → `Agent: designer, Phase: think`

## 6. Designer — Think + Deliver

Designer boots, reads product brief, explores:
- Variation A: share button on each photo → link modal
- Variation B: bulk share from album view → recipients list
- Variation C: share milestone card (curated view with multiple photos)

Produces HTML/CSS prototypes in `prototypes/`, enriches product brief with UX perspective.

**handoff.md** updated. **NEXT_PHASE.md** → `Agent: pm, Phase: think` (second pass)

## 7. PM Second Pass — Requirements

PM boots, reads Designer's prototypes and enriched brief. Writes `specs/requirements.md` with:
- Detailed functional requirements referencing prototype screens
- Acceptance criteria for each requirement
- Edge cases: expired links, revoked access, deleted photos

**handoff.md** updated. **NEXT_PHASE.md** → `Agent: architect, Phase: think`

## 8. Architect — Think + Deliver

Architect boots, reads requirements and prototypes. Produces:
- `specs/architecture.md` — sharing service design, link token model, permission system
- `specs/data_models.md` — ShareLink entity, permissions, expiration
- `specs/development-plan.md` — 3 vertical slices ordered by dependency

**handoff.md** updated. **NEXT_PHASE.md** → `Agent: techpm, Phase: think`

## 9. TechPM — Think + Deliver

TechPM boots, runs spec consistency check (requirements ↔ architecture ↔ prototypes), then creates:
- `specs/tickets.json` with 3 waves, 8 tickets total
- Wave 0: Foundation (share link model + API)
- Wave 1: Share flow (UI + backend + link generation)
- Wave 2: Recipient experience (public view page)

**handoff.md** updated. **NEXT_PHASE.md** → `Build phase`

## 10. Build Phase

Orchestrator executes tickets sequentially:
1. Ticket 0.1: Create ShareLink model → dev agent builds
2. Ticket 0.2: Create sharing API endpoints → dev agent builds
3. **Checkpoint (qa+user):** QA tests foundation against specs → findings routed
4. Ticket 1.1: Share button UI → dev agent builds
5. Ticket 1.2: Link generation flow → dev agent builds
6. **Checkpoint (qa+user):** QA tests share flow → user reviews
7. Ticket 2.1: Public recipient view → dev agent builds
8. **Checkpoint (qa+user):** QA tests full feature → final user review

## 11. Completion

All tickets done, all QA findings resolved. Orchestrator:
1. Updates `product-wiki/overview.md` — adds sharing capability to History
2. Updates `code-wiki/README.md` — adds sharing module to History
3. Updates `state.json` — clears active mission
4. Updates `memory.md` — "Sharing feature shipped. Link-based approach. Social deferred to v2."
5. Suggests: "Natural next mission: add sharing analytics or social media integration?"

---

## Key Takeaway

The entire flow is coordinated through `NEXT_PHASE.md` and `handoff.md`. No chat history dependency. Any agent can boot cold, read these files, and be productive immediately.
