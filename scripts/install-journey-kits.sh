#!/usr/bin/env bash
# Install Journey kits permanently for the Copilot CLI skill runtime.
#
# Installs into two locations:
#   1) Repo: claude-skills/_journey/<slug>/  — tracked; portable across systems.
#   2) Runtime: ~/.agents/skills/<slug>/     — what Copilot CLI actually discovers.
#
# Re-runnable on any machine after `git pull`. Idempotent.
#
# Usage: bash scripts/install-journey-kits.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DEST="$REPO_ROOT/claude-skills/_journey"
RUNTIME_DEST="$HOME/.agents/skills"
TARGET="claude-code"

# Format: "owner/slug[@ref]". @ref pins a specific version if the latest release
# has an upstream bundle bug. Plain entries resolve to ?ref=latest.
KITS=(
  "matt-clawd/morning-brief"
  "henryfinn/personal-knowledge-wiki"
  "matt-clawd/humanizer"
  "suparahul/supabuilder"
  "giorgio/memory-stack-integration"
  "kevin-bigham/multi-agent-game-dev@v1.0.0"
  "kevin-bigham/determinism-guard@v1.1.0"
  "giorgio/self-improve-harness"
  "matt-clawd/skill-drift-detector"
  "maxcoo/rsi-starter-loop-for-agent-systems"
  "lilu/context-guard"
  "robert-gordon/personal-ops-loop@v1.0.0"
  "brian-wagner/proposal-to-pdf"
  "bronsonelliott/data-analysis-suite"
  "maxcoo/itp-parallel-agent-cost-saver"
)

mkdir -p "$REPO_DEST" "$RUNTIME_DEST"

install_one() {
  local entry="$1"
  local kit_ref="${entry%@*}"
  local ref="latest"
  if [[ "$entry" == *"@"* ]]; then
    ref="${entry#*@}"
  fi
  local slug="${kit_ref#*/}"
  local url="https://www.journeykits.ai/api/kits/${kit_ref}/install?target=${TARGET}&ref=${ref}"
  local kit_repo="$REPO_DEST/$slug"
  local kit_runtime="$RUNTIME_DEST/$slug"
  local tmp
  tmp="$(mktemp -d)"

  echo "[journey] $kit_ref"
  if ! curl -sfL "$url" -o "$tmp/install.json"; then
    echo "[journey] fetch failed: $kit_ref" >&2
    return 1
  fi

  rm -rf "$kit_repo" "$kit_runtime"
  mkdir -p "$kit_repo"

  python3 - "$tmp/install.json" "$kit_repo" "$slug" "$kit_runtime" <<'PY'
import json, os, sys, pathlib, shutil
install_json, repo_root, slug, runtime_root = sys.argv[1:5]
d = json.load(open(install_json))
repo_root = pathlib.Path(repo_root)
runtime_root = pathlib.Path(runtime_root)

# Write every file into repo tree preserving original structure.
for f in d.get("files", []):
    p = repo_root / f["path"]
    p.parent.mkdir(parents=True, exist_ok=True)
    mode = f.get("writeMode", "create")
    if mode == "append" and p.exists():
        with p.open("a") as out:
            out.write("\n")
            out.write(f.get("content", ""))
    else:
        p.write_text(f.get("content", ""))

# Write an install manifest so audits can pin the install to a ref.
(repo_root / ".journey-install.json").write_text(json.dumps({
    "target": d.get("target"),
    "kitRef": d.get("kitRef"),
    "ref": d.get("ref"),
    "suggestedRootDir": d.get("suggestedRootDir"),
    "selfContained": d.get("selfContained", True),
    "dependencyKits": d.get("dependencyKits", []),
    "compatibilityNotes": d.get("compatibilityNotes"),
}, indent=2))

# Flatten to runtime layout: ~/.agents/skills/<slug>/SKILL.md + kit content.
runtime_root.mkdir(parents=True, exist_ok=True)
skill_src = repo_root / ".claude" / "skills" / slug / "SKILL.md"
if skill_src.exists():
    shutil.copy2(skill_src, runtime_root / "SKILL.md")
# Copy the kit-named content subtree (kit.md, src/, skills/, examples/, etc.)
content_src = repo_root / slug
if content_src.exists() and content_src.is_dir():
    for item in content_src.iterdir():
        dest = runtime_root / item.name
        if item.is_dir():
            shutil.copytree(item, dest, dirs_exist_ok=True)
        else:
            shutil.copy2(item, dest)
PY

  if [[ ! -f "$kit_runtime/SKILL.md" ]]; then
    echo "[journey] WARN: $slug has no SKILL.md — runtime discovery will skip it" >&2
  fi
  rm -rf "$tmp"
}

for kit in "${KITS[@]}"; do
  install_one "$kit" || echo "[journey] FAILED: $kit" >&2
done

echo "[journey] done. Installed $(ls -1 "$RUNTIME_DEST" | wc -l | tr -d ' ') skills at $RUNTIME_DEST"
