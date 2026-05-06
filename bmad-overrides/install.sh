#!/usr/bin/env bash
# Install GRIST overlays into a BMAD project.
# Usage: ./install.sh <bmad-project-root>
#
# Idempotent: re-running upgrades the schemas + scripts in place.
# Existing user .toml files are preserved (overlay files only ship at
# .toml, not .user.toml — your personal overrides are untouched).

set -euo pipefail

usage() {
  echo "usage: $0 <bmad-project-root> [--dry-run] [--uninstall]" >&2
  echo "  drops _bmad/custom/{toml,emission docs,scripts,schemas} into the project" >&2
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

if [[ ! -d "$PROJECT_ROOT/_bmad" ]]; then
  echo "error: $PROJECT_ROOT does not look like a BMAD project (no _bmad/ dir)" >&2
  exit 1
fi

if $UNINSTALL; then
  echo "Uninstalling GRIST BMAD npm overlay from $PROJECT_ROOT"
  
  if $DRY_RUN; then
    echo "[dry-run] Would remove _bmad/custom/grist-*"
  else
    # We only remove things we strictly installed and control
    rm -f "$PROJECT_ROOT"/_bmad/custom/grist-*-emission.md
    rm -rf "$PROJECT_ROOT/_bmad/custom/grist-schemas"
    rm -rf "$PROJECT_ROOT/_bmad/custom/grist-scripts"
    echo "Removed GRIST emission rules, schemas, and scripts."
    echo "Note: The .toml overrides in _bmad/custom/ were left in place to preserve your edits."
  fi
  exit 0
fi

if $DRY_RUN; then
  echo "[dry-run] Would create directory _bmad/custom/grist-schemas"
  echo "[dry-run] Would create directory _bmad/custom/grist-scripts"
else
  mkdir -p "$PROJECT_ROOT/_bmad/custom/grist-schemas" \
           "$PROJECT_ROOT/_bmad/custom/grist-scripts"
fi

# 1. TOML overrides — only copy if target does not exist (don't clobber user edits)
for tool in bmad-create-prd bmad-create-architecture bmad-create-story bmad-dev-story bmad-code-review; do
  src="$SRC_ROOT/_bmad/custom/$tool.toml"
  dst="$PROJECT_ROOT/_bmad/custom/$tool.toml"
  if [[ -f "$dst" ]]; then
    echo "skip (exists): _bmad/custom/$tool.toml"
  else
    if $DRY_RUN; then
      echo "[dry-run] Would write: _bmad/custom/$tool.toml"
    else
      cp "$src" "$dst"
      echo "wrote: _bmad/custom/$tool.toml"
    fi
  fi
done

# 2. Emission rules — always overwrite (these are GRIST-controlled)
for f in grist-prd-emission.md grist-architecture-emission.md grist-story-emission.md grist-dev-story-emission.md grist-code-review-emission.md; do
  if $DRY_RUN; then
    echo "[dry-run] Would write: _bmad/custom/$f"
  else
    cp "$SRC_ROOT/_bmad/custom/$f" "$PROJECT_ROOT/_bmad/custom/$f"
    echo "wrote: _bmad/custom/$f"
  fi
done

# 3. Schemas — always overwrite
for f in prd architecture story change review; do
  if $DRY_RUN; then
    echo "[dry-run] Would write: _bmad/custom/grist-schemas/$f.grist.yaml"
  else
    cp "$SRC_ROOT/_bmad/custom/grist-schemas/$f.grist.yaml" \
       "$PROJECT_ROOT/_bmad/custom/grist-schemas/$f.grist.yaml"
    echo "wrote: _bmad/custom/grist-schemas/$f.grist.yaml"
  fi
done

# 4. Scripts — always overwrite
for f in post-prd-to-grist.py post-arch-to-grist.py post-story-to-grist.py post-dev-story.py post-code-review.py bmad-prd-to-grist.py; do
  if $DRY_RUN; then
    echo "[dry-run] Would write: _bmad/custom/grist-scripts/$f"
  else
    cp "$SRC_ROOT/_bmad/custom/grist-scripts/$f" "$PROJECT_ROOT/_bmad/custom/grist-scripts/$f"
    chmod +x "$PROJECT_ROOT/_bmad/custom/grist-scripts/$f"
    echo "wrote: _bmad/custom/grist-scripts/$f"
  fi
done

echo
echo "GRIST overlay installed at $PROJECT_ROOT/_bmad/custom/"
echo
echo "Next:"
echo "  1. Run BMAD planning (e.g. bmad-create-prd) — agent will emit prd.grist.yaml"
echo "     alongside prd.md, post-hook validates on completion."
echo "  2. Verify with: ls $PROJECT_ROOT/<planning_artifacts>/prd.grist.yaml"
echo "  3. Personal overrides go in .user.toml (gitignored), not .toml"
echo "  4. Uninstall: $0 $PROJECT_ROOT --uninstall"
