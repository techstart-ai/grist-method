#!/usr/bin/env python3
"""GRIST activity sniff (Claude Code PreToolUse hook, matcher: Read|Write|Edit).

Catches BMAD / OpenSpec sessions the prompt regex misses (resumed sessions,
workflows invoked indirectly): any tool touch on _bmad/**, _bmad-output/**, or
openspec/** arms .grist/session-state.json so the session router injects GRIST
rules from the next prompt on. Never denies anything.

Phase heuristics:
  openspec/** ............................ iterate
  _bmad/**: Read of story-*.grist.yaml/.md  ship   (dev consumes stories)
  _bmad/**: anything else ................ design (planning emits artifacts)

Only arms when no state exists — a prompt-armed or explicit phase always wins.

Escape hatch: GRIST_NO_HOOKS=1. Stdlib only. Python >= 3.7. Always exits 0.
"""

import json
import os
import re
import sys
import time

STATE_REL = os.path.join(".grist", "session-state.json")

BMAD_DIRS = {"_bmad", "_bmad-output", "bmad-output"}
OPENSPEC_DIRS = {"openspec"}
RE_STORY = re.compile(r"^story-.*\.(?:grist\.yaml|md)$", re.I)


def allow():
    sys.exit(0)


def main():
    try:
        payload = json.load(sys.stdin)  # always drain stdin first (avoid SIGPIPE)
    except (json.JSONDecodeError, ValueError):
        payload = None
    if os.environ.get("GRIST_NO_HOOKS") == "1" or payload is None:
        allow()
    if not isinstance(payload, dict):
        allow()

    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        allow()
    file_path = tool_input.get("file_path")
    if not file_path or not isinstance(file_path, str):
        allow()

    parts = set(os.path.normpath(file_path).split(os.sep))
    if parts & OPENSPEC_DIRS:
        phase, why = "iterate", "openspec/ activity detected"
    elif parts & BMAD_DIRS:
        basename = os.path.basename(file_path)
        if payload.get("tool_name") == "Read" and RE_STORY.match(basename):
            phase, why = "ship", "BMAD story read detected"
        else:
            phase, why = "design", "_bmad/ activity detected"
    else:
        allow()

    project = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    state_path = os.path.join(project, STATE_REL)

    if os.path.isfile(state_path):
        allow()  # existing phase wins; never flip-flop mid-session

    try:
        os.makedirs(os.path.dirname(state_path), exist_ok=True)
        with open(state_path, "w") as f:
            json.dump({
                "phase": phase,
                "why": why,
                "armed_by": "sniff",
                "session_id": payload.get("session_id", ""),
                "ts": int(time.time()),
                "recalled": [],
            }, f)
            f.write("\n")
    except OSError:
        pass
    allow()


if __name__ == "__main__":
    main()
