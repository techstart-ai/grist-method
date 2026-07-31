#!/usr/bin/env bash
# Smoke test for GRIST auto-activation + recall hooks.
#
# Drives session-router.py, activity-sniff.py, read-discipline.py, and
# recall.py with synthetic hook payloads against a temp project, then runs
# `gristats recall` on the produced log.
#
# Usage: ./test/smoke-test-autoactivate.sh
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRIST_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS="$GRIST_ROOT/hooks"

RED='\033[0;31m'
GREEN='\033[0;32m'
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

# --- Setup: temp project ----------------------------------------------------

PROJECT="$(mktemp -d)"
trap 'rm -rf "$PROJECT"' EXIT
export CLAUDE_PROJECT_DIR="$PROJECT"
unset GRIST_NO_HOOKS 2>/dev/null || true

STATE="$PROJECT/.grist/session-state.json"

router() {  # router <prompt>
  printf '{"prompt": %s, "cwd": %s, "session_id": "sess-test"}' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")" \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$PROJECT")" \
    | python3 "$HOOKS/session-router.py"
}

# --- session-router ----------------------------------------------------------

OUT="$(router '/bmad:bmm:workflows:create-prd for auth')"
check "router: BMAD planning cmd arms design" "[[ -f '$STATE' ]] && grep -q '\"phase\": \"design\"' '$STATE'"
check "router: full context injected on arm" "echo \"\$OUT\" | grep -q 'design mode auto-active'"

OUT="$(router 'continue please')"
check "router: reminder re-injected next prompt" "echo \"\$OUT\" | grep -q 'design mode active'"

OUT="$(router '/bmad dev-story S1.1')"
check "router: dev-story switches to ship" "grep -q '\"phase\": \"ship\"' '$STATE'"

OUT="$(router 'stop grist')"
check "router: stop grist clears state" "[[ ! -f '$STATE' ]]"
check "router: off message emitted" "echo \"\$OUT\" | grep -qi 'GRIST mode off'"

OUT="$(router '/opsx propose new-change')"
check "router: opsx arms iterate" "grep -q '\"phase\": \"iterate\"' '$STATE'"
rm -f "$STATE"

OUT="$(router 'what does this function do?')"
check "router: plain chat injects nothing" "[[ -z \"\$OUT\" && ! -f '$STATE' ]]"

# --- activity-sniff -----------------------------------------------------------

sniff() {  # sniff <tool> <path>
  printf '{"tool_name": "%s", "tool_input": {"file_path": "%s"}, "cwd": "%s", "session_id": "sess-test"}' \
    "$1" "$2" "$PROJECT" | python3 "$HOOKS/activity-sniff.py"
}

sniff Read "$PROJECT/_bmad-output/story-S1.1.grist.yaml" > /dev/null
check "sniff: story read arms ship" "grep -q '\"phase\": \"ship\"' '$STATE'"
sniff Write "$PROJECT/_bmad-output/PRD.md" > /dev/null
check "sniff: existing state not overwritten" "grep -q '\"phase\": \"ship\"' '$STATE'"
rm -f "$STATE"
sniff Write "$PROJECT/openspec/changes/foo.md" > /dev/null
check "sniff: openspec write arms iterate" "grep -q '\"phase\": \"iterate\"' '$STATE'"
rm -f "$STATE"
sniff Read "$PROJECT/src/app.ts" > /dev/null
check "sniff: non-workflow path arms nothing" "[[ ! -f '$STATE' ]]"

# --- read-discipline: prose-sibling deny --------------------------------------

mkdir -p "$PROJECT/_bmad-output"
printf 'prd: auth\ngoal: test goal\nepics:\n  - id: E1\n    title: Login\n' > "$PROJECT/_bmad-output/PRD.grist.yaml"
printf '# PRD\n\nLong prose here.\n' > "$PROJECT/_bmad-output/PRD.md"

discipline() {  # discipline <extra-input-json-fragment>
  printf '{"tool_name": "Read", "tool_input": {"file_path": "%s"%s}}' \
    "$PROJECT/_bmad-output/PRD.md" "$1" | python3 "$HOOKS/read-discipline.py"
}

OUT="$(discipline '')"
check "discipline: prose with YAML sibling denied" "echo \"\$OUT\" | grep -q '\"permissionDecision\": \"deny\"'"
check "discipline: deny names the sibling" "echo \"\$OUT\" | grep -q 'PRD.grist.yaml'"
OUT="$(discipline ', "offset": 1, "limit": 20')"
check "discipline: range read escapes sibling deny" "[[ -z \"\$OUT\" ]]"

# --- recall -------------------------------------------------------------------

printf 'story: S1.1\nepic: prd#E1\ntasks:\n  - id: t1\n    do: implement login\n' \
  > "$PROJECT/_bmad-output/story-S1.1.grist.yaml"
printf '{"phase": "ship", "recalled": []}\n' > "$STATE"

recall() {
  printf '{"tool_name": "Read", "tool_input": {"file_path": "%s"}, "cwd": "%s", "session_id": "sess-test"}' \
    "$PROJECT/_bmad-output/story-S1.1.grist.yaml" "$PROJECT" | python3 "$HOOKS/recall.py"
}

OUT="$(recall)"
check "recall: injects resolved slice" "echo \"\$OUT\" | grep -q 'GRIST recall'"
check "recall: slice contains ref content" "echo \"\$OUT\" | grep -q 'Login'"
check "recall: log written" "[[ -f '$PROJECT/.grist/recall.log' ]] && grep -q '\"ref\": \"prd#E1\"' '$PROJECT/.grist/recall.log'"
OUT="$(recall)"
check "recall: same ref not injected twice per session" "[[ -z \"\$OUT\" ]]"

# --- gristats recall ----------------------------------------------------------

OUT="$(python3 "$GRIST_ROOT/gristats/gristats.py" recall --dir "$PROJECT")"
check "gristats recall: reports injections" "echo \"\$OUT\" | grep -q 'injections: 1 (1 resolved'"
check "gristats recall: lists top refs" "echo \"\$OUT\" | grep -q 'prd#E1'"

# --- escape hatch -------------------------------------------------------------

OUT="$(GRIST_NO_HOOKS=1 router '/bmad create-prd' )"
check "GRIST_NO_HOOKS=1 disables router" "[[ -z \"\$OUT\" ]]"

# --- Result -------------------------------------------------------------------

echo
echo "─────────────────────────────────────"
printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
echo "─────────────────────────────────────"
[[ $FAIL -eq 0 ]]
