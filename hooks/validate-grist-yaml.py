#!/usr/bin/env python3
"""GRIST artifact schema check (Claude Code PostToolUse, matcher: Write|Edit).

Validates *.grist.yaml artifacts right after they are written or edited.
Works without PyYAML: uses yaml.safe_load when available, otherwise falls
back to line-based structural checks.

Contract (Claude Code hooks):
  stdin  — JSON object with at least: tool_name, tool_input
           For Write: tool_input = {file_path, content}
           For Edit:  tool_input = {file_path, ...}
  stdout — hard failure: JSON {"decision": "block",
                               "reason": "GRIST schema check: <issues>"}
           soft issues:  plain-text warning line(s)
           valid:        nothing
  exit   — always 0

Hard failures (block): empty file; first non-comment line is not a known
artifact type key (prd:, architecture:, story:, change:, spec:, review:).
Soft issues (warn only): missing recommended top-level keys for the type;
tab characters used in indentation.

Escape hatch: GRIST_NO_HOOKS=1 disables enforcement.
Stdlib only. Python >= 3.7.
"""

import json
import os
import re
import sys

ARTIFACT_TYPES = ("prd", "architecture", "story", "change", "spec", "review")

# type -> list of requirement groups; each group is a tuple of alternatives,
# at least one of which should be present as a top-level key.
RECOMMENDED_KEYS = {
    "prd": [("problem",), ("goal",), ("epics",)],
    "architecture": [("decisions", "components")],
    "story": [("id", "story"), ("tasks", "acceptance")],
    "change": [("why", "delta")],
    "spec": [],
    "review": [],
}


def block(issues):
    print(json.dumps({
        "decision": "block",
        "reason": "GRIST schema check: " + "; ".join(issues),
    }))
    sys.exit(0)


def line_based_keys(text):
    """Line-based fallback: collect 'key:' names at top level and one
    indent level down (keys nested under the artifact type)."""
    keys = set()
    for line in text.splitlines():
        m = re.match(r"^[ \t]*([A-Za-z_][A-Za-z0-9_-]*)\s*:", line)
        if m:
            keys.add(m.group(1))
    return keys


def main():
    if os.environ.get("GRIST_NO_HOOKS") == "1":
        sys.exit(0)

    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    if not isinstance(payload, dict):
        sys.exit(0)
    if payload.get("tool_name") not in ("Write", "Edit"):
        sys.exit(0)

    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        sys.exit(0)

    file_path = tool_input.get("file_path")
    if not file_path or not isinstance(file_path, str):
        sys.exit(0)
    if not file_path.endswith(".grist.yaml"):
        sys.exit(0)
    if not os.path.isfile(file_path):
        sys.exit(0)

    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        sys.exit(0)

    # (a) non-empty — hard failure.
    if not text.strip():
        block(["%s is empty" % file_path])

    # (b) first non-comment, non-blank line must open a known artifact type.
    first_line = None
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped == "---":  # YAML document start marker
            continue
        first_line = line
        break

    if first_line is None:
        block(["%s contains only comments (no artifact body)" % file_path])

    m = re.match(r"^(%s)\s*:" % "|".join(ARTIFACT_TYPES), first_line.strip())
    if not m:
        block([
            "first non-comment line of %s must be one of: %s (got: %r)"
            % (file_path,
               ", ".join(t + ":" for t in ARTIFACT_TYPES),
               first_line.strip()[:60])
        ])

    artifact_type = m.group(1)
    warnings = []

    # Gather keys (nested under the artifact type, or top-level) — soft checks.
    keys = set()
    try:
        import yaml  # optional; not a dependency
        data = yaml.safe_load(text)
        if isinstance(data, dict):
            keys.update(k for k in data.keys() if isinstance(k, str))
            body = data.get(artifact_type)
            if isinstance(body, dict):
                keys.update(k for k in body.keys() if isinstance(k, str))
    except ImportError:
        keys.update(line_based_keys(text))
    except Exception:
        warnings.append("could not parse %s as YAML" % file_path)
        keys.update(line_based_keys(text))

    # (c) recommended keys per type — warn, don't block.
    for group in RECOMMENDED_KEYS.get(artifact_type, []):
        if not any(alt in keys for alt in group):
            warnings.append(
                "missing recommended key%s: %s"
                % ("" if len(group) == 1 else " (one of)", " or ".join(group))
            )

    # (d) tabs in indentation — warn, don't block.
    for i, line in enumerate(text.splitlines(), 1):
        if re.match(r"^ *\t", line):
            warnings.append("tab character in indentation at line %d" % i)
            break

    if warnings:
        print("GRIST schema warning (%s): %s" % (file_path, "; ".join(warnings)))

    sys.exit(0)


if __name__ == "__main__":
    main()
