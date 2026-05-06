#!/usr/bin/env bash
# Smoke test for grist-method installers.
#
# Creates a temporary mock project with BMAD Claude Code skills structure,
# runs the installer, and verifies all injection targets are present.
#
# Usage: ./test/smoke-test.sh
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRIST_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
  local desc="$1"
  local condition="$2"

  if eval "$condition"; then
    printf "${GREEN}✓${NC} %s\n" "$desc"
    PASS=$((PASS + 1))
  else
    printf "${RED}✗${NC} %s\n" "$desc"
    FAIL=$((FAIL + 1))
  fi
}

# --- Setup: create mock BMAD project ----------------------------------------

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Creating mock BMAD project at: $TMPDIR"
echo

# Create mock BMAD skills directory structure
mkdir -p "$TMPDIR/.claude/skills/bmad-create-prd/steps-c"
mkdir -p "$TMPDIR/.claude/skills/bmad-create-architecture/steps"
mkdir -p "$TMPDIR/.claude/skills/bmad-create-story/steps"
mkdir -p "$TMPDIR/.claude/skills/bmad-dev-story"
mkdir -p "$TMPDIR/.claude/skills/bmad-code-review/steps"
mkdir -p "$TMPDIR/_bmad"

# Create mock step files
cat > "$TMPDIR/.claude/skills/bmad-create-prd/steps-c/step-12-complete.md" << 'EOF'
# Step 12: Complete PRD

Finalize the PRD document.

## EXECUTION PROTOCOLS:

Run the final validation checks.
EOF

cat > "$TMPDIR/.claude/skills/bmad-create-architecture/steps/step-08-complete.md" << 'EOF'
# Step 8: Complete Architecture

## HALT

Wait for user review.
EOF

cat > "$TMPDIR/.claude/skills/bmad-create-story/steps/step-06-complete.md" << 'EOF'
# Step 6: Complete Story

## EXECUTION PROTOCOLS:

Validate the story.
EOF

cat > "$TMPDIR/.claude/skills/bmad-dev-story/workflow.md" << 'EOF'
<workflow>
<step n="1" name="Load story">
  <action>Read COMPLETE story file from the given path</action>
</step>
<step n="2" name="Analyze">
  <action>Analyze requirements</action>
</step>
<step n="9" name="Story completion and mark for review">
  <action>Update the story Status to: "review"</action>
</step>
<step n="10" name="Final">
  <action>Done</action>
</step>
</workflow>
EOF

cat > "$TMPDIR/.claude/skills/bmad-code-review/steps/step-04-present.md" << 'EOF'
# Step 4: Present Findings

Present the triaged findings to the user.

#### Completion summary

Summarize the review.
EOF

# Create CLAUDE.md
cat > "$TMPDIR/CLAUDE.md" << 'EOF'
# Project Configuration

This is a test project.
EOF

# --- Run installer ----------------------------------------------------------

echo "Running installer..."
echo
"$GRIST_ROOT/bmad-overrides/install-claude-code.sh" "$TMPDIR" 2>&1 || {
  printf "\n${RED}Installer failed!${NC}\n"
  exit 1
}

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Verification checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# --- Verify: emission rules, schemas, scripts --------------------------------

check "Emission rules installed" \
  "[[ -f '$TMPDIR/_bmad/custom/grist-prd-emission.md' ]]"

check "Architecture emission installed" \
  "[[ -f '$TMPDIR/_bmad/custom/grist-architecture-emission.md' ]]"

check "Dev-story emission installed" \
  "[[ -f '$TMPDIR/_bmad/custom/grist-dev-story-emission.md' ]]"

check "Code-review emission installed" \
  "[[ -f '$TMPDIR/_bmad/custom/grist-code-review-emission.md' ]]"

check "PRD schema installed" \
  "[[ -f '$TMPDIR/_bmad/custom/grist-schemas/prd.grist.yaml' ]]"

check "Architecture schema installed" \
  "[[ -f '$TMPDIR/_bmad/custom/grist-schemas/architecture.grist.yaml' ]]"

check "Story schema installed" \
  "[[ -f '$TMPDIR/_bmad/custom/grist-schemas/story.grist.yaml' ]]"

check "Review schema installed" \
  "[[ -f '$TMPDIR/_bmad/custom/grist-schemas/review.grist.yaml' ]]"

check "Change schema installed" \
  "[[ -f '$TMPDIR/_bmad/custom/grist-schemas/change.grist.yaml' ]]"

# --- Verify: step file injections -------------------------------------------

check "PRD step file has GRIST block" \
  "grep -q 'GRIST:BEGIN' '$TMPDIR/.claude/skills/bmad-create-prd/steps-c/step-12-complete.md'"

check "PRD step file has emission instruction" \
  "grep -q 'prd.grist.yaml' '$TMPDIR/.claude/skills/bmad-create-prd/steps-c/step-12-complete.md'"

check "Architecture step file has GRIST block" \
  "grep -q 'GRIST:BEGIN' '$TMPDIR/.claude/skills/bmad-create-architecture/steps/step-08-complete.md'"

check "Story step file has GRIST block" \
  "grep -q 'GRIST:BEGIN' '$TMPDIR/.claude/skills/bmad-create-story/steps/step-06-complete.md'"

check "Dev-story workflow has GRIST load block" \
  "grep -q 'GRIST:BEGIN:LOAD' '$TMPDIR/.claude/skills/bmad-dev-story/workflow.md'"

check "Dev-story workflow has GRIST complete block" \
  "grep -q 'GRIST:BEGIN:COMPLETE' '$TMPDIR/.claude/skills/bmad-dev-story/workflow.md'"

check "Code-review step file has GRIST block" \
  "grep -q 'GRIST:BEGIN' '$TMPDIR/.claude/skills/bmad-code-review/steps/step-04-present.md'"

# --- Verify: skill and command -----------------------------------------------

check "Grist SKILL.md installed" \
  "[[ -f '$TMPDIR/.claude/skills/grist/SKILL.md' ]]"

check "Grist command (MD) installed" \
  "[[ -f '$TMPDIR/.claude/commands/grist.md' ]]"

# --- Verify: CLAUDE.md rules -------------------------------------------------

check "CLAUDE.md has GRIST rules" \
  "grep -q 'GRIST.*Always-On\|GRIST:RULES' '$TMPDIR/CLAUDE.md'"

check "CLAUDE.md has banned preambles" \
  "grep -q 'Banned preambles\|preambles' '$TMPDIR/CLAUDE.md'"

check "CLAUDE.md has read discipline" \
  "grep -q 'Read discipline\|read discipline' '$TMPDIR/CLAUDE.md'"

check "CLAUDE.md has address-by-ID" \
  "grep -q 'Address-by-ID\|address-by-ID\|Address by ID' '$TMPDIR/CLAUDE.md'"

# --- Verify: context pack ----------------------------------------------------

check ".grist/context-pack.md exists" \
  "[[ -f '$TMPDIR/.grist/context-pack.md' ]]"

# --- Verify: idempotent re-run -----------------------------------------------

echo
echo "Verifying idempotent re-run..."
"$GRIST_ROOT/bmad-overrides/install-claude-code.sh" "$TMPDIR" 2>&1 > /dev/null

check "Idempotent: PRD still has exactly one GRIST block" \
  "[[ \$(grep -c 'GRIST:BEGIN' '$TMPDIR/.claude/skills/bmad-create-prd/steps-c/step-12-complete.md') -eq 1 ]]"

check "Idempotent: CLAUDE.md still has exactly one GRIST rules section" \
  "[[ \$(grep -c 'GRIST:RULES' '$TMPDIR/CLAUDE.md') -le 2 ]]"

# --- Verify: uninstall -------------------------------------------------------

echo
echo "Verifying uninstall..."
"$GRIST_ROOT/bmad-overrides/install-claude-code.sh" "$TMPDIR" --uninstall 2>&1 > /dev/null

check "Uninstall: PRD step file has no GRIST block" \
  "! grep -q 'GRIST:BEGIN' '$TMPDIR/.claude/skills/bmad-create-prd/steps-c/step-12-complete.md'"

check "Uninstall: CLAUDE.md has no GRIST rules" \
  "! grep -q 'GRIST:RULES' '$TMPDIR/CLAUDE.md'"

# --- Summary -----------------------------------------------------------------

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $FAIL -eq 0 ]]; then
  printf "${GREEN}All %d checks passed.${NC}\n" "$PASS"
else
  printf "${RED}%d of %d checks failed.${NC}\n" "$FAIL" "$((PASS + FAIL))"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ $FAIL -eq 0 ]]
