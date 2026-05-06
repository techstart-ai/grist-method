#!/usr/bin/env bash
# Smoke test for grist-method OpenSpec Claude Code installer.
#
# Creates a temporary mock project with OpenSpec + Claude Code command structure,
# runs the installer, and verifies all injection targets are present.
#
# Usage: ./test/smoke-test-openspec.sh
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

# --- Setup: create mock OpenSpec + Claude Code project ----------------------

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Creating mock OpenSpec project at: $TMPDIR"
echo

# OpenSpec directory structure
mkdir -p "$TMPDIR/openspec/specs/auth-login"
mkdir -p "$TMPDIR/openspec/specs/user-profile"
mkdir -p "$TMPDIR/openspec/schemas"
mkdir -p "$TMPDIR/.claude/commands"

# Mock opsx command files (Claude Code slash commands)
cat > "$TMPDIR/.claude/commands/opsx-propose.md" << 'EOF'
---
description: "Propose an OpenSpec change"
---

Propose a change to the OpenSpec: $ARGUMENTS

Generate the following artifacts:
- proposal.md: describes the change
- design.md: technical design
- tasks.md: task list
EOF

cat > "$TMPDIR/.claude/commands/opsx-apply.md" << 'EOF'
---
description: "Apply an OpenSpec change"
---

Apply the change: $ARGUMENTS

Read the change folder and execute all tasks.
Operating mode: implement carefully.
EOF

cat > "$TMPDIR/.claude/commands/opsx-archive.md" << 'EOF'
---
description: "Archive a completed change"
---

Archive the change: $ARGUMENTS

Merge deltas into specs and move to archive folder.
EOF

# Mock prose specs (should trigger migration hint)
cat > "$TMPDIR/openspec/specs/auth-login/spec.md" << 'EOF'
# Auth Login

## Purpose
Handles authentication.

### Requirement: MFA required
The system SHALL require MFA for all logins.

#### Scenario: Login with MFA
- **WHEN** user provides credentials
- **THEN** system requires MFA code
EOF

cat > "$TMPDIR/openspec/specs/user-profile/spec.md" << 'EOF'
# User Profile

## Purpose
User profile management.

### Requirement: Profile editable
The system SHALL allow users to edit their profiles.
EOF

# CLAUDE.md
cat > "$TMPDIR/CLAUDE.md" << 'EOF'
# Project Configuration

OpenSpec project.
EOF

# --- Run installer ----------------------------------------------------------

echo "Running installer..."
echo
"$GRIST_ROOT/openspec-overrides/install-claude-code.sh" "$TMPDIR" 2>&1 || {
  printf "\n${RED}Installer failed!${NC}\n"
  exit 1
}

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Verification checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# --- Verify: schema files ---------------------------------------------------

check "OpenSpec grist schema installed" \
  "[[ -f '$TMPDIR/openspec/schemas/grist/schema.yaml' ]]"

check "OpenSpec spec-to-grist script installed" \
  "[[ -f '$TMPDIR/openspec/scripts/openspec-spec-to-grist.py' ]]"

check "OpenSpec change template installed" \
  "[[ -f '$TMPDIR/openspec/schemas/grist/templates/change.grist.yaml' ]]"

check "OpenSpec tasks template installed" \
  "[[ -f '$TMPDIR/openspec/schemas/grist/templates/tasks.md' ]]"

check "OpenSpec config.yaml created" \
  "[[ -f '$TMPDIR/openspec/config.yaml' ]]"

check "OpenSpec config.yaml activates grist schema" \
  "grep -q 'schema.*grist\|grist' '$TMPDIR/openspec/config.yaml'"

# --- Verify: command injections ---------------------------------------------

check "opsx-propose has GRIST block" \
  "grep -q 'GRIST:BEGIN' '$TMPDIR/.claude/commands/opsx-propose.md'"

check "opsx-propose emits change.grist.yaml" \
  "grep -q 'change.grist.yaml' '$TMPDIR/.claude/commands/opsx-propose.md'"

check "opsx-apply has GRIST block" \
  "grep -q 'GRIST:BEGIN' '$TMPDIR/.claude/commands/opsx-apply.md'"

check "opsx-apply activates grist ship mode" \
  "grep -q 'ship mode\|grist ship\|No preambles\|no preambles' '$TMPDIR/.claude/commands/opsx-apply.md'"

check "opsx-archive has GRIST block" \
  "grep -q 'GRIST:BEGIN' '$TMPDIR/.claude/commands/opsx-archive.md'"

check "opsx-archive handles YAML delta merge" \
  "grep -q 'grist.yaml\|YAML merge\|yaml merge\|structural' '$TMPDIR/.claude/commands/opsx-archive.md'"

# --- Verify: grist command --------------------------------------------------

check "grist command (MD) installed" \
  "[[ -f '$TMPDIR/.claude/commands/grist.md' ]]"

# --- Verify: CLAUDE.md rules ------------------------------------------------

check "CLAUDE.md has GRIST rules" \
  "grep -q 'GRIST.*Always-On\|GRIST:RULES' '$TMPDIR/CLAUDE.md'"

check "CLAUDE.md has read discipline" \
  "grep -q 'Read discipline\|read discipline' '$TMPDIR/CLAUDE.md'"

# --- Verify: context pack ---------------------------------------------------

check ".grist/context-pack.md exists" \
  "[[ -f '$TMPDIR/.grist/context-pack.md' ]]"

# --- Verify: idempotent re-run ----------------------------------------------

echo
echo "Verifying idempotent re-run..."
"$GRIST_ROOT/openspec-overrides/install-claude-code.sh" "$TMPDIR" 2>&1 > /dev/null

check "Idempotent: opsx-apply has exactly one GRIST block" \
  "[[ \$(grep -c 'GRIST:BEGIN' '$TMPDIR/.claude/commands/opsx-apply.md') -eq 1 ]]"

check "Idempotent: CLAUDE.md has only one GRIST rules section" \
  "[[ \$(grep -c 'GRIST:RULES' '$TMPDIR/CLAUDE.md') -le 2 ]]"

# --- Verify: uninstall ------------------------------------------------------

echo
echo "Verifying uninstall..."
"$GRIST_ROOT/openspec-overrides/install-claude-code.sh" "$TMPDIR" --uninstall 2>&1 > /dev/null

check "Uninstall: opsx-propose has no GRIST block" \
  "! grep -q 'GRIST:BEGIN' '$TMPDIR/.claude/commands/opsx-propose.md'"

check "Uninstall: opsx-apply has no GRIST block" \
  "! grep -q 'GRIST:BEGIN' '$TMPDIR/.claude/commands/opsx-apply.md'"

# --- Verify: combined install.sh with --openspec flag -----------------------

echo
echo "Verifying combined install.sh --openspec flag..."

# Create a project with BOTH BMAD skills and OpenSpec
COMBINED_TMPDIR=$(mktemp -d)
trap 'rm -rf "$COMBINED_TMPDIR"' EXIT

mkdir -p "$COMBINED_TMPDIR/.claude/skills/bmad-create-prd/steps"
mkdir -p "$COMBINED_TMPDIR/.claude/skills/bmad-create-architecture/steps"
mkdir -p "$COMBINED_TMPDIR/.claude/skills/bmad-create-story/steps"
mkdir -p "$COMBINED_TMPDIR/.claude/skills/bmad-dev-story"
mkdir -p "$COMBINED_TMPDIR/.claude/skills/bmad-code-review/steps"
mkdir -p "$COMBINED_TMPDIR/.claude/commands"
mkdir -p "$COMBINED_TMPDIR/openspec/specs"

# Minimal step files
for f in \
  ".claude/skills/bmad-create-prd/steps/step-12-complete.md" \
  ".claude/skills/bmad-create-architecture/steps/step-08.md" \
  ".claude/skills/bmad-create-story/steps/step-06.md" \
  ".claude/skills/bmad-dev-story/workflow.md" \
  ".claude/skills/bmad-code-review/steps/step-04-present.md"
do
  printf '# Step\n\n## EXECUTION PROTOCOLS:\n\nDone.\n' > "$COMBINED_TMPDIR/$f"
done

# Mock opsx commands
for cmd in propose apply archive; do
  printf '# /opsx:%s\n\nRead context.\n' "$cmd" > "$COMBINED_TMPDIR/.claude/commands/opsx-${cmd}.md"
done

cat > "$COMBINED_TMPDIR/CLAUDE.md" << 'EOF'
# Combined Project
EOF

"$GRIST_ROOT/install.sh" "$COMBINED_TMPDIR" --openspec 2>&1 > /dev/null

check "Combined: BMAD PRD step injected" \
  "grep -q 'GRIST:BEGIN' '$COMBINED_TMPDIR/.claude/skills/bmad-create-prd/steps/step-12-complete.md'"

check "Combined: OpenSpec schema installed" \
  "[[ -f '$COMBINED_TMPDIR/openspec/schemas/grist/schema.yaml' ]]"

check "Combined: opsx-apply has GRIST block" \
  "grep -q 'GRIST:BEGIN' '$COMBINED_TMPDIR/.claude/commands/opsx-apply.md'"

check "Combined: CLAUDE.md has GRIST rules" \
  "grep -q 'GRIST:RULES' '$COMBINED_TMPDIR/CLAUDE.md'"

# --- Summary ----------------------------------------------------------------

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $FAIL -eq 0 ]]; then
  printf "${GREEN}All %d checks passed.${NC}\n" "$PASS"
else
  printf "${RED}%d of %d checks failed.${NC}\n" "$FAIL" "$((PASS + FAIL))"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ $FAIL -eq 0 ]]
