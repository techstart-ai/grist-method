#!/usr/bin/env bash
# Install GRIST BMAD overlays into a project.
#
# Usage: ./install-bmad.sh <project-root> [options]
#
# Auto-detects your BMAD variant. Use a flag to force a specific variant.
#
# Options:
#   --claude-code   Force Claude Code skills installer
#   --cursor        Force Cursor skills installer
#   --antigravity   Force Antigravity skills installer
#   --bmad-npm      Force BMAD npm/framework installer
#   --dry-run       Show what would be done without modifying files
#   --uninstall     Remove GRIST BMAD overlays
#   -h, --help      Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BMAD_OVERRIDES="$SCRIPT_DIR/bmad-overrides"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
  echo "usage: $0 <project-root> [options]"
  echo
  echo "Installs GRIST BMAD overlays. Auto-detects your BMAD variant."
  echo
  echo "Options:"
  echo "  --claude-code   Force Claude Code skills installer"
  echo "  --cursor        Force Cursor skills installer"
  echo "  --antigravity   Force Antigravity skills installer"
  echo "  --bmad-npm      Force BMAD npm/framework installer"
  echo "  --dry-run       Show what would be done without modifying files"
  echo "  --uninstall     Remove GRIST BMAD overlays"
  echo "  -h, --help      Show this help"
  exit 2
}

# --- Argument parsing -------------------------------------------------------

PROJECT_ROOT=""
FORCE_MODE=""
EXTRA_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --claude-code)  FORCE_MODE="claude-code" ;;
    --cursor)       FORCE_MODE="cursor" ;;
    --antigravity)  FORCE_MODE="antigravity" ;;
    --bmad-npm)     FORCE_MODE="bmad-npm" ;;
    --dry-run)      EXTRA_ARGS+=("--dry-run") ;;
    --uninstall)    EXTRA_ARGS+=("--uninstall") ;;
    --help|-h)      usage ;;
    *)
      if [[ -z "$PROJECT_ROOT" ]]; then
        PROJECT_ROOT="$(cd "$arg" 2>/dev/null && pwd)" || {
          echo "error: directory not found: $arg" >&2
          exit 1
        }
      else
        EXTRA_ARGS+=("$arg")
      fi
      ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  usage
fi

# --- Detection --------------------------------------------------------------

HAS_CLAUDE_CODE=false
HAS_CURSOR=false
HAS_ANTIGRAVITY=false
HAS_BMAD_NPM=false

[[ -d "$PROJECT_ROOT/.claude/skills/bmad-create-prd" ]] && HAS_CLAUDE_CODE=true
[[ -d "$PROJECT_ROOT/.claude/skills/bmad-create-architecture" ]] && HAS_CLAUDE_CODE=true
[[ -d "$PROJECT_ROOT/.cursor/skills/bmad-create-prd" ]] && HAS_CURSOR=true
[[ -d "$PROJECT_ROOT/.cursor/skills/bmad-create-architecture" ]] && HAS_CURSOR=true
[[ -d "$PROJECT_ROOT/.agents/skills/bmad-create-prd" ]] && HAS_ANTIGRAVITY=true
[[ -d "$PROJECT_ROOT/.agents/skills/bmad-create-architecture" ]] && HAS_ANTIGRAVITY=true
[[ -f "$PROJECT_ROOT/_bmad/bmm/config.yaml" ]] && HAS_BMAD_NPM=true
[[ -d "$PROJECT_ROOT/_bmad" && ! -d "$PROJECT_ROOT/.claude/skills" && ! -d "$PROJECT_ROOT/.cursor/skills" && ! -d "$PROJECT_ROOT/.agents/skills" ]] && HAS_BMAD_NPM=true

MODE="${FORCE_MODE:-}"

if [[ -z "$MODE" ]]; then
  if $HAS_CLAUDE_CODE && $HAS_CURSOR; then
    printf "${YELLOW}⚠${NC} Both Claude Code and Cursor skills detected.\n"
    printf "  Using Claude Code installer (takes precedence).\n"
    printf "  Use --cursor to force the Cursor installer.\n\n"
    MODE="claude-code"
  elif $HAS_CLAUDE_CODE && $HAS_BMAD_NPM; then
    printf "${YELLOW}⚠${NC} Both Claude Code skills and BMAD npm/framework detected.\n"
    printf "  Using Claude Code installer.\n"
    printf "  Use --bmad-npm to force the TOML-based installer.\n\n"
    MODE="claude-code"
  elif $HAS_CURSOR && $HAS_BMAD_NPM; then
    printf "${YELLOW}⚠${NC} Both Cursor skills and BMAD npm/framework detected.\n"
    printf "  Using Cursor installer.\n"
    printf "  Use --bmad-npm to force the TOML-based installer.\n\n"
    MODE="cursor"
  elif $HAS_ANTIGRAVITY && $HAS_BMAD_NPM; then
    printf "${YELLOW}⚠${NC} Both Antigravity skills and BMAD npm/framework detected.\n"
    printf "  Using Antigravity installer.\n"
    printf "  Use --bmad-npm to force the TOML-based installer.\n\n"
    MODE="antigravity"
  elif $HAS_CLAUDE_CODE; then
    MODE="claude-code"
  elif $HAS_CURSOR; then
    MODE="cursor"
  elif $HAS_ANTIGRAVITY; then
    MODE="antigravity"
  elif $HAS_BMAD_NPM; then
    MODE="bmad-npm"
  else
    printf "${RED}✗${NC} Cannot detect BMAD variant at: %s\n" "$PROJECT_ROOT" >&2
    echo "" >&2
    echo "Expected one of:" >&2
    echo "  • .claude/skills/bmad-create-prd/  (Claude Code skills)" >&2
    echo "  • .cursor/skills/bmad-create-prd/  (Cursor skills)" >&2
    echo "  • .agents/skills/bmad-create-prd/  (Antigravity skills)" >&2
    echo "  • _bmad/bmm/config.yaml            (BMAD npm/framework)" >&2
    echo "" >&2
    echo "Use --claude-code, --cursor, --antigravity, or --bmad-npm to force a mode." >&2
    exit 1
  fi
fi

# --- Run installer ----------------------------------------------------------

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "${BLUE}GRIST BMAD installer${NC} — mode: ${GREEN}%s${NC}\n" "$MODE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

case "$MODE" in
  claude-code)
    "$BMAD_OVERRIDES/install-claude-code.sh" "$PROJECT_ROOT" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
    ;;
  cursor)
    "$BMAD_OVERRIDES/install-cursor.sh" "$PROJECT_ROOT" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
    ;;
  antigravity)
    "$BMAD_OVERRIDES/install-antigravity.sh" "$PROJECT_ROOT" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
    ;;
  bmad-npm)
    "$BMAD_OVERRIDES/install.sh" "$PROJECT_ROOT" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
    ;;
  *)
    echo "error: unknown mode: $MODE" >&2
    exit 1
    ;;
esac
