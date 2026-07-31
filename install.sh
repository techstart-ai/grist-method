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
#   --codex         Force Codex variant (AGENTS.md rules only)
#   --bmad-npm      Force BMAD npm/framework variant
#   --dry-run       Show what would be done without modifying files
#   --uninstall     Remove GRIST overlays
#   --force         Force reinstallation even if version matches
#   -h, --help      Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRIST_INSTALLER_VERSION="1.3.0"

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
  echo "  --codex         Force Codex variant (AGENTS.md rules only)"
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
    --codex)        FORCE_MODE="codex" ;;
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
    codex)
      SKILL_DST=""
      COMMANDS_DST=""
      RULES_FILE="$PROJECT_ROOT/AGENTS.md"
      ;;
    claude-code|bmad-npm|*)
      SKILL_DST="$PROJECT_ROOT/.claude/skills/grist"
      COMMANDS_DST="$PROJECT_ROOT/.claude/commands"
      RULES_FILE="$PROJECT_ROOT/CLAUDE.md"
      ;;
  esac

  # Grist skill (skipped for codex — no project skill convention)
  SKILL_SRC="$GRIST_ROOT/skills/grist/SKILL.md"
  if [[ -z "$SKILL_DST" ]]; then
    :
  elif $IS_UNINSTALL; then
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

  # Enforcement hooks (Claude Code only — Cursor/Antigravity have no hook system)
  if [[ -n "$COMMANDS_DST" ]]; then
    HOOKS_SRC="$GRIST_ROOT/hooks"
    HOOKS_DST="$PROJECT_ROOT/.grist/hooks"
    SETTINGS_FILE="$PROJECT_ROOT/.claude/settings.json"

    if $IS_UNINSTALL; then
      if $IS_DRY_RUN; then
        log_info "[dry-run] Would remove .grist/hooks/"
        log_info "[dry-run] Would strip GRIST hook entries from .claude/settings.json"
      else
        rm -rf "$HOOKS_DST"
        log_ok "Removed .grist/hooks/"
        if [[ -f "$SETTINGS_FILE" ]]; then
          if python3 - "$SETTINGS_FILE" <<'PY'
import json, os, sys

path = sys.argv[1]
try:
    with open(path) as f:
        content = f.read().strip()
    settings = json.loads(content) if content else {}
except (OSError, ValueError):
    sys.exit(1)

hooks = settings.get("hooks")
if isinstance(hooks, dict):
    for event in list(hooks.keys()):
        entries = hooks[event]
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if isinstance(entry, dict) and isinstance(entry.get("hooks"), list):
                entry["hooks"] = [
                    h for h in entry["hooks"]
                    if ".grist/hooks/" not in str(h.get("command", ""))
                ]
        entries = [
            e for e in entries
            if not (isinstance(e, dict) and e.get("hooks") == [])
        ]
        if entries:
            hooks[event] = entries
        else:
            del hooks[event]
    if not hooks:
        del settings["hooks"]

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PY
          then
            log_ok "Stripped GRIST hook entries from .claude/settings.json"
          else
            log_warn "Could not update .claude/settings.json (malformed JSON?) — remove GRIST hook entries manually"
          fi
        fi
      fi
    else
      if $IS_DRY_RUN; then
        log_info "[dry-run] Would install hooks to .grist/hooks/"
        log_info "[dry-run] Would register GRIST hooks in .claude/settings.json"
      else
        mkdir -p "$HOOKS_DST"
        for hook in read-discipline.py validate-grist-yaml.py session-router.py activity-sniff.py recall.py; do
          cp "$HOOKS_SRC/$hook" "$HOOKS_DST/$hook"
          chmod +x "$HOOKS_DST/$hook"
          log_ok ".grist/hooks/$hook"
        done
        # recall.py resolves slices via grist-get; ship it alongside the hooks.
        if [[ -f "$GRIST_ROOT/gristats/grist-get.py" ]]; then
          cp "$GRIST_ROOT/gristats/grist-get.py" "$HOOKS_DST/grist-get.py"
          chmod +x "$HOOKS_DST/grist-get.py"
          log_ok ".grist/hooks/grist-get.py"
        fi

        mkdir -p "$PROJECT_ROOT/.claude"
        if python3 - "$SETTINGS_FILE" <<'PY'
import json, os, sys

path = sys.argv[1]
settings = {}
try:
    if os.path.isfile(path):
        with open(path) as f:
            content = f.read().strip()
        if content:
            settings = json.loads(content)
except (OSError, ValueError):
    sys.exit(1)
if not isinstance(settings, dict):
    sys.exit(1)

hooks = settings.setdefault("hooks", {})


def register(event, matcher, command):
    entries = hooks.setdefault(event, [])
    for entry in entries:
        if isinstance(entry, dict) and entry.get("matcher") == matcher:
            cmds = entry.setdefault("hooks", [])
            if not any(
                isinstance(h, dict) and h.get("command") == command
                for h in cmds
            ):
                cmds.append({"type": "command", "command": command})
            return
    entries.append({
        "matcher": matcher,
        "hooks": [{"type": "command", "command": command}],
    })


register(
    "UserPromptSubmit", "",
    'python3 "$CLAUDE_PROJECT_DIR/.grist/hooks/session-router.py"',
)
register(
    "PreToolUse", "Read",
    'python3 "$CLAUDE_PROJECT_DIR/.grist/hooks/read-discipline.py"',
)
register(
    "PreToolUse", "Read|Write|Edit",
    'python3 "$CLAUDE_PROJECT_DIR/.grist/hooks/activity-sniff.py"',
)
register(
    "PostToolUse", "Write|Edit",
    'python3 "$CLAUDE_PROJECT_DIR/.grist/hooks/validate-grist-yaml.py"',
)
register(
    "PostToolUse", "Read",
    'python3 "$CLAUDE_PROJECT_DIR/.grist/hooks/recall.py"',
)

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PY
        then
          log_ok "Registered GRIST hooks in .claude/settings.json"
        else
          log_warn "Could not update .claude/settings.json (malformed JSON?) — register GRIST hooks manually"
        fi
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
