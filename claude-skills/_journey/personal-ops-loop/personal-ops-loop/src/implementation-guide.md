# Implementation Guide

Use this guide to adapt Personal Ops Loop to a real environment.

## 1. Heartbeat design

Keep `HEARTBEAT.md` short.
A good heartbeat file names a few checks and the exact conditions for reminders.

Avoid:
- giant omnibus checklists
- vague goals like "be proactive"
- reminders with no state tracking rule

## 2. State tracking

Store durable reminder/check state in `memory/heartbeat-state.json`.

Recommended patterns:
- date string per recurring reminder key for once-per-day suppression
- timestamps for rotating checks such as calendar, weather, or inbox

## 3. Memory model

Use:
- `memory/YYYY-MM-DD.md` for raw context and daily notes
- `MEMORY.md` for durable user facts, preferences, and standing rules

Promote information only when it will likely matter again.

## 4. Presence signals

If presence exists, pick one default source of truth such as a person entity or device tracker.
Use it to decide relevance, not to create extra narration.

## 5. Channel behavior

In direct messages:
- allow warmer tone
- permit slightly more initiative
- keep replies concise

In shared chats:
- avoid answering everything
- contribute only when helpful
- prefer lightweight acknowledgement where supported

## 6. Approval boundaries

Require confirmation before:
- contacting third parties
- publishing links or content publicly
- sending final messages on the user's behalf
- destructive file or system changes

## 7. Maintenance

Every few days, review recent daily notes and promote durable facts into long-term memory.
Prune stale long-term notes that are no longer relevant.
