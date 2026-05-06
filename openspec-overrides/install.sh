#!/usr/bin/env bash
# Install the GRIST OpenSpec schema into a project.
# Usage: ./install.sh <openspec-project-root>
#
# Idempotent: re-running upgrades schema files in place. Existing
# openspec/config.yaml is preserved (script prints the line to add manually
# if `schema: grist` is not already set).

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <openspec-project-root>" >&2
  echo "  drops openspec/schemas/grist/ + scripts/ into the project" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$1" && pwd)"
SRC_ROOT="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -d "$PROJECT_ROOT/openspec" ]]; then
  echo "error: $PROJECT_ROOT does not look like an OpenSpec project (no openspec/ dir)" >&2
  echo "  run \`openspec init\` first" >&2
  exit 1
fi

mkdir -p "$PROJECT_ROOT/openspec/schemas/grist/templates" \
         "$PROJECT_ROOT/openspec/scripts"

# 1. Schema files — always overwrite (GRIST-controlled)
cp "$SRC_ROOT/schemas/grist/schema.yaml" \
   "$PROJECT_ROOT/openspec/schemas/grist/schema.yaml"
echo "wrote: openspec/schemas/grist/schema.yaml"

cp "$SRC_ROOT/schemas/grist/README.md" \
   "$PROJECT_ROOT/openspec/schemas/grist/README.md"
echo "wrote: openspec/schemas/grist/README.md"

for f in change.grist.yaml tasks.md; do
  cp "$SRC_ROOT/schemas/grist/templates/$f" \
     "$PROJECT_ROOT/openspec/schemas/grist/templates/$f"
  echo "wrote: openspec/schemas/grist/templates/$f"
done

# 2. Conversion script — always overwrite
cp "$SRC_ROOT/scripts/openspec-spec-to-grist.py" \
   "$PROJECT_ROOT/openspec/scripts/openspec-spec-to-grist.py"
chmod +x "$PROJECT_ROOT/openspec/scripts/openspec-spec-to-grist.py"
echo "wrote: openspec/scripts/openspec-spec-to-grist.py"

# 3. Validate schema
if command -v openspec >/dev/null 2>&1; then
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
  cp "$SRC_ROOT/config.yaml.example" "$CONFIG"
  echo "wrote: openspec/config.yaml (with schema: grist activated)"
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
