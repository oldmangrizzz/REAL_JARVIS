# Heartbeat Tasks

- Check calendar for today and tomorrow if it has not been checked recently.
- Check urgent unread messages or email on rotation.
- Check weather only when it is likely to matter.
- If a reminder depends on presence, verify whether the user is home first.
- Use `memory/heartbeat-state.json` for last checks and once-per-day reminders.
- Respect quiet hours.
- If nothing needs attention, reply `HEARTBEAT_OK`.
