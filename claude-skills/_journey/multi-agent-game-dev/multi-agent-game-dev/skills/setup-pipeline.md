# Setup Pipeline

> **Doc version:** 2026.04.05

## Goal
Scaffold the complete multi-agent game dev pipeline for a new or existing project. Creates all directory structures, template files, and durable memory with sensible defaults.

## When to Use
- Starting a new project that will use multi-agent development.
- Retrofitting an existing project with the pipeline structure.
- A user says "set up the multi-agent pipeline" or "initialize agents."

## Inputs
- `PROJECT_NAME`: Full project name (e.g. "Mr. Baseball Dynasty")
- `PROJECT_ACRONYM`: Short code (e.g. "MBD")
- `REPO_PATH`: Relative path to git repo from project root (e.g. "mr-baseball-dynasty")
- `AGENT_CONFIG`: Optional override for which platforms fill which roles.

## Steps

1. Confirm the project root directory. If it does not exist, create it.

2. Create the durable memory directory:
   ```
   mkdir -p .codex/<ACRONYM>
   ```

3. Create CLAUDE.md at project root with role definitions:
   ```markdown
   # Agents — <PROJECT_NAME>

   ## Team

   | Agent | Role | Platform |
   |-------|------|----------|
   | Architect | Game Design, feature specs, phase planning | ChatGPT |
   | Builder | Implementation, tests, feature branches | Codex |
   | Reviewer | PR review, regression checks, type safety | Claude Code |
   | Operations | Git ops, memory, sprint log, deploys | Claude Opus |

   ## Workflow
   Sequential: **Architect -> Builder -> Reviewer -> Operations**

   All coordination happens through files. No chat handoffs.

   ## Boot Sequence
   Every new session:
   1. Read `.codex/<ACRONYM>/status.md`
   2. Read `.codex/<ACRONYM>/handoff.md`
   3. Read `CLAUDE.md`
   4. Verify repo state (branch, tests, clean tree)
   5. Read `NEXT_TASK.md`
   6. Begin work within your role

   ## Collaboration Rules
   1. Read before editing
   2. Check your role — stay in scope
   3. Feature branches only, never commit to main
   4. Verify before committing (tests + typecheck + build)
   5. Update .codex/ memory after every session
   6. Stage files explicitly, never `git add -A`
   ```

4. Create CLAUDE.md at project root (for Claude-family agents):
   ```markdown
   # <PROJECT_NAME>

   ## Quick Orientation
   - Multi-agent AI development project with 4 agents
   - Git repo at `<REPO_PATH>/`
   - One task at a time via `NEXT_TASK.md`
   - Shared memory in `.codex/<ACRONYM>/`

   ## Read First
   1. `.codex/<ACRONYM>/status.md` — current state
   2. `.codex/<ACRONYM>/handoff.md` — last session
   3. `CLAUDE.md` — roles and rules
   4. `NEXT_TASK.md` — active task

   ## Hard Constraints
   - Tests must pass before and after every change
   - No changes outside current task scope
   - Update .codex/ memory before ending session
   ```

5. Create NEXT_TASK.md:
   ```markdown
   # Next Task

   ## INIT-001: Pipeline Setup Complete
   **Owner:** Operations
   **Status:** done

   Pipeline initialized. Architect: define the first real task.
   ```

6. Create BACKLOG.md:
   ```markdown
   # Backlog — <PROJECT_NAME>

   Priority-ordered. Architect moves items to NEXT_TASK.md.

   ## Queue
   <!-- Add tasks here as they are identified -->
   ```

7. Create SPRINT_LOG.md:
   ```markdown
   # Sprint Log — <PROJECT_NAME>

   ## Sprint 0 — Pipeline Setup
   **Date:** <today>
   **Agent:** Operations
   - Initialized multi-agent pipeline
   - Created .codex/<ACRONYM>/ durable memory
   - Created CLAUDE.md, CLAUDE.md, NEXT_TASK.md, BACKLOG.md
   ```

8. Create the 8 durable memory files in `.codex/<ACRONYM>/`:

   **status.md:**
   ```markdown
   # Status
   - **Current objective:** Pipeline initialized, awaiting first task
   - **Branch:** main
   - **Verification:** pending first build
   - **Last updated:** <today>
   ```

   **handoff.md:**
   ```markdown
   # Handoff
   ## Pipeline Initialization (<today>)
   - Created project structure and durable memory
   - Next: Architect defines first task in NEXT_TASK.md
   ```

   **changelog.md:**
   ```markdown
   # Changelog
   ## <today> — Pipeline Setup
   - Initialized multi-agent pipeline structure
   - Created 8 durable memory files
   - Ready for first Architect task
   ```

   **agent.md:**
   ```markdown
   # <ACRONYM> Agent Memory

   ## Project identity
   - Code: `<ACRONYM>`
   - Name: `<PROJECT_NAME>`
   - Owner: <user>

   ## Multi-agent process
   - 4 agents: ChatGPT (Architect), Codex (Builder), Claude (Reviewer), Claude Opus (Ops)
   - Workflow: Architect -> Builder -> Reviewer -> Operations
   - Task beacon: NEXT_TASK.md (exactly one active task)
   - Communication: file-based only

   ## Coding conventions
   <!-- Fill in project-specific conventions -->
   ```

   **plan.md:**
   ```markdown
   # Plan
   - Pipeline initialized
   - Awaiting Architect to define Phase 1 goals
   ```

   **decisions.md:**
   ```markdown
   # Decisions

   ## <today> — Multi-Agent Pipeline Adoption
   - Decision: Use 4-agent sequential pipeline with file-based coordination
   - Reason: Enables complex project development across multiple AI platforms
   - Consequences: All agents must follow boot sequence and update memory
   ```

   **runbook.md:**
   ```markdown
   # Runbook

   ## Setup
   ```bash
   cd <REPO_PATH>
   npm install   # or pnpm install
   ```

   ## Verification
   ```bash
   npm test      # All tests must pass
   npm run build # Clean build required
   ```

   ## Git workflow
   ```bash
   git checkout -b feat/short-description
   # ... make changes ...
   git add <specific-files>
   git commit -m "feat: description"
   git push -u origin feat/short-description
   ```
   ```

   **open_questions.md:**
   ```markdown
   # Open Questions
   <!-- Track uncertainties here with status and resolution -->
   ```

9. Verify the structure:
   ```bash
   ls -la CLAUDE.md CLAUDE.md NEXT_TASK.md BACKLOG.md SPRINT_LOG.md
   ls -la .codex/<ACRONYM>/
   ```

10. Report completion to the user with a summary of created files and next steps.

## Outputs
- Complete pipeline directory structure
- All 8 durable memory files initialized
- CLAUDE.md with role definitions and boot sequence
- CLAUDE.md with quick orientation
- Task beacon, backlog, and sprint log ready
- Project is ready for the Architect to define the first task
