---
name: setup-supabuilder
description: "Initialize Supabuilder in a project. Creates workspace scaffold, writes orchestrator brain to platform config, optionally scans codebase and populates wikis."
user-invocable: true
---

# Setup Supabuilder

Initialize or resume Supabuilder setup in the current project. Idempotent — re-running picks up where you left off.

## Before Starting: Detect State

| Condition | Start at |
|-----------|----------|
| No `supabuilder/` folder | Step 1 |
| `supabuilder/` exists but wikis have only stubs | Step 3 |
| Everything is populated | "Supabuilder is already initialized. Nothing to do." |

---

## Step 1: Brand + Scaffold

### 1a. Branding

Read `{kit_root}/reference/branding.md` and output the ASCII header with version and a random tagline.

### 1b. Create workspace

Create the `supabuilder/` workspace at the project root. Refer to `{kit_root}/templates/scaffold.md` for the full folder structure.

Create these directories and files:

```
supabuilder/
├── product-wiki/
│   ├── overview.md
│   ├── product-overview.excalidraw
│   ├── strategy/
│   ├── modules/
│   └── ui-kit/
│       └── README.md
├── code-wiki/
│   ├── README.md
│   ├── architecture-map.md
│   ├── patterns.md
│   ├── data-models.md
│   ├── system-overview.excalidraw
│   └── modules/
├── missions/
├── rules/
│   ├── coding-conventions.md
│   └── tech-stack.md
├── .archive/
├── state.json          ← from {kit_root}/templates/state.json
├── settings.json       ← from {kit_root}/templates/settings.json
├── memory.md
├── CLAUDE.md           ← copy from {kit_root}/agents.md
├── NEXT_PHASE.md       ← from {kit_root}/templates/next-phase.md
└── handoff.md          ← from {kit_root}/templates/handoff.md
```

Write stub content for wiki files (see `{kit_root}/templates/scaffold.md` for stub contents).

### 1c. Write orchestrator brain

Read the orchestrator template from `{kit_root}/orchestrator.md`.

Write to the platform's configuration file:
- **If no config file exists:** write the orchestrator template directly
- **If config file exists:** ask the user:
  - "Append Supabuilder orchestrator to existing config" (Recommended)
  - "Replace config with Supabuilder orchestrator"
  - "Skip — I'll add it manually"

### 1d. Checkpoint

Show summary of what was created:

```
Workspace created at supabuilder/
Orchestrator brain written to platform config.

Next: A quick interview so I can scan your codebase smarter.
```

Proceed to Step 2.

---

## Step 2: Interview (optional)

### 2a. Product overview

Ask the user:
- "Before I scan your codebase, a quick overview helps me scan smarter. What does this product do? Or point me to an existing doc."
- Options: "I'll give you an overview" / "Read this file" / "Skip, just scan"

If user provides context, extract a short product name and one-liner description. Write them to `supabuilder/state.json` as `product_name` and `product_description`. If skipped, leave both null.

### 2b. User types

Ask the user:
- "Who uses this product? Are there different types of users with different roles or access levels?"
- Options: "Single user type" / "Multiple user types" / "Not sure yet"

If multiple → capture for wiki population.

### 2c. Quick project detection

Scan config files and directory structure to detect modules/areas:
- `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `pubspec.yaml`, etc.
- Directory tree: `src/`, `lib/`, `app/`, `pages/`, `routes/`, `api/`
- Language, framework, main dependencies

This is lightweight — just enough to identify areas.

### 2d. Present areas

Present detected areas to the user:
- "I detected these main areas: {area1}, {area2}, {area3}. Does this look right?"
- Options: "Looks right" / "Let me adjust" / "Not sure, just scan"

Name areas from the user's perspective, not the codebase structure ("AI Chat" not "chat-panel").

---

## Step 3: Codebase Scan (if existing code)

For each detected area:

1. **Scan** — read key files (routes, components, models, API handlers, config)
2. **Extract dual lens:**
   - Product lens: what this area does for users, flows, business rules
   - Code lens: architecture, patterns, data models, dependencies
3. **Present findings** to user for confirmation
4. **Write wikis:**
   - `product-wiki/modules/{area}/README.md`
   - `code-wiki/modules/{area}/README.md`
   - Update running overviews

After all areas:
- Finalize `product-wiki/overview.md` with full product story + user types
- Finalize `code-wiki/architecture-map.md`, `patterns.md`, `data-models.md`

### 3b. Design System Extraction (optional)

After the codebase scan, ask the user:
- "I can extract your design system into a browsable HTML UI Kit now. This includes design tokens, components, cards, and layout patterns. Or the Designer agent can do this during the first mission."
- Options: "Extract now" / "Skip — Designer will handle it later"

If "Extract now":
1. Read `{kit_root}/reference/design-system.md` for the full specification
2. Follow Step 1 (Discover) — scan CSS/Tailwind config, theme setup, component library, composed patterns
3. Follow Step 2 (Create) — generate `tokens.css`, `_preview.css`, `foundations.html`, `core.html`, `cards.html`, `patterns.html`, `preview.html`
4. Present `preview.html` to the user for review
5. Write all files to `product-wiki/ui-kit/`

If "Skip", the Designer agent will handle this during their first mission.

---

## Step 4: Completion

```
Supabuilder initialized!

Workspace: supabuilder/
Orchestrator: active
Product-wiki: {N} modules populated (or: ready for first mission)
Code-wiki: {N} modules populated (or: ready for first mission)

The orchestrator is now active. Start talking about what you want to build.

Skills:
  setup-supabuilder    Re-run setup
```

---

## Edge Cases

- **Not a git repo** — works fine, skip git context
- **Empty project** — scaffold only, skip interview + scan (nothing to scan)
- **Very large codebase** — scan one area at a time to prevent context overflow
- **Can't write files** — check permissions, print error
