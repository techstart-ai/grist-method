#!/usr/bin/env bash
# Install GRIST OpenSpec overlay into a project using Antigravity.
#
# Usage: ./install-antigravity.sh <project-root> [--dry-run] [--uninstall]
#
# This installer targets projects where OpenSpec commands run as Antigravity skills
# (.agents/skills/opsx-*/). It mirrors install-cursor.sh with path
# adjustments for Antigravity's directory layout.
#
# What it does:
#   1. Runs the standard OpenSpec installer (copies schema + script + config)
#   2. Injects GRIST blocks into opsx-propose, opsx-apply, opsx-archive skills
#   3. Installs the grist skill if not already present
#   4. Appends GRIST always-on rules to AGENTS.md (idempotent)
#   5. Creates .grist/context-pack.md from template if not present

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENSPEC_OVERRIDES_DIR="$SCRIPT_DIR"
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
  echo "  Installs GRIST OpenSpec overlay for Antigravity projects."
  echo "  Requires Antigravity skills (.agents/skills/opsx-*)."
  echo
  echo "Options:"
  echo "  --dry-run     Show what would be done without modifying files"
  echo "  --uninstall   Remove GRIST injection blocks from skill files"
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
    *)           PROJECT_ROOT="$(cd "$arg" 2>/dev/null && pwd)" || {
                   log_err "Directory not found: $arg"
                   exit 1
                 } ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  log_err "No project root specified."
  usage
fi

# --- Validation -------------------------------------------------------------

SKILLS_DIR="$PROJECT_ROOT/.agents/skills"

# Check for at least one opsx skill
OPSX_FOUND=false
if [[ -d "$SKILLS_DIR" ]]; then
  for d in "$SKILLS_DIR"/opsx-*/; do
    [[ -d "$d" ]] && OPSX_FOUND=true && break
  done
fi

# OpenSpec project structure check
HAS_OPENSPEC=false
[[ -d "$PROJECT_ROOT/openspec" ]] && HAS_OPENSPEC=true

if ! $OPSX_FOUND && ! $HAS_OPENSPEC; then
  log_warn "No OpenSpec structure found at $PROJECT_ROOT"
  log_warn "Expected: .agents/skills/opsx-*/ or openspec/ directory"
  log_warn "Continuing — will install grist skill and AGENTS.md rules."
fi

# --- Uninstall mode ---------------------------------------------------------

remove_grist_blocks() {
  local file="$1"
  if [[ ! -f "$file" ]]; then return; fi
  if ! grep -q 'GRIST:BEGIN' "$file"; then return; fi

  if $DRY_RUN; then
    log_info "[dry-run] Would remove GRIST blocks from $(basename "$file")"
    return
  fi

  local tmpfile
  tmpfile=$(mktemp)
  local in_block=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == *"GRIST:BEGIN"* ]]; then
      in_block=true
      continue
    fi
    if [[ "$line" == *"GRIST:END"* ]]; then
      in_block=false
      continue
    fi
    if ! $in_block; then
      printf '%s\n' "$line" >> "$tmpfile"
    fi
  done < "$file"
  mv "$tmpfile" "$file"
  log_ok "Removed GRIST blocks from $(basename "$file")"
}

if $UNINSTALL; then
  log_info "Uninstalling GRIST OpenSpec overlay from $PROJECT_ROOT"
  echo

  # Remove injection blocks from opsx skill files
  if [[ -d "$SKILLS_DIR" ]]; then
    for d in "$SKILLS_DIR"/opsx-*/; do
      if [[ -d "$d" ]]; then
        find "$d" -name '*.md' -type f | while read -r f; do
          remove_grist_blocks "$f"
        done
      fi
    done
  fi

  # Remove AGENTS.md GRIST rules
  if [[ -f "$PROJECT_ROOT/AGENTS.md" ]]; then
    if grep -q 'GRIST:RULES' "$PROJECT_ROOT/AGENTS.md"; then
      tmpfile=$(mktemp)
      in_rules=false
      while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == *"GRIST:RULES"* ]] && ! $in_rules; then
          in_rules=true
          continue
        fi
        if [[ "$line" == *"GRIST:RULES:END"* ]]; then
          in_rules=false
          continue
        fi
        if ! $in_rules; then
          printf '%s\n' "$line" >> "$tmpfile"
        fi
      done < "$PROJECT_ROOT/AGENTS.md"
      mv "$tmpfile" "$PROJECT_ROOT/AGENTS.md"
      log_ok "Removed GRIST rules from AGENTS.md"
    else
      log_skip "AGENTS.md has no GRIST rules"
    fi
  fi

  log_ok "GRIST OpenSpec overlay uninstalled. Schema files at openspec/schemas/grist/ left in place."
  exit 0
fi

# --- Step 1: Run standard OpenSpec installer --------------------------------

echo
log_info "Step 1: Installing OpenSpec schema files (standard installer)"

STANDARD_INSTALLER="$OPENSPEC_OVERRIDES_DIR/install.sh"

if [[ -f "$STANDARD_INSTALLER" ]]; then
  if $DRY_RUN; then
    log_info "[dry-run] Would run: $STANDARD_INSTALLER $PROJECT_ROOT"
  else
    # Run standard installer — it handles schema, script, config.yaml
    "$STANDARD_INSTALLER" "$PROJECT_ROOT" 2>&1 | sed 's/^/  /'
    log_ok "Standard OpenSpec schema installed"
  fi
else
  log_warn "Standard installer not found at $STANDARD_INSTALLER — skipping schema copy"
fi

# --- Step 2: Inject GRIST blocks into opsx skills ---------------------------

echo
log_info "Step 2: Injecting GRIST blocks into OpenSpec skill files"

INJECTIONS_DIR="$OPENSPEC_OVERRIDES_DIR/injections"

# Helper: inject or update a GRIST block in a skill file
inject_block() {
  local target_file="$1"
  local injection_file="$2"
  local before_pattern="$3"  # ERE regex for where to inject (empty = append)

  if [[ ! -f "$target_file" ]]; then
    log_warn "Skill file not found: $target_file — skipping"
    return 0
  fi

  if $DRY_RUN; then
    if grep -q 'GRIST:BEGIN' "$target_file"; then
      log_info "[dry-run] Would update GRIST block in $(basename "$target_file")"
    else
      log_info "[dry-run] Would inject GRIST block into $(basename "$target_file")"
    fi
    return 0
  fi

  # Replace existing block
  if grep -q 'GRIST:BEGIN' "$target_file"; then
    local tmpfile
    tmpfile=$(mktemp)
    local in_block=false
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == *"GRIST:BEGIN"* ]]; then
        in_block=true
        cat "$injection_file" >> "$tmpfile"
        continue
      fi
      if [[ "$line" == *"GRIST:END"* ]]; then
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

  # Inject before pattern or append
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

# Find an opsx skill's workflow file by name stem (propose, apply, archive)
find_opsx_workflow() {
  local stem="$1"
  local dir="$SKILLS_DIR"

  if [[ ! -d "$dir" ]]; then echo ""; return; fi

  # Try skill directory with workflow.md
  for pattern in \
    "opsx-${stem}" \
    "opsx_${stem}" \
    "${stem}"
  do
    local skill_dir="$dir/$pattern"
    if [[ -d "$skill_dir" && -f "$skill_dir/workflow.md" ]]; then
      echo "$skill_dir/workflow.md"
      return
    fi
    if [[ -d "$skill_dir" && -f "$skill_dir/SKILL.md" ]]; then
      echo "$skill_dir/SKILL.md"
      return
    fi
  done

  # Fuzzy: any skill directory containing the stem
  local result
  result=$(find "$dir" -maxdepth 2 -name 'workflow.md' -path "*${stem}*" 2>/dev/null | head -1)
  echo "$result"
}

# Inject into opsx-propose
propose_wf=$(find_opsx_workflow "propose")
if [[ -n "$propose_wf" ]]; then
  inject_block "$propose_wf" "$INJECTIONS_DIR/opsx-propose.md" "Emit|emit|Generate|generate|Create|create"
else
  log_warn "opsx-propose skill not found at $SKILLS_DIR — skipping injection"
  log_warn "  (Install OpenSpec skills first, then re-run this installer)"
fi

# Inject into opsx-apply
apply_wf=$(find_opsx_workflow "apply")
if [[ -n "$apply_wf" ]]; then
  inject_block "$apply_wf" "$INJECTIONS_DIR/opsx-apply.md" "Read|read|Load|load|mode:|Mode:"
else
  log_warn "opsx-apply skill not found — skipping injection"
fi

# Inject into opsx-archive
archive_wf=$(find_opsx_workflow "archive")
if [[ -n "$archive_wf" ]]; then
  inject_block "$archive_wf" "$INJECTIONS_DIR/opsx-archive.md" "merge|Merge|archive|Archive|move|Move"
else
  log_warn "opsx-archive skill not found — skipping injection"
fi

# --- Step 3: Install/update grist skill ------------------------------------

echo
log_info "Step 3: Installing grist skill"

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
  log_skip "AGENTS.md already contains GRIST rules"
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

# --- Step 6: Spec migration hint --------------------------------------------

echo
log_info "Step 6: Checking for existing prose specs"

SPECS_DIR="$PROJECT_ROOT/openspec/specs"
PROSE_SPECS=()

if [[ -d "$SPECS_DIR" ]]; then
  while IFS= read -r f; do
    sibling_yaml="${f%spec.md}spec.grist.yaml"
    if [[ ! -f "$sibling_yaml" ]]; then
      PROSE_SPECS+=("$f")
    fi
  done < <(find "$SPECS_DIR" -name 'spec.md' -type f 2>/dev/null)
fi

if [[ ${#PROSE_SPECS[@]} -gt 0 ]]; then
  log_warn "${#PROSE_SPECS[@]} prose spec(s) found without YAML equivalent:"
  for f in "${PROSE_SPECS[@]}"; do
    printf "    %s\n" "${f#"$PROJECT_ROOT/"}"
  done
  echo
  echo "  Migrate to YAML form:"
  echo "    for d in openspec/specs/*/; do"
  echo "      python3 openspec/scripts/openspec-spec-to-grist.py --in-place \"\$d/spec.md\""
  echo "    done"
else
  log_skip "No unmigrated prose specs found"
fi

# --- Summary ----------------------------------------------------------------

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "${GREEN}GRIST OpenSpec overlay installed at:${NC} %s\n" "$PROJECT_ROOT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "What happens now:"
echo "  • Invoke the grist skill for mode activation."
echo "  • /grist iterate — shortcut for the propose→apply→archive cycle"
echo "  • Always-on rules in AGENTS.md apply automatically."
echo
echo "Next steps:"
echo "  1. Edit .grist/context-pack.md with your project's stable facts."
echo "  2. Try: /opsx:propose add-<feature>"
echo "  3. Verify change.grist.yaml is emitted (not proposal.md/design.md)."
echo
echo "Uninstall:"
echo "  $0 $PROJECT_ROOT --uninstall"
echo
