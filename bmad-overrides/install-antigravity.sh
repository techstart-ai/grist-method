#!/usr/bin/env bash
# Install GRIST overlays into a BMAD project that uses Antigravity skills.
#
# Usage: ./install-antigravity.sh <project-root> [--dry-run] [--uninstall]
#
# This installer targets projects where BMAD runs via Antigravity skills
# (.agents/skills/bmad-*/workflow.md). It mirrors install-cursor.sh
# with path adjustments for Antigravity's directory layout.
#
# What it does:
#   1. Copies emission rules, schemas, scripts to _bmad/custom/
#   2. Patches each BMAD workflow's step files with grist emission blocks
#   3. Installs the grist skill (skill = command in Antigravity)
#   4. Appends always-on rules to AGENTS.md (idempotent)
#   5. Creates .grist/context-pack.md from template
#
# Idempotent: re-running upgrades overlays and re-patches step files.
# Existing user content outside GRIST markers is untouched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRIST_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
log_skip() { printf "${YELLOW}⊘${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
log_err()  { printf "${RED}✗${NC} %s\n" "$1" >&2; }
log_info() { printf "${BLUE}→${NC} %s\n" "$1"; }

usage() {
  echo "usage: $0 <project-root> [--dry-run] [--uninstall]"
  echo
  echo "  Installs GRIST overlays for BMAD projects using Antigravity skills."
  echo "  For BMAD npm/framework (TOML config), use install.sh instead."
  echo
  echo "Options:"
  echo "  --dry-run     Show what would be done without modifying files"
  echo "  --uninstall   Remove GRIST injection blocks and AGENTS.md rules"
  exit 2
}

# --- Argument parsing -------------------------------------------------------

if [[ $# -lt 1 ]]; then
  usage
fi

PROJECT_ROOT=""
DRY_RUN=false
UNINSTALL=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=true ;;
    --uninstall) UNINSTALL=true ;;
    --help|-h)   usage ;;
    *)           PROJECT_ROOT="$(cd "$arg" && pwd)" ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  log_err "No project root specified."
  usage
fi

# --- Validation -------------------------------------------------------------

SKILLS_DIR="$PROJECT_ROOT/.agents/skills"

if [[ ! -d "$SKILLS_DIR" ]]; then
  log_err "$PROJECT_ROOT does not have .agents/skills/ — is this an Antigravity project?"
  exit 1
fi

# Check for at least one BMAD skill
BMAD_SKILLS=()
for skill in bmad-create-prd bmad-create-architecture bmad-create-story bmad-dev-story bmad-code-review; do
  if [[ -d "$SKILLS_DIR/$skill" ]]; then
    BMAD_SKILLS+=("$skill")
  fi
done

if [[ ${#BMAD_SKILLS[@]} -eq 0 ]]; then
  log_err "No BMAD skills found at $SKILLS_DIR/bmad-*"
  log_err "Install BMAD skills first, then re-run this installer."
  exit 1
fi

log_info "Found ${#BMAD_SKILLS[@]} BMAD skills: ${BMAD_SKILLS[*]}"

# --- Uninstall mode ---------------------------------------------------------

remove_grist_blocks() {
  local file="$1"
  if [[ ! -f "$file" ]]; then return; fi
  if ! grep -q 'GRIST:BEGIN' "$file" && ! grep -q 'GRIST:RULES' "$file"; then return; fi

  if $DRY_RUN; then
    log_info "[dry-run] Would remove GRIST blocks from $file"
    return
  fi

  # Remove content between GRIST:BEGIN and GRIST:END markers (inclusive)
  local tmpfile
  tmpfile=$(mktemp)
  awk '/<!-- GRIST:BEGIN/,/<!-- GRIST:END/ { next } /<!-- GRIST:RULES/,/<!-- GRIST:RULES:END/ { next } { print }' "$file" > "$tmpfile"
  mv "$tmpfile" "$file"
  log_ok "Removed GRIST blocks from $(basename "$file")"
}

if $UNINSTALL; then
  log_info "Uninstalling GRIST from $PROJECT_ROOT"
  echo

  # Remove injection blocks from step files
  for skill in "${BMAD_SKILLS[@]}"; do
    skill_dir="$SKILLS_DIR/$skill"
    find "$skill_dir" -name '*.md' -type f | while read -r f; do
      remove_grist_blocks "$f"
    done
  done

  # Remove AGENTS.md rules
  if [[ -f "$PROJECT_ROOT/AGENTS.md" ]]; then
    remove_grist_blocks "$PROJECT_ROOT/AGENTS.md"
  fi

  log_ok "GRIST uninstalled. Emission rules and schemas at _bmad/custom/ left in place."
  exit 0
fi

# --- Step 1: Copy emission rules, schemas, scripts -------------------------

echo
log_info "Step 1: Copying emission rules, schemas, and scripts"

CUSTOM_DIR="$PROJECT_ROOT/_bmad/custom"
mkdir -p "$CUSTOM_DIR/grist-schemas" "$CUSTOM_DIR/grist-scripts"

# Emission rules — always overwrite
for f in grist-prd-emission.md grist-architecture-emission.md grist-story-emission.md grist-dev-story-emission.md grist-code-review-emission.md; do
  src="$SCRIPT_DIR/_bmad/custom/$f"
  if [[ -f "$src" ]]; then
    if $DRY_RUN; then
      log_info "[dry-run] Would copy $f"
    else
      cp "$src" "$CUSTOM_DIR/$f"
      log_ok "_bmad/custom/$f"
    fi
  else
    log_warn "Source not found: $src"
  fi
done

# Schemas — always overwrite
for f in prd architecture story change review; do
  src="$GRIST_ROOT/schemas/$f.grist.yaml"
  if [[ -f "$src" ]]; then
    if $DRY_RUN; then
      log_info "[dry-run] Would copy $f.grist.yaml"
    else
      cp "$src" "$CUSTOM_DIR/grist-schemas/$f.grist.yaml"
      log_ok "_bmad/custom/grist-schemas/$f.grist.yaml"
    fi
  fi
done

# Scripts — always overwrite
for f in post-prd-to-grist.py post-arch-to-grist.py post-story-to-grist.py post-dev-story.py post-code-review.py bmad-prd-to-grist.py; do
  src="$SCRIPT_DIR/_bmad/custom/grist-scripts/$f"
  if [[ -f "$src" ]]; then
    if $DRY_RUN; then
      log_info "[dry-run] Would copy $f"
    else
      cp "$src" "$CUSTOM_DIR/grist-scripts/$f"
      chmod +x "$CUSTOM_DIR/grist-scripts/$f"
      log_ok "_bmad/custom/grist-scripts/$f"
    fi
  fi
done

# --- Step 2: Inject grist blocks into workflow step files -------------------

echo
log_info "Step 2: Injecting GRIST emission blocks into workflow step files"

# Helper: inject a block into a file before a marker line, or append if marker not found.
# If GRIST:BEGIN already exists, replace it.
inject_block() {
  local target_file="$1"
  local injection_file="$2"
  local before_pattern="$3"  # regex to find the line BEFORE which to inject (empty = append)
  local block_id="${4:-}"    # optional: GRIST:BEGIN:<id> for multi-block files

  if [[ ! -f "$target_file" ]]; then
    log_warn "Target file not found: $target_file"
    return 1
  fi

  local marker="GRIST:BEGIN"
  local end_marker="GRIST:END"
  if [[ -n "$block_id" ]]; then
    marker="GRIST:BEGIN:${block_id}"
    end_marker="GRIST:END:${block_id}"
  fi

  if $DRY_RUN; then
    if grep -q "$marker" "$target_file"; then
      log_info "[dry-run] Would update existing GRIST block in $(basename "$target_file")"
    else
      log_info "[dry-run] Would inject GRIST block into $(basename "$target_file")"
    fi
    return 0
  fi

  # If block already exists, replace it: remove old content between markers, insert new
  if grep -q "$marker" "$target_file"; then
    local tmpfile
    tmpfile=$(mktemp)
    local in_block=false
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == *"$marker"* ]]; then
        in_block=true
        # Insert new content from injection file
        cat "$injection_file" >> "$tmpfile"
        continue
      fi
      if [[ "$line" == *"$end_marker"* ]]; then
        in_block=false
        continue
      fi
      if ! $in_block; then
        printf '%s\n' "$line" >> "$tmpfile"
      fi
    done < "$target_file"
    mv "$tmpfile" "$target_file"
    log_ok "Updated GRIST block in $(basename "$target_file")"
    return 0
  fi

  # Otherwise, inject before the pattern (or append)
  if [[ -n "$before_pattern" ]] && grep -qE "$before_pattern" "$target_file"; then
    local tmpfile
    tmpfile=$(mktemp)
    local injected=false
    while IFS= read -r line || [[ -n "$line" ]]; do
      if ! $injected && echo "$line" | grep -qE "$before_pattern"; then
        cat "$injection_file" >> "$tmpfile"
        printf '\n' >> "$tmpfile"
        injected=true
      fi
      printf '%s\n' "$line" >> "$tmpfile"
    done < "$target_file"
    mv "$tmpfile" "$target_file"
    log_ok "Injected GRIST block before '${before_pattern}' in $(basename "$target_file")"
  else
    printf '\n' >> "$target_file"
    cat "$injection_file" >> "$target_file"
    printf '\n' >> "$target_file"
    log_ok "Appended GRIST block to $(basename "$target_file")"
  fi
}

# Find the final step file in a skills directory (highest-numbered step-NN-*.md)
find_final_step() {
  local steps_dir="$1"
  local result=""

  # Try multiple common step directory names
  for subdir in steps-c steps steps-d; do
    local dir="$steps_dir/$subdir"
    if [[ -d "$dir" ]]; then
      # Find step files with "complete" or "final" in name first
      result=$(find "$dir" -name '*complete*' -o -name '*final*' | head -1)
      if [[ -n "$result" ]]; then
        echo "$result"
        return 0
      fi
      # Fall back to highest-numbered step file
      result=$(find "$dir" -name 'step-*' -type f | sort -V | tail -1)
      if [[ -n "$result" ]]; then
        echo "$result"
        return 0
      fi
    fi
  done

  # Last resort: any .md file with "complete" or "final"
  result=$(find "$steps_dir" -name '*.md' -path '*step*' | sort -V | tail -1)
  echo "$result"
}

INJECTIONS_DIR="$SCRIPT_DIR/injections"

# --- bmad-create-prd ---
if [[ -d "$SKILLS_DIR/bmad-create-prd" ]]; then
  final_step=$(find_final_step "$SKILLS_DIR/bmad-create-prd")
  if [[ -n "$final_step" ]]; then
    inject_block "$final_step" "$INJECTIONS_DIR/prd-emission.md" "EXECUTION PROTOCOLS"
  elif [[ -f "$SKILLS_DIR/bmad-create-prd/workflow.md" ]]; then
    inject_block "$SKILLS_DIR/bmad-create-prd/workflow.md" "$INJECTIONS_DIR/prd-emission.md" "</workflow>"
  else
    log_warn "bmad-create-prd: no final step file found — skipping injection"
  fi
fi

# --- bmad-create-architecture ---
if [[ -d "$SKILLS_DIR/bmad-create-architecture" ]]; then
  final_step=$(find_final_step "$SKILLS_DIR/bmad-create-architecture")
  if [[ -n "$final_step" ]]; then
    inject_block "$final_step" "$INJECTIONS_DIR/architecture-emission.md" "HALT|EXECUTION PROTOCOLS|next steps"
  elif [[ -f "$SKILLS_DIR/bmad-create-architecture/workflow.md" ]]; then
    inject_block "$SKILLS_DIR/bmad-create-architecture/workflow.md" "$INJECTIONS_DIR/architecture-emission.md" "</workflow>"
  else
    log_warn "bmad-create-architecture: no final step file found — skipping injection"
  fi
fi

# --- bmad-create-story ---
if [[ -d "$SKILLS_DIR/bmad-create-story" ]]; then
  final_step=$(find_final_step "$SKILLS_DIR/bmad-create-story")
  if [[ -n "$final_step" ]]; then
    inject_block "$final_step" "$INJECTIONS_DIR/story-emission.md" "HALT|EXECUTION PROTOCOLS|next steps"
  elif [[ -f "$SKILLS_DIR/bmad-create-story/workflow.md" ]]; then
    inject_block "$SKILLS_DIR/bmad-create-story/workflow.md" "$INJECTIONS_DIR/story-emission.md" "</workflow>"
  else
    log_warn "bmad-create-story: no final step file found — skipping injection"
  fi
fi

# --- bmad-dev-story (two injection points) ---
if [[ -d "$SKILLS_DIR/bmad-dev-story" ]]; then
  workflow_file="$SKILLS_DIR/bmad-dev-story/workflow.md"
  if [[ -f "$workflow_file" ]]; then
    # Injection A: story load (after step 1's file read)
    inject_block "$workflow_file" "$INJECTIONS_DIR/dev-story-load.md" 'step n="2"' "LOAD"
    # Injection B: story completion (in step 9)
    inject_block "$workflow_file" "$INJECTIONS_DIR/dev-story-complete.md" 'step n="10"|HALT|</workflow>' "COMPLETE"
  else
    log_warn "bmad-dev-story: workflow.md not found — skipping injection"
  fi
fi

# --- bmad-code-review ---
if [[ -d "$SKILLS_DIR/bmad-code-review" ]]; then
  # Try step-04-present.md specifically
  present_step=""
  for subdir in steps steps-c steps-d; do
    candidate="$SKILLS_DIR/bmad-code-review/$subdir/step-04-present.md"
    if [[ -f "$candidate" ]]; then
      present_step="$candidate"
      break
    fi
  done

  if [[ -z "$present_step" ]]; then
    # Fall back to any step with "present" in name
    present_step=$(find "$SKILLS_DIR/bmad-code-review" -name '*present*' -type f | head -1)
  fi

  if [[ -z "$present_step" ]]; then
    # Fall back to final step
    present_step=$(find_final_step "$SKILLS_DIR/bmad-code-review")
  fi

  if [[ -n "$present_step" ]]; then
    inject_block "$present_step" "$INJECTIONS_DIR/code-review-emission.md" "Completion summary|completion summary|#### Completion"
  elif [[ -f "$SKILLS_DIR/bmad-code-review/workflow.md" ]]; then
    inject_block "$SKILLS_DIR/bmad-code-review/workflow.md" "$INJECTIONS_DIR/code-review-emission.md" "</workflow>"
  else
    log_warn "bmad-code-review: no suitable step file found — skipping injection"
  fi
fi

# --- Step 3: Install grist skill -------------------------------------------

echo
log_info "Step 3: Installing grist skill (skill = command in Antigravity)"

# Skill
SKILL_DST="$SKILLS_DIR/grist"
mkdir -p "$SKILL_DST"
if $DRY_RUN; then
  log_info "[dry-run] Would install .agents/skills/grist/SKILL.md"
else
  cp "$GRIST_ROOT/skills/grist/SKILL.md" "$SKILL_DST/SKILL.md"
  log_ok ".agents/skills/grist/SKILL.md"
fi

# --- Step 4: Install AGENTS.md rules ---------------------------------------

echo
log_info "Step 4: Installing always-on rules"

# AGENTS.md
AGENTS_MD="$PROJECT_ROOT/AGENTS.md"
RULES_TEMPLATE="$GRIST_ROOT/templates/agents-md-rules.md"

if [[ -f "$AGENTS_MD" ]] && grep -q 'GRIST:RULES' "$AGENTS_MD"; then
  log_skip "AGENTS.md already contains GRIST rules (marker found)"
elif [[ -f "$AGENTS_MD" ]] && grep -q 'GRIST.*Always-On' "$AGENTS_MD"; then
  log_skip "AGENTS.md already contains GRIST rules (heading found)"
elif [[ -f "$RULES_TEMPLATE" ]]; then
  if $DRY_RUN; then
    log_info "[dry-run] Would append GRIST rules to AGENTS.md"
  else
    if [[ ! -f "$AGENTS_MD" ]]; then
      touch "$AGENTS_MD"
      log_info "Created AGENTS.md"
    fi
    echo "" >> "$AGENTS_MD"
    cat "$RULES_TEMPLATE" >> "$AGENTS_MD"
    log_ok "Appended GRIST always-on rules to AGENTS.md"
  fi
else
  log_warn "Rules template not found at $RULES_TEMPLATE"
fi

# --- Step 5: Create .grist/context-pack.md ---------------------------------

echo
log_info "Step 5: Creating .grist/context-pack.md"

GRIST_DIR="$PROJECT_ROOT/.grist"
CONTEXT_PACK="$GRIST_DIR/context-pack.md"

if [[ -f "$CONTEXT_PACK" ]]; then
  log_skip ".grist/context-pack.md already exists"
else
  if $DRY_RUN; then
    log_info "[dry-run] Would create .grist/context-pack.md from template"
  else
    mkdir -p "$GRIST_DIR"
    cp "$GRIST_ROOT/templates/context-pack.md" "$CONTEXT_PACK"
    log_ok ".grist/context-pack.md (populate with project-specific facts)"
  fi
fi

# --- Step 6: Add TOML deprecation notices -----------------------------------

echo
log_info "Step 6: Adding deprecation notices to TOML overrides (if present)"

TOML_NOTICE="# NOTE: This TOML override is for the BMAD-method npm/framework TOML config layer only.
# Antigravity skills (.agents/skills/bmad-*/) ignore this file.
# GRIST emission is wired directly into workflow step files by install-antigravity.sh.
# See: bmad-overrides/injections/ for the active injection blocks."

for tool in bmad-create-prd bmad-create-architecture bmad-create-story bmad-dev-story bmad-code-review; do
  toml_file="$CUSTOM_DIR/$tool.toml"
  if [[ -f "$toml_file" ]]; then
    if grep -q "Antigravity skills" "$toml_file"; then
      log_skip "$tool.toml already has deprecation notice"
    else
      if $DRY_RUN; then
        log_info "[dry-run] Would add notice to $tool.toml"
      else
        tmpfile=$(mktemp)
        echo "$TOML_NOTICE" > "$tmpfile"
        echo "" >> "$tmpfile"
        cat "$toml_file" >> "$tmpfile"
        mv "$tmpfile" "$toml_file"
        log_ok "Added notice to $tool.toml"
      fi
    fi
  fi
done

# --- Summary ----------------------------------------------------------------

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "${GREEN}GRIST installed for Antigravity at:${NC} %s\n" "$PROJECT_ROOT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "What happens now:"
echo "  • Invoke the grist skill in Antigravity chat to activate a mode."
echo "  • /grist ship    — coding mode (default). No preambles, read discipline."
echo "  • /grist design  — BMAD planning. Emits .grist.yaml alongside prose."
echo "  • /grist iterate — OpenSpec changes. Single change.grist.yaml."
echo "  • Always-on rules in AGENTS.md apply automatically."
echo
echo "Next steps:"
echo "  1. Edit .grist/context-pack.md with your project's stable facts."
echo "  2. Run a BMAD planning skill — verify .grist.yaml artifact is emitted."
echo "  3. Measure: python3 gristats/gristats.py sessions --days 7"
echo
echo "Uninstall:"
echo "  $0 $PROJECT_ROOT --uninstall"
echo
