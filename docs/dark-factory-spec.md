# Spec: Dark Factory CI/CD Pipeline + Portable Personal IDE

## Objective

Complete the Dark Factory pipeline so that a new idea dropped into Obsidian flows automatically through spec generation, operator approval, task decomposition, agent execution, and completion — without operator intervention beyond approving specs. Also deploy the Portable Personal IDE so JARVIS can execute code tasks surfaced from approved specs.

**User story:** Grizz types `## idea: [description]` in the Obsidian Factory/Kanban.md on Echo, waits ~30 seconds, sees a generated spec in the APPROVE section, clicks **[APPROVE]**, and watches tasks appear in the Kanban and execute without further action. He monitors progress on his phone via Obsidian sync.

**Success criteria:**
- Submitting `## idea: Build a thing` in Kanban.md → spec appears in ≤60s
- Clicking **[APPROVE]** on a spec → ≥1 tasks created in Kanban in ≤10s
- Task created → agent claims and begins execution in ≤15s
- Task completed → status updates to ✅ in Kanban in ≤15s
- ide-executor.py running → shell/Python/Node commands execute and return output
- All 5 pipeline stages (ideas inbox, pending specs, approved, task kanban, done) render correctly in Kanban.md

---

## Tech Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| Backend | Convex (fastidious-wolverine-481) | factory.ts, meta.ts, ide.ts — already correct |
| Graph routing | Neo4j (cypher-shell) | SpikeReasoner; seeded but NOT wired in this spec (future work) |
| Kanban store | Obsidian Markdown (Factory/Kanban.md) | 10s poll interval |
| Factory agent | Python 3.14 (`dark-factory-agent-v2.py`) | Lane: Planner / Executor / Verifier / Scribe |
| Kanban poller | Node.js (`factory-kanban-poller.js`) | 10s poll interval |
| IDE executor | Python 3.14 (`ide-executor.py`) | LaunchAgent `com.grizz.jarvis.ide-executor` |
| IDE interface | Node.js (`ide-kanban-interface.js`) | Parses IDE.md checkboxes, drives ide-executor |
| Credential | CONVEX_DEPLOY_KEY | In `~/.bash_profile`; sourced by agents via `.bash_profile` |

---

## Commands

```bash
# Restart all daemons (after any config change)
pkill -f "factory-kanban-poller|dark-factory-agent-v2|ide-executor"
bash -c 'source ~/.bash_profile && nohup node ~/.jarvis/bin/factory-kanban-poller.js > /dev/null 2>&1 &'
bash -c 'source ~/.bash_profile && nohup python3 ~/.jarvis/bin/dark-factory-agent-v2.py > /dev/null 2>&1 &'
bash -c 'source ~/.bash_profile && nohup python3 ~/.jarvis/bin/ide-executor.py > /dev/null 2>&1 &'

# Verify all running
ps aux | grep -E "factory-kanban-poller|dark-factory-agent-v2|ide-executor" | grep -v grep

# Verify Convex backend
npx convex status --prod

# Tail daemon logs (if redirected to file)
tail -f ~/.jarvis/logs/factory-kanban-poller.log
tail -f ~/.jarvis/logs/dark-factory-agent.log

# Test idea submission end-to-end
npx convex run meta:submitIdea --arg '{"ideaTitle":"test","ideaDescription":"testing","ideaSource":"cli","tags":["test"]}' --prod

# View raw factory state
npx convex run factory:getFactoryStatus --prod
npx convex run meta:getIdeas --prod
npx convex run factory:getAllTasks --prod

# Test IDE executor directly
python3 ~/.jarvis/bin/ide-executor.py --test
```

---

## Project Structure

```
~/.jarvis/
├── bin/
│   ├── factory-kanban-poller.js     # Convex → Obsidian Kanban.md poller (Node.js)
│   ├── dark-factory-agent-v2.py     # Task execution agent per lane (Python 3.14)
│   ├── ide-executor.py              # Portable IDE command executor (Python 3.14)
│   └── ide-kanban-interface.js       # IDE.md checkbox → ide-executor bridge (Node.js)
├── logs/
│   ├── factory-kanban-poller.log    # Rotated log output
│   └── dark-factory-agent.log
└── launch-agents/
    ├── com.grizz.jarvis.factory-poller.plist   # Kanban poller LaunchAgent
    ├── com.grizz.jarvis.factory-agent.plist    # Dark factory agent LaunchAgent
    └── com.grizz.jarvis.ide-executor.plist    # IDE executor LaunchAgent

~/Documents/Obsidian Vault/Factory/
├── Kanban.md     # Main Dark Factory Kanban (poller writes here, operator reads)
└── IDE.md        # Portable IDE command interface (operator edits, interface parses)

~/REAL_JARVIS/convex/
├── schema.ts     # All tables (factory_tasks, factory_ideas, factory_specs, etc.) — already correct
├── factory.ts    # Task/lane mutations — already correct
├── meta.ts       # Ideas/specs mutations — already correct
└── ide.ts        # IDE command mutations — already correct
```

---

## Code Style

### Poller (factory-kanban-poller.js)
```javascript
// Convex function calls use explicit namespace prefix
// DO: runConvex("meta:getIdeas") — explicit namespace
// DO: runConvex("factory:getAllTasks") — explicit namespace
// DON'T: runConvex("getIdeas") — implicit factory: assumed

function runConvex(fn, args = "") {
  return new Promise((resolve, reject) => {
    const cmd = ["npx", "convex", "run", fn]; // fn already includes "namespace:"
    if (args) cmd.push(args);
    // ... spawn, parse JSON from stdout
  });
}

// Mutations use --json flag correctly
function runMutation(fn, args) {
  const jsonArgs = JSON.stringify(args);
  return runConvex(fn, `--json '${jsonArgs.replace(/'/g, "'\\''")}'`);
}
```

### Factory Agent (dark-factory-agent-v2.py)
```python
# Heartbeat uses correct Convex function name
self.run_convex("heartbeat", json.dumps({  # NOT "recordHeartbeat"
    "agentId": self.agent_id,
    "laneType": self.lane_type,
    ...
}))
```

### Kanban.md operator interface sections
```
## 🚀 Ideas Inbox        ← operator drops ideas here
## 📋 Specs — Awaiting Approval  ← [APPROVE] / [REJECT] links
## ✅ Approved Specs      ← auto-created after approval
## 🗂️ Task Kanban         ← tasks grouped by priority
## 📡 Agent Heartbeat     ← live agent status
```

---

## Testing Strategy

### Level 1: Convex backend (verified, no changes)
- `npx convex run meta:submitIdea ...` → idea appears in `npx convex run meta:getIdeas`
- `npx convex run meta:approveSpec ...` → spec status changes, tasks created
- `npx convex run factory:claimTask ...` → task assigned to lane
- `npx convex run factory:heartbeat ...` → agent heartbeat recorded

### Level 2: Kanban poller (primary fix target)
- Restart poller → Kanban.md updates within 15s
- Submit idea via CLI → appears in Ideas Inbox within 15s
- Approve spec via CLI → appears in Approved section within 15s
- Run factory agent → appears in Agent Heartbeat within 20s
- **Manual verification:** `grep "getIdeas\|getHeartbeats\|getPendingSpecs" ~/.jarvis/bin/factory-kanban-poller.js` returns zero false namespaces

### Level 3: Factory agent (secondary fix target)
- Agent running → heartbeat appears in `npx convex run factory:getFactoryStatus`
- Task claimed → status changes in Kanban
- Task completed → ✅ updated in Kanban

### Level 4: IDE executor
- `ide-executor.py --test` → shell command executes, output returned
- Add command to IDE.md → ide-kanban-interface.js picks it up → executes → result in IDE.md
- LaunchAgent loaded → survives session restart

### Level 5: Full pipeline E2E
1. Drop `## idea: Test E2E` in Kanban.md Ideas Inbox
2. Within 60s: spec appears in "Awaiting Approval"
3. Click **[APPROVE]** → within 30s: task appears in Task Kanban
4. Agent claims → status changes to "executing"
5. Agent completes → status changes to ✅

---

## Boundaries

### Always
- Run `npx convex deploy` after any schema change
- Test Convex mutations directly before blamed client code
- Use explicit namespace prefix on ALL Convex function calls (no implicit `factory:`)
- Restart relevant daemons after any code change
- Keep CONVEX_DEPLOY_KEY in `~/.bash_profile` (not hardcoded in scripts)

### Ask first
- Changing Convex schema.ts (backend contract)
- Changing Convex function signatures in factory.ts / meta.ts / ide.ts
- Changing the Kanban.md section structure (affects poller parsing)
- Adding new LaunchAgents or changing startup behavior

### Never
- Commit CONVEX_DEPLOY_KEY or other credentials to git
- Change the Obsidian vault path (hardcoded to `~/Documents/Obsidian Vault/Factory/`)
- Deploy without running Level 1 convex verify commands first
- Use implicit namespace in runConvex() calls

---

## Success Criteria (repeatable verification)

| # | Criterion | Verification |
|---|-----------|-------------|
| 1 | Kanban Ideas Inbox renders ideas from Convex | Drop idea via CLI; appears in Kanban.md within 15s |
| 2 | Specs section renders pending specs | Submit spec via CLI; appears in Kanban.md within 15s |
| 3 | Agent Heartbeat renders live agents | dark-factory-agent-v2.py running; `npx convex run factory:getFactoryStatus` shows it |
| 4 | **[APPROVE]** in Kanban.md triggers spec approval | Edit Kanban.md APPROVE link; Convex mutation called; spec status changes |
| 5 | ide-executor.py runs as LaunchAgent | `launchctl list \| grep ide-executor` shows loaded |
| 6 | IDE.md checkbox → execution → result | Checkbox in IDE.md → output appears in IDE.md Results |
| 7 | All 5 Kanban sections populated correctly | Ideas / Pending Specs / Approved / Task Kanban / Done — all render with real data |

---

## Open Questions

1. **IdeExecutor authentication** — ide-executor.py has a `setSecret` / `getSecret` pair (for API keys). Should secrets be stored in Convex `ide:cacheFile` or in the local macOS keychain?
2. **SpikeReasoner routing** — tasks currently assign to lanes by round-robin/simple tag match. Do you want me to spec the Neo4j routing as a second phase, or leave it as simple tag-based for now?
3. **APPROVE/REJECT mechanism** — the APPROVE links in Kanban.md are Markdown links. Since Obsidian doesn't execute JavaScript, these need to be either (a) Obsidian custom commands, (b) operator manually runs a CLI command, or (c) we use a templater script. What interaction model do you want?
4. **Dark Factory E2E spec generation** — the pipeline as designed expects an agent to generate specs from ideas. Is this a Claude Code subagent? A Python daemon? Or is spec generation out of scope for this spec (manual spec authoring)?
