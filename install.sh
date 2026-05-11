#!/usr/bin/env bash
# Install GRIST into a project — auto-detects BMAD variant.
#
# Usage: ./install.sh <project-root> [--dry-run] [--uninstall]
#        ./install.sh <project-root> --bmad-npm       # force BMAD npm/framework path
#        ./install.sh <project-root> --claude-code    # force Claude Code skills path
#        ./install.sh <project-root> --cursor         # force Cursor skills path
#        ./install.sh <project-root> --openspec       # OpenSpec overlay only (no BMAD required)
#        ./install.sh <project-root> --openspec --claude-code  # OpenSpec with explicit mode
#
# Detection logic:
#   1. .claude/skills/bmad-create-prd/  → Claude Code skills variant
#   2. .cursor/skills/bmad-create-prd/  → Cursor skills variant
#   3. .agents/skills/bmad-create-prd/  → Antigravity skills variant
#   4. _bmad/bmm/config.yaml           → BMAD npm/framework variant
#   5. Multiple present                 → Claude Code > Cursor > Antigravity > BMAD npm (warn)
#   6. --openspec with no BMAD         → OpenSpec-only install (no BMAD installer run)
#   7. Neither and no --openspec        → error with guidance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'
GRIST_INSTALLER_VERSION="1.2.0"
usage() {
  echo "usage: $0 <project-root> [options]"
  echo
  echo "Auto-detects your BMAD variant and installs GRIST overlays."
  echo
  echo "Options:"
  echo "  --claude-code   Force Claude Code skills installer"
  echo "  --cursor        Force Cursor skills installer"
  echo "  --antigravity   Force Antigravity skills installer"
  echo "  --bmad-npm      Force BMAD npm/framework installer"
  echo "  --openspec      Also install OpenSpec schema overlay"
  echo "  --dry-run       Show what would be done without modifying files"
  echo "  --uninstall     Remove GRIST overlays"
  echo "  --force         Force reinstallation even if version matches"
  echo "  -h, --help      Show this help"
  exit 2
}

# --- Argument parsing -------------------------------------------------------

PROJECT_ROOT=""
FORCE_MODE=""
INSTALL_OPENSPEC=false
FORCE_INSTALL=false
EXTRA_ARGS=()
IS_UNINSTALL=false
IS_DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --claude-code)  FORCE_MODE="claude-code" ;;
    --cursor)       FORCE_MODE="cursor" ;;
    --antigravity)  FORCE_MODE="antigravity" ;;
    --bmad-npm)     FORCE_MODE="bmad-npm" ;;
    --openspec)     INSTALL_OPENSPEC=true ;;
    --dry-run)      EXTRA_ARGS+=("--dry-run"); IS_DRY_RUN=true ;;
    --uninstall)    EXTRA_ARGS+=("--uninstall"); IS_UNINSTALL=true ;;
    --force)        FORCE_INSTALL=true ;;
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

# --- Version Checking -------------------------------------------------------

GRIST_DIR="$PROJECT_ROOT/.grist"
VERSION_FILE="$GRIST_DIR/version"

if $IS_UNINSTALL; then
  if $IS_DRY_RUN; then
    echo "[dry-run] Would remove $VERSION_FILE"
  else
    rm -f "$VERSION_FILE"
  fi
elif ! $IS_DRY_RUN; then
  if [[ -f "$VERSION_FILE" ]]; then
    CURRENT_VERSION=$(cat "$VERSION_FILE")
    if [[ "$CURRENT_VERSION" == "$GRIST_INSTALLER_VERSION" ]] && ! $FORCE_INSTALL; then
      printf "${GREEN}✓${NC} GRIST is already up to date at version ${BLUE}%s${NC}.\n" "$CURRENT_VERSION"
      echo "  Use --force to reinstall."
      exit 0
    elif [[ "$CURRENT_VERSION" != "$GRIST_INSTALLER_VERSION" ]]; then
      printf "${BLUE}→${NC} Upgrading GRIST from version ${YELLOW}%s${NC} to ${GREEN}%s${NC}...\n" "$CURRENT_VERSION" "$GRIST_INSTALLER_VERSION"
    fi
  else
    printf "${BLUE}→${NC} Installing GRIST version ${GREEN}%s${NC}...\n" "$GRIST_INSTALLER_VERSION"
  fi
fi

# --- Detection --------------------------------------------------------------

HAS_CLAUDE_CODE=false
HAS_CURSOR=false
HAS_ANTIGRAVITY=false
HAS_BMAD_NPM=false
HAS_OPENSPEC=false

[[ -d "$PROJECT_ROOT/.claude/skills/bmad-create-prd" ]] && HAS_CLAUDE_CODE=true
[[ -d "$PROJECT_ROOT/.claude/skills/bmad-create-architecture" ]] && HAS_CLAUDE_CODE=true
[[ -d "$PROJECT_ROOT/.cursor/skills/bmad-create-prd" ]] && HAS_CURSOR=true
[[ -d "$PROJECT_ROOT/.cursor/skills/bmad-create-architecture" ]] && HAS_CURSOR=true
[[ -d "$PROJECT_ROOT/.agents/skills/bmad-create-prd" ]] && HAS_ANTIGRAVITY=true
[[ -d "$PROJECT_ROOT/.agents/skills/bmad-create-architecture" ]] && HAS_ANTIGRAVITY=true
[[ -f "$PROJECT_ROOT/_bmad/bmm/config.yaml" ]] && HAS_BMAD_NPM=true
[[ -d "$PROJECT_ROOT/_bmad" && ! -d "$PROJECT_ROOT/.claude/skills" && ! -d "$PROJECT_ROOT/.cursor/skills" && ! -d "$PROJECT_ROOT/.agents/skills" ]] && HAS_BMAD_NPM=true
[[ -d "$PROJECT_ROOT/openspec" ]] && HAS_OPENSPEC=true

# Determine mode
MODE="${FORCE_MODE:-}"

if [[ -z "$MODE" ]]; then
  if $HAS_CLAUDE_CODE && $HAS_CURSOR; then
    printf "${YELLOW}⚠${NC} Both Claude Code and Cursor skills detected.\n"
    printf "  Using Claude Code installer (takes precedence).\n"
    printf "  Use --cursor to force the Cursor installer.\n\n"
    MODE="claude-code"
  elif $HAS_CLAUDE_CODE && $HAS_BMAD_NPM; then
    printf "${YELLOW}⚠${NC} Both Claude Code skills and BMAD npm/framework detected.\n"
    printf "  Using Claude Code installer (most common for active projects).\n"
    printf "  Use --bmad-npm to force the TOML-based installer.\n\n"
    MODE="claude-code"
  elif $HAS_CURSOR && $HAS_BMAD_NPM; then
    printf "${YELLOW}⚠${NC} Both Cursor skills and BMAD npm/framework detected.\n"
    printf "  Using Cursor installer (most common for active projects).\n"
    printf "  Use --bmad-npm to force the TOML-based installer.\n\n"
    MODE="cursor"
  elif $HAS_ANTIGRAVITY && $HAS_BMAD_NPM; then
    printf "${YELLOW}⚠${NC} Both Antigravity skills and BMAD npm/framework detected.\n"
    printf "  Using Antigravity installer (most common for active projects).\n"
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
  elif $INSTALL_OPENSPEC; then
    printf "${YELLOW}⚠${NC} No BMAD variant detected. Installing OpenSpec overlay only.\n\n"
    MODE="openspec-only"
  else
    printf "${RED}✗${NC} Cannot detect BMAD variant at: %s\n" "$PROJECT_ROOT" >&2
    echo "" >&2
    echo "Expected one of:" >&2
    echo "  • .claude/skills/bmad-create-prd/  (Claude Code skills)" >&2
    echo "  • .cursor/skills/bmad-create-prd/  (Cursor skills)" >&2
    echo "  • .agents/skills/bmad-create-prd/  (Antigravity skills)" >&2
    echo "  • _bmad/bmm/config.yaml            (BMAD npm/framework)" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  1. Install BMAD skills first, then re-run" >&2
    echo "  2. Use --claude-code, --cursor, --antigravity, or --bmad-npm to force a mode" >&2
    echo "  3. Use --openspec to install the OpenSpec overlay without BMAD" >&2
    exit 1
  fi
fi

# --- Run BMAD installer -----------------------------------------------------

if [[ "$MODE" != "openspec-only" ]]; then
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
    cursor)
      if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
        "$SCRIPT_DIR/bmad-overrides/install-cursor.sh" "$PROJECT_ROOT" "${EXTRA_ARGS[@]}"
      else
        "$SCRIPT_DIR/bmad-overrides/install-cursor.sh" "$PROJECT_ROOT"
      fi
      ;;
    antigravity)
      if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
        "$SCRIPT_DIR/bmad-overrides/install-antigravity.sh" "$PROJECT_ROOT" "${EXTRA_ARGS[@]}"
      else
        "$SCRIPT_DIR/bmad-overrides/install-antigravity.sh" "$PROJECT_ROOT"
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
fi

# --- OpenSpec (if requested) ------------------------------------------------

if $INSTALL_OPENSPEC; then
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [[ "$MODE" == "openspec-only" ]]; then
    printf "${BLUE}GRIST OpenSpec overlay${NC} — mode: ${GREEN}openspec-only${NC}\n"
  else
    printf "${BLUE}GRIST OpenSpec overlay${NC}\n"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if $HAS_OPENSPEC; then
    # Claude Code mode gets the command-file injection installer;
    # BMAD npm / openspec-only mode gets the standard schema installer
    case "$MODE" in
      claude-code)
        if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
          "$SCRIPT_DIR/openspec-overrides/install-claude-code.sh" "$PROJECT_ROOT" "${EXTRA_ARGS[@]}"
        else
          "$SCRIPT_DIR/openspec-overrides/install-claude-code.sh" "$PROJECT_ROOT"
        fi
        ;;
      cursor)
        if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
          "$SCRIPT_DIR/openspec-overrides/install-cursor.sh" "$PROJECT_ROOT" "${EXTRA_ARGS[@]}"
        else
          "$SCRIPT_DIR/openspec-overrides/install-cursor.sh" "$PROJECT_ROOT"
        fi
        ;;
      antigravity)
        if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
          "$SCRIPT_DIR/openspec-overrides/install-antigravity.sh" "$PROJECT_ROOT" "${EXTRA_ARGS[@]}"
        else
          "$SCRIPT_DIR/openspec-overrides/install-antigravity.sh" "$PROJECT_ROOT"
        fi
        ;;
      openspec-only|*)
        if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
          "$SCRIPT_DIR/openspec-overrides/install.sh" "$PROJECT_ROOT" "${EXTRA_ARGS[@]}"
        else
          "$SCRIPT_DIR/openspec-overrides/install.sh" "$PROJECT_ROOT"
        fi
        ;;
    esac
  else
    printf "${YELLOW}⚠${NC} No openspec/ directory found. Skipping OpenSpec overlay.\n"
    echo "  Run 'openspec init' first if you want OpenSpec support."
  fi
fi

if ! $IS_UNINSTALL && ! $IS_DRY_RUN; then
  mkdir -p "$GRIST_DIR"
  echo "$GRIST_INSTALLER_VERSION" > "$VERSION_FILE"
fi
