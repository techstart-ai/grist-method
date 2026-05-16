#!/usr/bin/env bash
# Install GRIST OpenSpec overlays into a project.
#
# Usage: ./install-openspec.sh <project-root> [options]
#
# Requires an openspec/ directory. Auto-detects your AI tool variant.
#
# Options:
#   --claude-code   Force Claude Code variant
#   --cursor        Force Cursor variant
#   --antigravity   Force Antigravity variant
#   --bmad-npm      Alias for standard schema-only install
#   --dry-run       Show what would be done without modifying files
#   --uninstall     Remove GRIST OpenSpec overlays
#   -h, --help      Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENSPEC_OVERRIDES="$SCRIPT_DIR/openspec-overrides"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
  echo "usage: $0 <project-root> [options]"
  echo
  echo "Installs GRIST OpenSpec overlays. Requires openspec/ directory."
  echo
  echo "Options:"
  echo "  --claude-code   Force Claude Code variant"
  echo "  --cursor        Force Cursor variant"
  echo "  --antigravity   Force Antigravity variant"
  echo "  --bmad-npm      Use standard schema-only install"
  echo "  --dry-run       Show what would be done without modifying files"
  echo "  --uninstall     Remove GRIST OpenSpec overlays"
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
    --bmad-npm)     FORCE_MODE="standard" ;;
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

# --- Validate ---------------------------------------------------------------

if [[ ! -d "$PROJECT_ROOT/openspec" ]]; then
  printf "${RED}✗${NC} No openspec/ directory found at: %s\n" "$PROJECT_ROOT" >&2
  echo "  Run 'openspec init' first, then re-run this installer." >&2
  exit 1
fi

# --- Detection --------------------------------------------------------------

HAS_CLAUDE_CODE=false
HAS_CURSOR=false
HAS_ANTIGRAVITY=false

[[ -d "$PROJECT_ROOT/.claude/commands" || -d "$PROJECT_ROOT/.claude/skills" ]] && HAS_CLAUDE_CODE=true
[[ -d "$PROJECT_ROOT/.cursor/rules" || -d "$PROJECT_ROOT/.cursor/skills" ]] && HAS_CURSOR=true
[[ -d "$PROJECT_ROOT/.agents/skills" ]] && HAS_ANTIGRAVITY=true

MODE="${FORCE_MODE:-}"

if [[ -z "$MODE" ]]; then
  if $HAS_CLAUDE_CODE && $HAS_CURSOR; then
    printf "${YELLOW}⚠${NC} Both Claude Code and Cursor detected.\n"
    printf "  Using Claude Code installer (takes precedence).\n"
    printf "  Use --cursor to force the Cursor installer.\n\n"
    MODE="claude-code"
  elif $HAS_CLAUDE_CODE; then
    MODE="claude-code"
  elif $HAS_CURSOR; then
    MODE="cursor"
  elif $HAS_ANTIGRAVITY; then
    MODE="antigravity"
  else
    printf "${YELLOW}⚠${NC} No AI tool detected — using standard schema-only install.\n\n"
    MODE="standard"
  fi
fi

# --- Run installer ----------------------------------------------------------

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "${BLUE}GRIST OpenSpec installer${NC} — mode: ${GREEN}%s${NC}\n" "$MODE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

case "$MODE" in
  claude-code)
    "$OPENSPEC_OVERRIDES/install-claude-code.sh" "$PROJECT_ROOT" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
    ;;
  cursor)
    "$OPENSPEC_OVERRIDES/install-cursor.sh" "$PROJECT_ROOT" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
    ;;
  antigravity)
    "$OPENSPEC_OVERRIDES/install-antigravity.sh" "$PROJECT_ROOT" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
    ;;
  standard|*)
    "$OPENSPEC_OVERRIDES/install.sh" "$PROJECT_ROOT" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
    ;;
esac
