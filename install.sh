#!/usr/bin/env bash
# Install GRIST into a project.
#
# Usage: ./install.sh <project-root> [options]
#
# Detection logic — runs installers based on what is present:
#   BMAD skills detected  → install-bmad.sh
#   openspec/ detected    → install-openspec.sh
#   Neither detected      → base install (normal chat mode, no framework required)
#   Both detected         → install-bmad.sh + install-openspec.sh
#
# To install only BMAD or only OpenSpec overlays, call the sub-installers directly:
#   ./install-bmad.sh <project-root> [--claude-code|--cursor|--antigravity|--bmad-npm]
#   ./install-openspec.sh <project-root> [--claude-code|--cursor|--antigravity]
#
# Options:
#   --claude-code   Force Claude Code variant
#   --cursor        Force Cursor variant
#   --antigravity   Force Antigravity variant
#   --bmad-npm      Force BMAD npm/framework variant
#   --dry-run       Show what would be done without modifying files
#   --uninstall     Remove GRIST overlays
#   --force         Force reinstallation even if version matches
#   -h, --help      Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRIST_INSTALLER_VERSION="1.2.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
log_skip() { printf "${YELLOW}⊘${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
log_info() { printf "${BLUE}→${NC} %s\n" "$1"; }

usage() {
  echo "usage: $0 <project-root> [options]"
  echo
  echo "Auto-detects BMAD and OpenSpec presence, runs appropriate GRIST installers."
  echo "Also works with no framework — installs GRIST for normal Claude Code chat mode."
  echo
  echo "Options:"
  echo "  --claude-code   Force Claude Code variant"
  echo "  --cursor        Force Cursor variant"
  echo "  --antigravity   Force Antigravity variant"
  echo "  --bmad-npm      Force BMAD npm/framework variant"
  echo "  --dry-run       Show what would be done without modifying files"
  echo "  --uninstall     Remove GRIST overlays"
  echo "  --force         Force reinstallation even if version matches"
  echo "  -h, --help      Show this help"
  exit 2
}

# --- Argument parsing -------------------------------------------------------

PROJECT_ROOT=""
FORCE_MODE=""
FORCE_INSTALL=false
IS_UNINSTALL=false
IS_DRY_RUN=false
FORWARD_FLAGS=()

for arg in "$@"; do
  case "$arg" in
    --claude-code)  FORCE_MODE="claude-code" ; FORWARD_FLAGS+=("--claude-code") ;;
    --cursor)       FORCE_MODE="cursor"      ; FORWARD_FLAGS+=("--cursor") ;;
    --antigravity)  FORCE_MODE="antigravity" ; FORWARD_FLAGS+=("--antigravity") ;;
    --bmad-npm)     FORCE_MODE="bmad-npm"    ; FORWARD_FLAGS+=("--bmad-npm") ;;
    --dry-run)      IS_DRY_RUN=true          ; FORWARD_FLAGS+=("--dry-run") ;;
    --uninstall)    IS_UNINSTALL=true        ; FORWARD_FLAGS+=("--uninstall") ;;
    --force)        FORCE_INSTALL=true ;;
    --help|-h)      usage ;;
    *)
      if [[ -z "$PROJECT_ROOT" ]]; then
        PROJECT_ROOT="$(cd "$arg" 2>/dev/null && pwd)" || {
          echo "error: directory not found: $arg" >&2
          exit 1
        }
      fi
      ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  usage
fi

# --- Version checking -------------------------------------------------------

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

HAS_BMAD=false
HAS_OPENSPEC=false

[[ -d "$PROJECT_ROOT/.claude/skills/bmad-create-prd" ]] && HAS_BMAD=true
[[ -d "$PROJECT_ROOT/.claude/skills/bmad-create-architecture" ]] && HAS_BMAD=true
[[ -d "$PROJECT_ROOT/.cursor/skills/bmad-create-prd" ]] && HAS_BMAD=true
[[ -d "$PROJECT_ROOT/.cursor/skills/bmad-create-architecture" ]] && HAS_BMAD=true
[[ -d "$PROJECT_ROOT/.agents/skills/bmad-create-prd" ]] && HAS_BMAD=true
[[ -d "$PROJECT_ROOT/.agents/skills/bmad-create-architecture" ]] && HAS_BMAD=true
[[ -f "$PROJECT_ROOT/_bmad/bmm/config.yaml" ]] && HAS_BMAD=true
[[ -d "$PROJECT_ROOT/_bmad" && ! -d "$PROJECT_ROOT/.claude/skills" && ! -d "$PROJECT_ROOT/.cursor/skills" && ! -d "$PROJECT_ROOT/.agents/skills" ]] && HAS_BMAD=true
[[ -d "$PROJECT_ROOT/openspec" ]] && HAS_OPENSPEC=true

# A forced variant implies the user wants BMAD installed (matches previous behaviour)
[[ -n "$FORCE_MODE" ]] && HAS_BMAD=true

# --- Run BMAD installer -----------------------------------------------------

RAN_SOMETHING=false

if $HAS_BMAD; then
  "$SCRIPT_DIR/install-bmad.sh" "$PROJECT_ROOT" ${FORWARD_FLAGS[@]+"${FORWARD_FLAGS[@]}"}
  RAN_SOMETHING=true
fi

# --- Run OpenSpec installer -------------------------------------------------

if $HAS_OPENSPEC; then
  echo
  "$SCRIPT_DIR/install-openspec.sh" "$PROJECT_ROOT" ${FORWARD_FLAGS[@]+"${FORWARD_FLAGS[@]}"}
  RAN_SOMETHING=true
fi

# --- Base install (normal chat mode) ----------------------------------------
# Runs only when no BMAD or OpenSpec framework is detected.
# Installs: grist skill, slash command, always-on rules, .grist/context-pack.md.

if ! $RAN_SOMETHING; then
  AI_MODE="${FORCE_MODE:-}"
  if [[ -z "$AI_MODE" ]]; then
    if [[ -d "$PROJECT_ROOT/.claude" ]]; then
      AI_MODE="claude-code"
    elif [[ -d "$PROJECT_ROOT/.cursor" ]]; then
      AI_MODE="cursor"
    elif [[ -d "$PROJECT_ROOT/.agents" ]]; then
      AI_MODE="antigravity"
    else
      AI_MODE="claude-code"
    fi
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "${BLUE}GRIST base install${NC} — mode: ${GREEN}%s${NC}\n" "$AI_MODE"
  printf "  (no BMAD or OpenSpec detected — installing for normal chat mode)\n"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  GRIST_ROOT="$SCRIPT_DIR"

  case "$AI_MODE" in
    cursor)
      SKILL_DST="$PROJECT_ROOT/.cursor/skills/grist"
      COMMANDS_DST=""
      RULES_FILE="$PROJECT_ROOT/AGENTS.md"
      ;;
    antigravity)
      SKILL_DST="$PROJECT_ROOT/.agents/skills/grist"
      COMMANDS_DST=""
      RULES_FILE="$PROJECT_ROOT/AGENTS.md"
      ;;
    claude-code|bmad-npm|*)
      SKILL_DST="$PROJECT_ROOT/.claude/skills/grist"
      COMMANDS_DST="$PROJECT_ROOT/.claude/commands"
      RULES_FILE="$PROJECT_ROOT/CLAUDE.md"
      ;;
  esac

  # Grist skill
  SKILL_SRC="$GRIST_ROOT/skills/grist/SKILL.md"
  if $IS_UNINSTALL; then
    if $IS_DRY_RUN; then
      log_info "[dry-run] Would remove $(basename "$(dirname "$SKILL_DST")")/grist/"
    else
      rm -rf "$SKILL_DST"
      log_ok "Removed grist skill"
    fi
  elif [[ -f "$SKILL_SRC" ]]; then
    if $IS_DRY_RUN; then
      log_info "[dry-run] Would install grist skill"
    else
      mkdir -p "$SKILL_DST"
      cp "$SKILL_SRC" "$SKILL_DST/SKILL.md"
      log_ok "$(basename "$(dirname "$SKILL_DST")")/grist/SKILL.md"
    fi
  fi

  # Grist slash command (Claude Code only — Cursor/Antigravity use skills)
  if [[ -n "$COMMANDS_DST" ]]; then
    if $IS_UNINSTALL; then
      if $IS_DRY_RUN; then
        log_info "[dry-run] Would remove grist command files"
      else
        rm -f "$COMMANDS_DST/grist.md" "$COMMANDS_DST/grist.toml"
        log_ok "Removed grist command"
      fi
    else
      if $IS_DRY_RUN; then
        log_info "[dry-run] Would install grist command"
      else
        mkdir -p "$COMMANDS_DST"
        [[ -f "$GRIST_ROOT/commands/grist.md" ]] && cp "$GRIST_ROOT/commands/grist.md" "$COMMANDS_DST/grist.md" && log_ok ".claude/commands/grist.md"
        [[ -f "$GRIST_ROOT/commands/grist.toml" ]] && cp "$GRIST_ROOT/commands/grist.toml" "$COMMANDS_DST/grist.toml" && log_ok ".claude/commands/grist.toml"
      fi
    fi
  fi

  # Always-on rules (CLAUDE.md or AGENTS.md)
  RULES_TEMPLATE="$GRIST_ROOT/templates/claude-md-rules.md"
  if [[ -f "$RULES_TEMPLATE" ]]; then
    if $IS_UNINSTALL; then
      if $IS_DRY_RUN; then
        log_info "[dry-run] Would remove GRIST rules from $(basename "$RULES_FILE")"
      elif [[ -f "$RULES_FILE" ]] && grep -q 'GRIST:RULES' "$RULES_FILE"; then
        tmpfile=$(mktemp)
        awk '/<!-- GRIST:RULES/,/<!-- GRIST:RULES:END/ { next } { print }' "$RULES_FILE" > "$tmpfile"
        mv "$tmpfile" "$RULES_FILE"
        log_ok "Removed GRIST rules from $(basename "$RULES_FILE")"
      fi
    elif $IS_DRY_RUN; then
      log_info "[dry-run] Would append GRIST rules to $(basename "$RULES_FILE")"
    elif [[ -f "$RULES_FILE" ]] && { grep -q 'GRIST:RULES' "$RULES_FILE" || grep -q 'GRIST.*Always-On' "$RULES_FILE"; }; then
      log_skip "$(basename "$RULES_FILE") already contains GRIST rules"
    else
      touch "$RULES_FILE"
      printf '\n' >> "$RULES_FILE"
      cat "$RULES_TEMPLATE" >> "$RULES_FILE"
      log_ok "Appended GRIST rules to $(basename "$RULES_FILE")"
    fi
  fi

  # .grist/context-pack.md
  CONTEXT_TEMPLATE="$GRIST_ROOT/templates/context-pack.md"
  CONTEXT_PACK="$PROJECT_ROOT/.grist/context-pack.md"
  if ! $IS_UNINSTALL; then
    if $IS_DRY_RUN; then
      log_info "[dry-run] Would create .grist/context-pack.md"
    elif [[ -f "$CONTEXT_PACK" ]]; then
      log_skip ".grist/context-pack.md already exists"
    elif [[ -f "$CONTEXT_TEMPLATE" ]]; then
      mkdir -p "$PROJECT_ROOT/.grist"
      cp "$CONTEXT_TEMPLATE" "$CONTEXT_PACK"
      log_ok ".grist/context-pack.md"
    fi
  fi

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "${GREEN}GRIST installed (chat mode) at:${NC} %s\n" "$PROJECT_ROOT"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
  echo "What happens now:"
  echo "  • /grist ship    — coding mode. No preambles, read discipline."
  echo "  • /grist design  — planning mode."
  echo "  • Always-on rules apply even without /grist activation."
  echo
  echo "Next steps:"
  echo "  1. Edit .grist/context-pack.md with your project's stable facts."
  echo "  2. Use /grist ship in Claude Code for focused sessions."
  echo
  RAN_SOMETHING=true
fi

# --- Write version file -----------------------------------------------------

if ! $IS_UNINSTALL && ! $IS_DRY_RUN; then
  mkdir -p "$GRIST_DIR"
  echo "$GRIST_INSTALLER_VERSION" > "$VERSION_FILE"
fi
