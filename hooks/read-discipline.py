#!/usr/bin/env python3
"""GRIST read-discipline hook (Claude Code PreToolUse, matcher: Read).

Deterministically enforces the GRIST read discipline:
  1. Never read whole files longer than 300 lines. Denied with guidance
     to re-read a targeted range or grep for the symbol first.
  2. Never read a prose .md artifact whole when a .grist.yaml sibling
     exists — denied with a redirect to the sibling / slice resolver.
     An explicit offset/limit range escapes (deliberate prose read).

Contract (Claude Code hooks):
  stdin  — JSON object with at least: tool_name, tool_input
           For Read: tool_input = {file_path, offset?, limit?}
  stdout — on deny, JSON:
           {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                   "permissionDecision": "deny",
                                   "permissionDecisionReason": "..."}}
  exit   — always 0 (fail open; a broken hook must never block work)

Escape hatch: GRIST_NO_HOOKS=1 disables enforcement.
Stdlib only. Python >= 3.7.
"""

import json
import os
import sys

MAX_LINES = 300

# Files that are meant to be read whole (compressed GRIST artifacts).
EXEMPT_BASENAMES = {"CLAUDE.md", "AGENTS.md"}
EXEMPT_SUFFIX = ".grist.yaml"
EXEMPT_DIR_PART = ".grist"


def allow():
    sys.exit(0)


def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


def is_exempt(file_path):
    basename = os.path.basename(file_path)
    if basename in EXEMPT_BASENAMES:
        return True
    if basename.endswith(EXEMPT_SUFFIX):
        return True
    # Anything under a .grist/ directory at any depth.
    parts = os.path.normpath(file_path).split(os.sep)
    if EXEMPT_DIR_PART in parts[:-1]:
        return True
    return False


def grist_sibling(file_path):
    """Return the .grist.yaml sibling for a prose .md artifact, or None."""
    if not file_path.endswith(".md"):
        return None
    stem = os.path.basename(file_path)[:-3]
    dirname = os.path.dirname(file_path) or "."
    for candidate in (stem + ".grist.yaml", stem.lower() + ".grist.yaml"):
        sibling = os.path.join(dirname, candidate)
        if os.path.isfile(sibling):
            return sibling
    try:
        entries = os.listdir(dirname)
    except OSError:
        return None
    target = stem.lower() + ".grist.yaml"
    for entry in entries:
        if entry.lower() == target:
            return os.path.join(dirname, entry)
    return None


def count_lines(file_path):
    """Return line count, or None if missing/unreadable/binary."""
    try:
        with open(file_path, "rb") as f:
            sample = f.read(8192)
            if b"\x00" in sample:
                return None  # binary
            n = sample.count(b"\n")
            while True:
                chunk = f.read(1024 * 1024)
                if not chunk:
                    break
                if b"\x00" in chunk:
                    return None  # binary
                n += chunk.count(b"\n")
        return n
    except OSError:
        return None


def main():
    try:
        payload = json.load(sys.stdin)  # always drain stdin first (avoid SIGPIPE)
    except (json.JSONDecodeError, ValueError):
        payload = None
    if os.environ.get("GRIST_NO_HOOKS") == "1" or payload is None:
        allow()

    if not isinstance(payload, dict) or payload.get("tool_name") != "Read":
        allow()

    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        allow()

    # A targeted read is already disciplined.
    if tool_input.get("offset") is not None or tool_input.get("limit") is not None:
        allow()

    file_path = tool_input.get("file_path")
    if not file_path or not isinstance(file_path, str):
        allow()

    if is_exempt(file_path):
        allow()

    sibling = grist_sibling(file_path)
    if sibling:
        deny(
            "GRIST: %s has a GRIST sibling — read %s instead (denser, same facts), "
            "or resolve one slice: python3 grist-get.py '<type>#<id>' --dir %s. "
            "To read the prose anyway, pass an explicit offset/limit range "
            "(or set GRIST_NO_HOOKS=1)."
            % (file_path, sibling, os.path.dirname(sibling) or ".")
        )

    n_lines = count_lines(file_path)
    if n_lines is None or n_lines <= MAX_LINES:
        allow()

    deny(
        "GRIST read discipline: %s is %d lines (>%d). "
        "Re-read with offset/limit targeting the relevant range, "
        "or grep for the symbol first." % (file_path, n_lines, MAX_LINES)
    )


if __name__ == "__main__":
    main()
