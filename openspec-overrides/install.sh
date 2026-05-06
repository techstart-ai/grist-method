#!/usr/bin/env bash
# Install the GRIST OpenSpec schema into a project.
# Usage: ./install.sh <openspec-project-root>
#
# Idempotent: re-running upgrades schema files in place. Existing
# openspec/config.yaml is preserved (script prints the line to add manually
# if `schema: grist` is not already set).

set -euo pipefail

usage() {
  echo "usage: $0 <openspec-project-root> [--dry-run] [--uninstall]" >&2
  echo "  drops openspec/schemas/grist/ + scripts/ into the project" >&2
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

PROJECT_ROOT=""
DRY_RUN=false
UNINSTALL=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=true ;;
    --uninstall) UNINSTALL=true ;;
    --help|-h)   usage ;;
    *)           PROJECT_ROOT="$(cd "$arg" 2>/dev/null && pwd)" || { echo "error: dir not found: $arg" >&2; exit 1; } ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  usage
fi

SRC_ROOT="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -d "$PROJECT_ROOT/openspec" ]]; then
  echo "error: $PROJECT_ROOT does not look like an OpenSpec project (no openspec/ dir)" >&2
  echo "  run \`openspec init\` first" >&2
  exit 1
fi

if $UNINSTALL; then
  echo "Uninstalling GRIST OpenSpec schema from $PROJECT_ROOT"
  if $DRY_RUN; then
    echo "[dry-run] Would remove openspec/schemas/grist/"
    echo "[dry-run] Would remove openspec/scripts/openspec-spec-to-grist.py"
  else
    rm -rf "$PROJECT_ROOT/openspec/schemas/grist"
    rm -f "$PROJECT_ROOT/openspec/scripts/openspec-spec-to-grist.py"
    echo "Removed GRIST schemas and scripts."
    echo "Note: openspec/config.yaml was left untouched to preserve your configuration."
  fi
  exit 0
fi

if $DRY_RUN; then
  echo "[dry-run] Would create openspec/schemas/grist/templates"
  echo "[dry-run] Would create openspec/scripts"
else
  mkdir -p "$PROJECT_ROOT/openspec/schemas/grist/templates" \
           "$PROJECT_ROOT/openspec/scripts"
fi

# 1. Schema files — always overwrite (GRIST-controlled)
if $DRY_RUN; then
  echo "[dry-run] Would write: openspec/schemas/grist/schema.yaml"
  echo "[dry-run] Would write: openspec/schemas/grist/README.md"
else
  cp "$SRC_ROOT/schemas/grist/schema.yaml" \
     "$PROJECT_ROOT/openspec/schemas/grist/schema.yaml"
  echo "wrote: openspec/schemas/grist/schema.yaml"

  cp "$SRC_ROOT/schemas/grist/README.md" \
     "$PROJECT_ROOT/openspec/schemas/grist/README.md"
  echo "wrote: openspec/schemas/grist/README.md"
fi

for f in change.grist.yaml tasks.md; do
  if $DRY_RUN; then
    echo "[dry-run] Would write: openspec/schemas/grist/templates/$f"
  else
    cp "$SRC_ROOT/schemas/grist/templates/$f" \
       "$PROJECT_ROOT/openspec/schemas/grist/templates/$f"
    echo "wrote: openspec/schemas/grist/templates/$f"
  fi
done

# 2. Conversion script — always overwrite
if $DRY_RUN; then
  echo "[dry-run] Would write: openspec/scripts/openspec-spec-to-grist.py"
else
  cp "$SRC_ROOT/scripts/openspec-spec-to-grist.py" \
     "$PROJECT_ROOT/openspec/scripts/openspec-spec-to-grist.py"
  chmod +x "$PROJECT_ROOT/openspec/scripts/openspec-spec-to-grist.py"
  echo "wrote: openspec/scripts/openspec-spec-to-grist.py"
fi

# 3. Validate schema
if ! $DRY_RUN && command -v openspec >/dev/null 2>&1; then
  echo
  echo "validating schema..."
  if openspec schema validate grist 2>&1; then
    echo "schema valid."
  else
    echo "  schema validation failed — review schema.yaml" >&2
  fi
fi

# 4. Activate — only if config.yaml doesn't already select grist
CONFIG="$PROJECT_ROOT/openspec/config.yaml"
if [[ -f "$CONFIG" ]] && grep -q "^schema:[[:space:]]*grist[[:space:]]*$" "$CONFIG"; then
  echo
  echo "openspec/config.yaml already activates 'grist' — done."
elif [[ -f "$CONFIG" ]]; then
  echo
  echo "openspec/config.yaml exists but does not activate grist."
  echo "Add this line to enable project-wide:"
  echo
  echo "    schema: grist"
  echo
  echo "Or use per-change: openspec new <name> --schema grist"
else
  if $DRY_RUN; then
    echo "[dry-run] Would write: openspec/config.yaml (with schema: grist activated)"
  else
    cp "$SRC_ROOT/config.yaml.example" "$CONFIG"
    echo "wrote: openspec/config.yaml (with schema: grist activated)"
  fi
fi

echo
echo "GRIST OpenSpec schema installed."
echo
echo "Next:"
echo "  1. (Optional) Migrate existing specs to YAML form:"
echo "       for d in openspec/specs/*/; do"
echo "         python3 openspec/scripts/openspec-spec-to-grist.py --in-place \"\$d/spec.md\""
echo "       done"
echo "  2. Try a change: /opsx:propose <description>"
echo "     → emits change.grist.yaml + tasks.md"
echo "  3. Apply: /opsx:apply <change-name>"
echo "     → /grist ship mode active during implementation"
echo "  4. Uninstall: $0 $PROJECT_ROOT --uninstall"
