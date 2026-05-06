#!/usr/bin/env bash
# Install GRIST into a project — auto-detects BMAD variant.
#
# Usage: ./install.sh <project-root> [--dry-run] [--uninstall]
#        ./install.sh <project-root> --bmad-npm     # force BMAD npm/framework path
#        ./install.sh <project-root> --claude-code   # force Claude Code skills path
#
# Detection logic:
#   1. .claude/skills/bmad-create-prd/  → Claude Code skills variant
#   2. _bmad/bmm/config.yaml           → BMAD npm/framework variant
#   3. Both present                     → Claude Code takes precedence (warn)
#   4. Neither                          → error with guidance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
  echo "usage: $0 <project-root> [options]"
  echo
  echo "Auto-detects your BMAD variant and installs GRIST overlays."
  echo
  echo "Options:"
  echo "  --claude-code   Force Claude Code skills installer"
  echo "  --bmad-npm      Force BMAD npm/framework installer"
  echo "  --openspec      Also install OpenSpec schema overlay"
  echo "  --dry-run       Show what would be done without modifying files"
  echo "  --uninstall     Remove GRIST overlays"
  echo "  -h, --help      Show this help"
  exit 2
}

# --- Argument parsing -------------------------------------------------------

PROJECT_ROOT=""
FORCE_MODE=""
INSTALL_OPENSPEC=false
EXTRA_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --claude-code)  FORCE_MODE="claude-code" ;;
    --bmad-npm)     FORCE_MODE="bmad-npm" ;;
    --openspec)     INSTALL_OPENSPEC=true ;;
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
HAS_BMAD_NPM=false
HAS_OPENSPEC=false

[[ -d "$PROJECT_ROOT/.claude/skills/bmad-create-prd" ]] && HAS_CLAUDE_CODE=true
[[ -d "$PROJECT_ROOT/.claude/skills/bmad-create-architecture" ]] && HAS_CLAUDE_CODE=true
[[ -f "$PROJECT_ROOT/_bmad/bmm/config.yaml" ]] && HAS_BMAD_NPM=true
[[ -d "$PROJECT_ROOT/_bmad" && ! -d "$PROJECT_ROOT/.claude/skills" ]] && HAS_BMAD_NPM=true
[[ -d "$PROJECT_ROOT/openspec" ]] && HAS_OPENSPEC=true

# Determine mode
MODE="${FORCE_MODE:-}"

if [[ -z "$MODE" ]]; then
  if $HAS_CLAUDE_CODE && $HAS_BMAD_NPM; then
    printf "${YELLOW}⚠${NC} Both Claude Code skills and BMAD npm/framework detected.\n"
    printf "  Using Claude Code installer (most common for active projects).\n"
    printf "  Use --bmad-npm to force the TOML-based installer.\n\n"
    MODE="claude-code"
  elif $HAS_CLAUDE_CODE; then
    MODE="claude-code"
  elif $HAS_BMAD_NPM; then
    MODE="bmad-npm"
  else
    printf "${RED}✗${NC} Cannot detect BMAD variant at: %s\n" "$PROJECT_ROOT" >&2
    echo "" >&2
    echo "Expected one of:" >&2
    echo "  • .claude/skills/bmad-create-prd/  (Claude Code skills)" >&2
    echo "  • _bmad/bmm/config.yaml            (BMAD npm/framework)" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  1. Install BMAD skills first, then re-run" >&2
    echo "  2. Use --claude-code or --bmad-npm to force a mode" >&2
    exit 1
  fi
fi

# --- Run BMAD installer -----------------------------------------------------

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "${BLUE}GRIST installer${NC} — mode: ${GREEN}%s${NC}\n" "$MODE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

case "$MODE" in
  claude-code)
    if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
      "$SCRIPT_DIR/bmad-overrides/install-claude-code.sh" "$PROJECT_ROOT" "${EXTRA_ARGS[@]}"
    else
      "$SCRIPT_DIR/bmad-overrides/install-claude-code.sh" "$PROJECT_ROOT"
    fi
    ;;
  bmad-npm)
    if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
      "$SCRIPT_DIR/bmad-overrides/install.sh" "$PROJECT_ROOT" "${EXTRA_ARGS[@]}"
    else
      "$SCRIPT_DIR/bmad-overrides/install.sh" "$PROJECT_ROOT"
    fi
    ;;
  *)
    echo "error: unknown mode: $MODE" >&2
    exit 1
    ;;
esac

# --- OpenSpec (if requested) ------------------------------------------------

if $INSTALL_OPENSPEC; then
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "${BLUE}GRIST OpenSpec overlay${NC}\n"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if $HAS_OPENSPEC; then
    # Claude Code mode gets the command-file injection installer;
    # BMAD npm mode (or schema-only) gets the standard schema installer
    case "$MODE" in
      claude-code)
        if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
          "$SCRIPT_DIR/openspec-overrides/install-claude-code.sh" "$PROJECT_ROOT" "${EXTRA_ARGS[@]}"
        else
          "$SCRIPT_DIR/openspec-overrides/install-claude-code.sh" "$PROJECT_ROOT"
        fi
        ;;
      *)
        "$SCRIPT_DIR/openspec-overrides/install.sh" "$PROJECT_ROOT"
        ;;
    esac
  else
    printf "${YELLOW}⚠${NC} No openspec/ directory found. Skipping OpenSpec overlay.\n"
    echo "  Run 'openspec init' first if you want OpenSpec support."
  fi
fi
