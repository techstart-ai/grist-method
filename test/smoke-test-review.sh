#!/usr/bin/env bash
# Smoke test for the GRIST review pipeline (/grist review).
#
# Builds a throwaway git repo with a base branch and a feature branch that
# touches code, a lockfile, a generated file, a snapshot and a vendored file,
# then drives:
#   - gristats/grist-diff.py      (orient + classify + read plan)
#   - hooks/diff-discipline.py    (deny whole-PR git diff / gh pr diff)
#   - hooks/session-router.py     (review phase arming, no false positives)
#   - hooks/read-discipline.py    (one read per range in review phase)
#   - gristats/grist-render.py    (YAML → md / GitHub payload / GitLab script)
#
# Usage: ./test/smoke-test-review.sh
# Exit 0 — all checks passed; 1 — one or more failed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRIST_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS="$GRIST_ROOT/hooks"
TOOLS="$GRIST_ROOT/gristats"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
PASS=0
FAIL=0

check() {
  local desc="$1" condition="$2"
  if eval "$condition"; then
    printf "${GREEN}✓${NC} %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "${RED}✗${NC} %s\n" "$desc"; FAIL=$((FAIL + 1))
  fi
}

json_str() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

# --- fixture repo -------------------------------------------------------------

REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT
export CLAUDE_PROJECT_DIR="$REPO"
unset GRIST_NO_HOOKS 2>/dev/null || true
unset GRIST_DIFF_THRESHOLD 2>/dev/null || true

git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name t
mkdir -p "$REPO/src" "$REPO/src/generated" "$REPO/vendor/lib" "$REPO/src/__snapshots__"
printf 'export function a() { return 1 }\n' > "$REPO/src/a.ts"
printf 'export function b() { return 2 }\n' > "$REPO/src/b.ts"
printf 'lock: 1\n' > "$REPO/pnpm-lock.yaml"
printf '// generated\nexport const x = 1\n' > "$REPO/src/generated/api.ts"
printf 'module.exports = 1\n' > "$REPO/vendor/lib/index.js"
printf 'exports[`t`] = `1`\n' > "$REPO/src/__snapshots__/a.test.ts.snap"
printf '*.custom linguist-generated=true\n' > "$REPO/.gitattributes"
printf 'gen\n' > "$REPO/schema.custom"
git -C "$REPO" add -A && git -C "$REPO" commit -qm base

git -C "$REPO" checkout -qb feature
python3 - "$REPO" <<'PY'
import sys, os
root = sys.argv[1]
with open(os.path.join(root, "src/a.ts"), "w") as f:
    f.write("export function a() {\n  try {\n    return fetchToken()\n  } catch (e) {\n    return null\n  }\n}\n")
with open(os.path.join(root, "src/b.ts"), "a") as f:
    f.write("".join("export const k%d = %d\n" % (i, i) for i in range(300)))  # push over threshold
for p, body in (("pnpm-lock.yaml", "lock: 2\n" * 50), ("src/generated/api.ts", "// generated\nexport const x = 2\n"),
                ("vendor/lib/index.js", "module.exports = 2\n"), ("src/__snapshots__/a.test.ts.snap", "exports[`t`] = `2`\n"),
                ("schema.custom", "gen2\n")):
    with open(os.path.join(root, p), "w") as f:
        f.write(body)
PY
git -C "$REPO" add -A && git -C "$REPO" commit -qm feature
cd "$REPO"

# --- grist-diff ---------------------------------------------------------------

OUT="$(python3 "$TOOLS/grist-diff.py" main...feature)"
check "grist-diff: lockfile classified" "echo \"\$OUT\" | grep -q 'pnpm-lock.yaml .*lockfile'"
check "grist-diff: generated dir classified" "echo \"\$OUT\" | grep -q 'src/generated/api.ts .*generated'"
check "grist-diff: vendor classified" "echo \"\$OUT\" | grep -q 'vendor/lib/index.js .*vendor'"
check "grist-diff: snapshot classified" "echo \"\$OUT\" | grep -q 'a.test.ts.snap .*snapshot'"
check "grist-diff: .gitattributes linguist-generated honoured" "echo \"\$OUT\" | grep -q 'schema.custom .*generated'"
check "grist-diff: code files kept" "echo \"\$OUT\" | grep -q 'src/a.ts .*code' && echo \"\$OUT\" | grep -q 'src/b.ts .*code'"
check "grist-diff: skipped_yaml block emitted" "echo \"\$OUT\" | grep -q -- '- {path: pnpm-lock.yaml, reason: lockfile}'"
check "grist-diff: over threshold → per-file plan" "echo \"\$OUT\" | grep -q 'plan (per-file'"
OUT="$(python3 "$TOOLS/grist-diff.py" main...feature --threshold 1000)"
check "grist-diff: under threshold → single diff plan with only code paths" \
  "echo \"\$OUT\" | grep -q 'plan (single' && echo \"\$OUT\" | grep 'plan (single' | grep -q 'src/a.ts src/b.ts' && ! echo \"\$OUT\" | grep 'plan (single' | grep -q 'pnpm-lock'"
OUT="$(python3 "$TOOLS/grist-diff.py" main...feature --json)"
check "grist-diff: --json parses" "echo \"\$OUT\" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"plan_kind\"]==\"per-file\" and len(d[\"skipped\"])==5'"
mkdir -p .grist && printf 'src/b.ts\n' > .grist/review-ignore
OUT="$(python3 "$TOOLS/grist-diff.py" main...feature)"
check "grist-diff: .grist/review-ignore honoured" "echo \"\$OUT\" | grep -q 'src/b.ts .*ignored'"
rm -f .grist/review-ignore

# --- diff-discipline hook -----------------------------------------------------

dd() {  # dd <command>
  printf '{"tool_name": "Bash", "tool_input": {"command": %s}, "cwd": %s}' "$(json_str "$1")" "$(json_str "$REPO")" \
    | python3 "$HOOKS/diff-discipline.py"
}
OUT="$(dd 'git diff main...feature')"
check "diff hook: whole-PR git diff over threshold denied" "echo \"\$OUT\" | grep -q '\"permissionDecision\": \"deny\"'"
check "diff hook: deny names grist-diff and per-file form" "echo \"\$OUT\" | grep -q 'grist-diff.py' && echo \"\$OUT\" | grep -q -- '-U3 main...feature -- <path>'"
check "diff hook: --stat allowed" "[[ -z \"\$(dd 'git diff --stat main...feature')\" ]]"
check "diff hook: --name-only allowed" "[[ -z \"\$(dd 'git diff --name-only main...feature')\" ]]"
check "diff hook: pathspec allowed" "[[ -z \"\$(dd 'git diff -U3 main...feature -- src/a.ts')\" ]]"
check "diff hook: piped through head allowed" "[[ -z \"\$(dd 'git diff main...feature | head -40')\" ]]"
check "diff hook: redirect to file allowed" "[[ -z \"\$(dd 'git diff main...feature > /tmp/x.patch')\" ]]"
check "diff hook: git -C <dir> diff handled" "dd 'git -C $REPO diff main...feature' | grep -q deny"
check "diff hook: small diff allowed whole" "[[ -z \"\$(dd 'git diff main...feature -- src/a.ts src/generated/api.ts' )\" ]] && [[ -z \"\$(GRIST_DIFF_THRESHOLD=100000 dd 'git diff main...feature')\" ]]"
check "diff hook: gh pr diff denied" "dd 'gh pr diff 42' | grep -q 'grist-diff.py --pr'"
check "diff hook: glab mr diff denied" "dd 'glab mr diff 7' | grep -q 'grist-diff.py --mr'"
check "diff hook: gh pr diff --name-only allowed" "[[ -z \"\$(dd 'gh pr diff 42 --name-only')\" ]]"
check "diff hook: non-diff command untouched" "[[ -z \"\$(dd 'git status && git log --oneline -3')\" ]]"
check "diff hook: compound — first segment stat, second denied" "dd 'git diff --stat main...feature && git diff main...feature' | grep -q deny"
check "diff hook: GRIST_NO_HOOKS=1 bypass" "[[ -z \"\$(GRIST_NO_HOOKS=1 dd 'git diff main...feature')\" ]]"

# --- session-router: review phase -----------------------------------------------

STATE="$REPO/.grist/session-state.json"
router() {
  printf '{"prompt": %s, "cwd": %s, "session_id": "sess-review"}' "$(json_str "$1")" "$(json_str "$REPO")" \
    | python3 "$HOOKS/session-router.py"
}
rm -f "$STATE"
OUT="$(router '/grist review 42')"
check "router: /grist review arms review" "grep -q '\"phase\": \"review\"' '$STATE'"
check "router: review context names grist-diff + grist-render" "echo \"\$OUT\" | grep -q 'grist-diff.py' && echo \"\$OUT\" | grep -q 'grist-render.py'"
rm -f "$STATE"; router 'gh pr review 12 --approve' > /dev/null
check "router: gh pr review arms review" "grep -q '\"phase\": \"review\"' '$STATE'"
rm -f "$STATE"; router '/bmad code-review S1.1' > /dev/null
check "router: bmad code-review arms review (not ship)" "grep -q '\"phase\": \"review\"' '$STATE'"
rm -f "$STATE"; router '/bmad dev-story S1.1' > /dev/null
check "router: bmad dev-story still arms ship" "grep -q '\"phase\": \"ship\"' '$STATE'"
rm -f "$STATE"; OUT="$(router 'can you review this function for me?')"
check "router: bare word review arms nothing" "[[ -z \"\$OUT\" && ! -f '$STATE' ]]"
OUT="$(router 'this repo does not use BMAD nor OpenSpec')"
check "router: bare words bmad/openspec arm nothing" "[[ -z \"\$OUT\" && ! -f '$STATE' ]]"
router '/opsx propose x' > /dev/null
check "router: /opsx still arms iterate" "grep -q '\"phase\": \"iterate\"' '$STATE'"
rm -f "$STATE"

# --- read-discipline: one read per range in review phase --------------------------

printf '{"phase": "review", "recalled": []}\n' > "$STATE"
rd() {  # rd <path> <extra-json>
  printf '{"tool_name": "Read", "tool_input": {"file_path": %s%s}, "cwd": %s}' "$(json_str "$1")" "$2" "$(json_str "$REPO")" \
    | python3 "$HOOKS/read-discipline.py"
}
check "read hook: first range read allowed" "[[ -z \"\$(rd '$REPO/src/b.ts' ', \"offset\": 1, \"limit\": 40')\" ]]"
OUT="$(rd "$REPO/src/b.ts" ', "offset": 1, "limit": 40')"
check "read hook: identical re-read denied in review phase" "echo \"\$OUT\" | grep -q 'already read this session'"
check "read hook: different range allowed" "[[ -z \"\$(rd '$REPO/src/b.ts' ', \"offset\": 41, \"limit\": 40')\" ]]"
printf '{"phase": "ship", "recalled": []}\n' > "$STATE"
check "read hook: re-read allowed outside review phase" "[[ -z \"\$(rd '$REPO/src/b.ts' ', \"offset\": 41, \"limit\": 40')\" ]] && [[ -z \"\$(rd '$REPO/src/b.ts' ', \"offset\": 41, \"limit\": 40')\" ]]"
rm -f "$STATE"

# --- grist-render -------------------------------------------------------------------

EX="$GRIST_ROOT/schemas/examples/review-pr.example.grist.yaml"
OUT="$(python3 "$TOOLS/grist-render.py" "$EX")"
check "render md: verdict is a sentence" "echo \"\$OUT\" | grep -q '^## Review: Token exchange error handling must be fixed before merge; rest is sound.$'"
check "render md: zone red → Request changes" "echo \"\$OUT\" | grep -q 'decision: \*\*Request changes\*\*'"
check "render md: finding carries loc + fix sentence" "echo \"\$OUT\" | grep -q 'src/auth/okta.ts:42' && echo \"\$OUT\" | grep -q 'Suggested fix: Re-throw'"
check "render md: paths in verified not capitalised" "echo \"\$OUT\" | grep -q 'config/env.ts:12'"
check "render md: skipped listed" "echo \"\$OUT\" | grep -q 'pnpm-lock.yaml. — lockfile\|pnpm-lock.yaml\` — lockfile'"
check "render md: handoff checklist" "echo \"\$OUT\" | grep -q -- '- \[ \] \*\*platform\*\*'"

OUTDIR="$REPO/render-out"
OUT="$(python3 "$TOOLS/grist-render.py" "$EX" --target github --out "$OUTDIR")"
check "render github: dry run, no post" "echo \"\$OUT\" | grep -q 'dry run'"
check "render github: gh api command targets repo/pr from pr: field" "echo \"\$OUT\" | grep -q 'gh api --method POST repos/acme/shop/pulls/42/reviews --input'"
check "render github: payload event + 3 inline comments" \
  "python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d[\"event\"]==\"REQUEST_CHANGES\"; assert len(d[\"comments\"])==3; assert d[\"comments\"][0][\"path\"]==\"src/auth/okta.ts\" and d[\"comments\"][0][\"line\"]==42 and d[\"comments\"][0][\"side\"]==\"RIGHT\"' '$OUTDIR/review-pr.example.github.json'"

OUT="$(python3 "$TOOLS/grist-render.py" "$EX" --target gitlab --out "$OUTDIR" --number 42)"
check "render gitlab: script written" "[[ -x '$OUTDIR/review-pr.example.gitlab.sh' ]]"
check "render gitlab: note + 3 discussions, no approve for red" \
  "grep -c 'merge_requests/42/discussions' '$OUTDIR/review-pr.example.gitlab.sh' | grep -q '^3$' && grep -q 'glab mr note 42' '$OUTDIR/review-pr.example.gitlab.sh' && ! grep -q 'mr approve' '$OUTDIR/review-pr.example.gitlab.sh'"
check "render gitlab: inline position uses head sha + new_line" "grep -q 'position\[head_sha\]=b7e41d0' '$OUTDIR/review-pr.example.gitlab.sh' && grep -q 'position\[new_line\]=42' '$OUTDIR/review-pr.example.gitlab.sh'"

# green zone → APPROVE / glab mr approve; dismissed findings never posted
cat > "$REPO/review-pr-7.grist.yaml" <<'YAML'
review: pr-7
date: 2026-09-06
verdict: looks good
zone: green
pr: acme/shop#7
findings:
  - id: f1
    class: dismiss
    severity: low
    loc: src/x.ts:3
    title: style nit
    detail: not worth a comment
counts: {decision_needed: 0, patch: 0, defer: 0, dismissed: 1}
YAML
python3 "$TOOLS/grist-render.py" "$REPO/review-pr-7.grist.yaml" --target github --out "$OUTDIR" > /dev/null
check "render github: green → APPROVE, dismissed not posted" \
  "python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d[\"event\"]==\"APPROVE\" and d[\"comments\"]==[]' '$OUTDIR/review-pr-7.github.json'"
python3 "$TOOLS/grist-render.py" "$REPO/review-pr-7.grist.yaml" --target gitlab --out "$OUTDIR" > /dev/null
check "render gitlab: green → glab mr approve" "grep -q 'glab mr approve 7' '$OUTDIR/review-pr-7.gitlab.sh'"

# BMAD-style example still renders (story-bound keys optional)
OUT="$(python3 "$TOOLS/grist-render.py" "$GRIST_ROOT/schemas/examples/review.example.grist.yaml")"
check "render md: BMAD review example renders with ac_ref sentence" "echo \"\$OUT\" | grep -q 'This violates acceptance criterion ac3.'"

# validate-grist-yaml accepts the new example
OUT="$(printf '{"tool_name": "Write", "tool_input": {"file_path": %s}}' "$(json_str "$EX")" | python3 "$HOOKS/validate-grist-yaml.py")"
check "validator: standalone review example passes" "[[ -z \"\$OUT\" ]]"

# --- Result -------------------------------------------------------------------

echo
echo "─────────────────────────────────────"
printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
echo "─────────────────────────────────────"
[[ $FAIL -eq 0 ]]
