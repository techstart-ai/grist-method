#!/usr/bin/env bash
# Install GRIST overlays into a BMAD project.
# Usage: ./install.sh <bmad-project-root>
#
# Idempotent: re-running upgrades the schemas + scripts in place.
# Existing user .toml files are preserved (overlay files only ship at
# .toml, not .user.toml — your personal overrides are untouched).

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <bmad-project-root>" >&2
  echo "  drops _bmad/custom/{toml,emission docs,scripts,schemas} into the project" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$1" && pwd)"
SRC_ROOT="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -d "$PROJECT_ROOT/_bmad" ]]; then
  echo "error: $PROJECT_ROOT does not look like a BMAD project (no _bmad/ dir)" >&2
  exit 1
fi

mkdir -p "$PROJECT_ROOT/_bmad/custom/grist-schemas" \
         "$PROJECT_ROOT/_bmad/custom/grist-scripts"

# 1. TOML overrides — only copy if target does not exist (don't clobber user edits)
for tool in bmad-create-prd bmad-create-architecture bmad-create-story bmad-dev-story bmad-code-review; do
  src="$SRC_ROOT/_bmad/custom/$tool.toml"
  dst="$PROJECT_ROOT/_bmad/custom/$tool.toml"
  if [[ -f "$dst" ]]; then
    echo "skip (exists): _bmad/custom/$tool.toml"
  else
    cp "$src" "$dst"
    echo "wrote: _bmad/custom/$tool.toml"
  fi
done

# 2. Emission rules — always overwrite (these are GRIST-controlled)
for f in grist-prd-emission.md grist-architecture-emission.md grist-story-emission.md grist-dev-story-emission.md grist-code-review-emission.md; do
  cp "$SRC_ROOT/_bmad/custom/$f" "$PROJECT_ROOT/_bmad/custom/$f"
  echo "wrote: _bmad/custom/$f"
done

# 3. Schemas — always overwrite
for f in prd architecture story change review; do
  cp "$SRC_ROOT/_bmad/custom/grist-schemas/$f.grist.yaml" \
     "$PROJECT_ROOT/_bmad/custom/grist-schemas/$f.grist.yaml"
  echo "wrote: _bmad/custom/grist-schemas/$f.grist.yaml"
done

# 4. Scripts — always overwrite
for f in post-prd-to-grist.py post-arch-to-grist.py post-story-to-grist.py post-dev-story.py post-code-review.py bmad-prd-to-grist.py; do
  cp "$SRC_ROOT/_bmad/custom/grist-scripts/$f" "$PROJECT_ROOT/_bmad/custom/grist-scripts/$f"
  chmod +x "$PROJECT_ROOT/_bmad/custom/grist-scripts/$f"
  echo "wrote: _bmad/custom/grist-scripts/$f"
done

echo
echo "GRIST overlay installed at $PROJECT_ROOT/_bmad/custom/"
echo
echo "Next:"
echo "  1. Run BMAD planning (e.g. bmad-create-prd) — agent will emit prd.grist.yaml"
echo "     alongside prd.md, post-hook validates on completion."
echo "  2. Verify with: ls $PROJECT_ROOT/<planning_artifacts>/prd.grist.yaml"
echo "  3. Personal overrides go in .user.toml (gitignored), not .toml"
