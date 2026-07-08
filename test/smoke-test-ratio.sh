#!/usr/bin/env bash
# Smoke test for the GRIST compression claim.
#
# Runs gristats against the bundled auth-v2 example and verifies that the
# prose → grist token ratio actually backs the pitch: at least one
# .md ↔ .grist.yaml pair must be found, and the overall ratio must be ≥ 3.0×.
#
# Usage: ./test/smoke-test-ratio.sh
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

MIN_RATIO="3.0"
EXAMPLE_DIR="$GRIST_ROOT/examples/auth-v2"

echo "Running gristats against: $EXAMPLE_DIR"
echo

OUTPUT="$(python3 "$GRIST_ROOT/gristats/gristats.py" project "$EXAMPLE_DIR")" || {
  printf "${RED}gristats failed to run!${NC}\n"
  exit 1
}

echo "$OUTPUT"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Verification checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# --- Verify: at least one prose ↔ grist pair found ---------------------------

PAIRS="$(echo "$OUTPUT" | sed -n 's/^found:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"

check "gristats reports a 'found:' line" \
  "[[ -n '$PAIRS' ]]"

check "at least 1 prose ↔ grist pair found (got: ${PAIRS:-0})" \
  "[[ -n '$PAIRS' && '$PAIRS' -ge 1 ]]"

# --- Verify: overall ratio meets the compression claim ------------------------

RATIO="$(echo "$OUTPUT" | sed -n 's/^overall ratio:[[:space:]]*\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"

check "gristats reports an 'overall ratio' line" \
  "[[ -n '$RATIO' ]]"

check "overall ratio ≥ ${MIN_RATIO}× (got: ${RATIO:-none}×)" \
  "[[ -n '$RATIO' ]] && awk -v r='$RATIO' -v m='$MIN_RATIO' 'BEGIN { exit !(r >= m) }'"

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
