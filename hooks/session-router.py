#!/usr/bin/env python3
"""GRIST session router (Claude Code UserPromptSubmit hook).

Auto-activates the right GRIST phase when BMAD / OpenSpec commands appear in
the prompt, persists that phase in .grist/session-state.json, and re-injects a
one-line reminder on every subsequent prompt so the mode never evaporates
mid-workflow. When no BMAD/OpenSpec state is armed, injects nothing — an
always-on chat style (e.g. caveman) owns output.

Phase mapping:
  /grist review, gh pr / glab mr, /code-review, BMAD code-review ... review
  BMAD dev-story ......................... ship
  BMAD anything else (prd, arch, story) .. design
  OpenSpec /opsx propose|apply|archive ... iterate
  /grist <mode> .......................... explicit override
  'stop grist' / '/grist off' ............ clear state

Contract (Claude Code hooks):
  stdin  — JSON: {prompt, cwd, session_id, ...}
  stdout — {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                   "additionalContext": "..."}}
  exit   — always 0 (fail open)

Escape hatch: GRIST_NO_HOOKS=1 disables everything.
Stdlib only. Python >= 3.7.
"""

import json
import os
import re
import sys
import time

STATE_REL = os.path.join(".grist", "session-state.json")

# --- trigger patterns -------------------------------------------------------

RE_OFF = re.compile(r"(?:^|\s)(?:/grist\s+off|stop\s+grist|normal\s+mode)\b", re.I)
RE_GRIST = re.compile(r"(?:^|\s)/grist\b(?:\s+(chat|design|iterate|ship|review))?", re.I)
RE_BMAD = re.compile(r"(?:^|\s)/bmad[\w:-]*|\bbmad[-:][\w:-]+", re.I)
RE_BMAD_SHIP = re.compile(r"dev[\s-]?story|story[\s-]?done", re.I)
RE_BMAD_REVIEW = re.compile(r"code[\s-]?review|review[\s-]?story", re.I)
# Command shapes only — a bare word like "review" or "openspec" in prose must not arm a phase.
RE_REVIEW = re.compile(
    r"(?:^|\s)(?:/code-review\b|/review-pr\b|gh\s+pr\s+(?:review|diff|view|checkout)\b|"
    r"glab\s+mr\s+(?:review|diff|view|checkout)\b|review\s+(?:pr|mr|pull\s+request|merge\s+request)\s*[#!]?\d+)",
    re.I)
RE_OPSX = re.compile(r"(?:^|\s)/(?:opsx[\w:-]*|openspec[\w:-]*)\b|\bopenspec\s+(?:propose|apply|archive|new|ff|continue|verify)\b", re.I)

FULL_CONTEXT = (
    "GRIST %(phase)s mode auto-active (%(why)s). Rules for the rest of this workflow:\n"
    "- Input: never read a whole file >300 lines (grep/range first); cite path:line, "
    "never re-paste code; resolve GRIST artifact slices by ID "
    "(python3 grist-get.py 'prd#E1' style), never whole-file reads.\n"
    "- Output: GRIST owns style while this mode is active — no preambles, no "
    "end-of-turn summaries, no task restatement; emit .grist.yaml artifacts in "
    "tight style (no comments, flow lists, omit empty keys). Any other terse "
    "chat style (e.g. caveman) is deferred until this mode exits.\n"
    "%(extra)s"
    "- Exit: 'stop grist' or '/grist off'."
)

REVIEW_EXTRA = (
    "- Review: orient with python3 gristats/grist-diff.py <base>...<head> (or --pr N) before any "
    "diff read; never `git diff` the whole PR above the threshold; read hunks with -U3 per file, "
    "context by line range, at most 3 context files; one read per range — answer later questions "
    "from what is already loaded. Emit .grist/reviews/review-<key>.grist.yaml (schemas/review.grist.yaml); "
    "python3 gristats/grist-render.py <file> --target github|gitlab|md writes the prose — you never do.\n"
)

REMINDER = (
    "GRIST %(phase)s mode active (auto). Read discipline + slice refs in force; "
    "GRIST owns output style — no preambles/summaries. Exit: 'stop grist'."
)


def out(context=None):
    if context:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": context,
            }
        }))
    sys.exit(0)


def project_dir(payload):
    return (
        os.environ.get("CLAUDE_PROJECT_DIR")
        or payload.get("cwd")
        or os.getcwd()
    )


def load_state(path):
    try:
        with open(path) as f:
            state = json.load(f)
        return state if isinstance(state, dict) and state.get("phase") else None
    except (OSError, ValueError):
        return None


def save_state(path, state):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            json.dump(state, f, indent=0)
            f.write("\n")
    except OSError:
        pass


def clear_state(path):
    try:
        os.remove(path)
    except OSError:
        pass


def detect_phase(prompt):
    """Return (phase, why) or (None, None)."""
    m = RE_GRIST.search(prompt)
    if m:
        return (m.group(1) or "ship").lower(), "explicit /grist"
    if RE_OPSX.search(prompt):
        return "iterate", "OpenSpec command detected"
    if RE_BMAD.search(prompt):
        if RE_BMAD_REVIEW.search(prompt):
            return "review", "BMAD code-review detected"
        if RE_BMAD_SHIP.search(prompt):
            return "ship", "BMAD dev workflow detected"
        return "design", "BMAD planning workflow detected"
    if RE_REVIEW.search(prompt):
        return "review", "PR review command detected"
    return None, None


def main():
    try:
        payload = json.load(sys.stdin)  # always drain stdin first (avoid SIGPIPE)
    except (json.JSONDecodeError, ValueError):
        payload = None
    if os.environ.get("GRIST_NO_HOOKS") == "1" or payload is None:
        out()
    if not isinstance(payload, dict):
        out()

    prompt = payload.get("prompt") or ""
    if not isinstance(prompt, str):
        out()

    state_path = os.path.join(project_dir(payload), STATE_REL)

    if RE_OFF.search(prompt):
        clear_state(state_path)
        out("GRIST mode off. Default chat style (e.g. caveman) owns output again.")

    state = load_state(state_path)
    phase, why = detect_phase(prompt)

    if phase:
        if state and state.get("phase") == phase:
            # Same phase re-triggered — just remind.
            out(REMINDER % {"phase": phase})
        save_state(state_path, {
            "phase": phase,
            "why": why,
            "armed_by": "prompt",
            "session_id": payload.get("session_id", ""),
            "ts": int(time.time()),
            "recalled": (state or {}).get("recalled", []),
        })
        out(FULL_CONTEXT % {"phase": phase, "why": why,
                            "extra": REVIEW_EXTRA if phase == "review" else ""})

    if state:
        # Freshly armed by activity-sniff (PreToolUse) — give the full block once.
        if state.get("armed_by") == "sniff" and not state.get("announced"):
            state["announced"] = True
            save_state(state_path, state)
            out(FULL_CONTEXT % {"phase": state["phase"],
                                "why": state.get("why", "workflow files detected"),
                                "extra": REVIEW_EXTRA if state["phase"] == "review" else ""})
        out(REMINDER % {"phase": state["phase"]})

    out()  # no state, no trigger — caveman/default owns the turn


if __name__ == "__main__":
    main()
