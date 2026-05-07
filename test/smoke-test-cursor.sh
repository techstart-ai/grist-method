#!/usr/bin/env bash
# Smoke test for grist-method Cursor installer.
#
# Creates a temporary mock project with BMAD Cursor skills structure,
# runs the installer, and verifies all injection targets are present.
#
# Usage: ./test/smoke-test-cursor.sh
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

# --- Setup: create mock Cursor + BMAD project -------------------------------

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Creating mock Cursor + BMAD project at: $TMPDIR"
echo

# Create mock BMAD skills directory structure (mirrors Claude Code layout)
mkdir -p "$TMPDIR/.cursor/skills/bmad-create-prd/steps-c"
mkdir -p "$TMPDIR/.cursor/skills/bmad-create-architecture/steps"
mkdir -p "$TMPDIR/.cursor/skills/bmad-create-story/steps"
mkdir -p "$TMPDIR/.cursor/skills/bmad-dev-story"
mkdir -p "$TMPDIR/.cursor/skills/bmad-code-review/steps"
mkdir -p "$TMPDIR/.cursor/rules"
mkdir -p "$TMPDIR/_bmad"

# Create mock step files (identical to Claude Code structure)
cat > "$TMPDIR/.cursor/skills/bmad-create-prd/steps-c/step-12-complete.md" << 'EOF'
# Step 12: Complete PRD

Finalize the PRD document.

## EXECUTION PROTOCOLS:

Run the final validation checks.
EOF

cat > "$TMPDIR/.cursor/skills/bmad-create-architecture/steps/step-08-complete.md" << 'EOF'
# Step 8: Complete Architecture

## HALT

Wait for user review.
EOF

cat > "$TMPDIR/.cursor/skills/bmad-create-story/steps/step-06-complete.md" << 'EOF'
# Step 6: Complete Story

## EXECUTION PROTOCOLS:

Validate the story.
EOF

cat > "$TMPDIR/.cursor/skills/bmad-dev-story/workflow.md" << 'EOF'
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

cat > "$TMPDIR/.cursor/skills/bmad-code-review/steps/step-04-present.md" << 'EOF'
# Step 4: Present Findings

Present the triaged findings to the user.

#### Completion summary

Summarize the review.
EOF

# Create AGENTS.md (Cursor's equivalent of CLAUDE.md)
cat > "$TMPDIR/AGENTS.md" << 'EOF'
# Project Configuration

This is a test project.
EOF

# --- Run installer ----------------------------------------------------------

echo "Running Cursor installer..."
echo
"$GRIST_ROOT/bmad-overrides/install-cursor.sh" "$TMPDIR" 2>&1 || {
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
  "grep -q 'GRIST:BEGIN' '$TMPDIR/.cursor/skills/bmad-create-prd/steps-c/step-12-complete.md'"

check "PRD step file has emission instruction" \
  "grep -q 'prd.grist.yaml' '$TMPDIR/.cursor/skills/bmad-create-prd/steps-c/step-12-complete.md'"

check "Architecture step file has GRIST block" \
  "grep -q 'GRIST:BEGIN' '$TMPDIR/.cursor/skills/bmad-create-architecture/steps/step-08-complete.md'"

check "Story step file has GRIST block" \
  "grep -q 'GRIST:BEGIN' '$TMPDIR/.cursor/skills/bmad-create-story/steps/step-06-complete.md'"

check "Dev-story workflow has GRIST load block" \
  "grep -q 'GRIST:BEGIN:LOAD' '$TMPDIR/.cursor/skills/bmad-dev-story/workflow.md'"

check "Dev-story workflow has GRIST complete block" \
  "grep -q 'GRIST:BEGIN:COMPLETE' '$TMPDIR/.cursor/skills/bmad-dev-story/workflow.md'"

check "Code-review step file has GRIST block" \
  "grep -q 'GRIST:BEGIN' '$TMPDIR/.cursor/skills/bmad-code-review/steps/step-04-present.md'"

# --- Verify: skill and .mdc rule --------------------------------------------

check "Grist SKILL.md installed at .cursor/skills/" \
  "[[ -f '$TMPDIR/.cursor/skills/grist/SKILL.md' ]]"

check "Grist .mdc rule installed at .cursor/rules/" \
  "[[ -f '$TMPDIR/.cursor/rules/grist.mdc' ]]"

check "Grist .mdc has alwaysApply: true" \
  "grep -q 'alwaysApply: true' '$TMPDIR/.cursor/rules/grist.mdc'"

# --- Verify: AGENTS.md rules ------------------------------------------------

check "AGENTS.md has GRIST rules" \
  "grep -q 'GRIST.*Always-On\|GRIST:RULES' '$TMPDIR/AGENTS.md'"

check "AGENTS.md has banned preambles" \
  "grep -q 'Banned preambles\|preambles' '$TMPDIR/AGENTS.md'"

check "AGENTS.md has read discipline" \
  "grep -q 'Read discipline\|read discipline' '$TMPDIR/AGENTS.md'"

check "AGENTS.md has address-by-ID" \
  "grep -q 'Address-by-ID\|address-by-ID\|Address by ID' '$TMPDIR/AGENTS.md'"

# --- Verify: context pack ---------------------------------------------------

check ".grist/context-pack.md exists" \
  "[[ -f '$TMPDIR/.grist/context-pack.md' ]]"

# --- Verify: idempotent re-run ----------------------------------------------

echo
echo "Verifying idempotent re-run..."
"$GRIST_ROOT/bmad-overrides/install-cursor.sh" "$TMPDIR" 2>&1 > /dev/null

check "Idempotent: PRD still has exactly one GRIST block" \
  "[[ \$(grep -c 'GRIST:BEGIN' '$TMPDIR/.cursor/skills/bmad-create-prd/steps-c/step-12-complete.md') -eq 1 ]]"

check "Idempotent: AGENTS.md still has exactly one GRIST rules section" \
  "[[ \$(grep -c 'GRIST:RULES' '$TMPDIR/AGENTS.md') -le 2 ]]"

# --- Verify: uninstall -------------------------------------------------------

echo
echo "Verifying uninstall..."
"$GRIST_ROOT/bmad-overrides/install-cursor.sh" "$TMPDIR" --uninstall 2>&1 > /dev/null

check "Uninstall: PRD step file has no GRIST block" \
  "! grep -q 'GRIST:BEGIN' '$TMPDIR/.cursor/skills/bmad-create-prd/steps-c/step-12-complete.md'"

check "Uninstall: AGENTS.md has no GRIST rules" \
  "! grep -q 'GRIST:RULES' '$TMPDIR/AGENTS.md'"

check "Uninstall: .cursor/rules/grist.mdc removed" \
  "[[ ! -f '$TMPDIR/.cursor/rules/grist.mdc' ]]"

# --- Verify: main installer auto-detection ----------------------------------

echo
echo "Verifying main installer auto-detection..."

# Re-create project for main installer test
"$GRIST_ROOT/bmad-overrides/install-cursor.sh" "$TMPDIR" 2>&1 > /dev/null
rm -f "$TMPDIR/.grist/version"

# Run main installer — should auto-detect Cursor
DETECT_OUTPUT_FILE=$(mktemp)
"$GRIST_ROOT/install.sh" "$TMPDIR" --force > "$DETECT_OUTPUT_FILE" 2>&1 || true

check "Main installer detects Cursor mode" \
  "grep -qi 'cursor' '$DETECT_OUTPUT_FILE'"
rm -f "$DETECT_OUTPUT_FILE"

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
