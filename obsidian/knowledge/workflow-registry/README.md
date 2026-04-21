# Workflow Registry (n8n)

Each workflow Jarvis's dark factory operates. One MD file per workflow with:
- Purpose
- Trigger (cron / webhook / HA state)
- Inputs / outputs
- Failure mode
- n8n export JSON path

## Categories
- **self-healing/** — monitor + restart services
- **smart-home/** — device control
- **evolutionary-build/** — forge orchestration, self-update
- **briefing/** — operator daily / weekly reports
