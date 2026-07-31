#!/usr/bin/env python3
"""GRIST recall (Claude Code PostToolUse hook, matcher: Read).

Cue-based memory: when the agent opens a *.grist.yaml artifact, parse the ID
references it declares (epic: prd#E1, arch: arch#C2, ...), resolve each one
1 hop via grist-get, and inject the resolved slices as additionalContext — the
agent gets its dependencies without asking, and without whole-file reads.

Bounded by design:
  - 1 hop only: just the refs the opened artifact declares directly.
  - Max 8 refs per read, max ~1200 chars per resolved slice.
  - Each ref injected once per session (tracked in session-state 'recalled').

Every injection (and failed resolution) is logged to .grist/recall.log as
JSONL for `gristats recall` precision auditing.

Escape hatch: GRIST_NO_HOOKS=1. Stdlib only. Python >= 3.7. Always exits 0.
"""

import json
import os
import re
import subprocess
import sys
import time

STATE_REL = os.path.join(".grist", "session-state.json")
LOG_REL = os.path.join(".grist", "recall.log")

MAX_REFS = 8
MAX_SLICE_CHARS = 1200
RESOLVER_TIMEOUT = 10  # seconds

RE_REF = re.compile(
    r"\b((?:prd|arch|architecture|spec|story|change|review)"
    r"#[A-Za-z0-9._-]+(?:#[A-Za-z0-9._-]+)?)"
)


def out(context=None):
    if context:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": context,
            }
        }))
    sys.exit(0)


def find_resolver():
    here = os.path.dirname(os.path.abspath(__file__))
    for candidate in (
        os.path.join(here, "..", "gristats", "grist-get.py"),  # plugin layout
        os.path.join(here, "grist-get.py"),                    # .grist/hooks/ install
    ):
        candidate = os.path.normpath(candidate)
        if os.path.isfile(candidate):
            return candidate
    return None


def resolve(resolver, ref, search_dir):
    try:
        proc = subprocess.run(
            [sys.executable or "python3", resolver, ref, "--dir", search_dir],
            capture_output=True, text=True, timeout=RESOLVER_TIMEOUT,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    text = proc.stdout.strip()
    if not text:
        return None
    if len(text) > MAX_SLICE_CHARS:
        text = text[:MAX_SLICE_CHARS] + "\n# [truncated]"
    return text


def append_log(log_path, entry):
    try:
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        with open(log_path, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except OSError:
        pass


def main():
    try:
        payload = json.load(sys.stdin)  # always drain stdin first (avoid SIGPIPE)
    except (json.JSONDecodeError, ValueError):
        payload = None
    if os.environ.get("GRIST_NO_HOOKS") == "1" or payload is None:
        out()
    if not isinstance(payload, dict) or payload.get("tool_name") != "Read":
        out()

    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        out()
    file_path = tool_input.get("file_path")
    if not file_path or not isinstance(file_path, str):
        out()
    if not file_path.endswith(".grist.yaml"):
        out()

    try:
        with open(file_path) as f:
            content = f.read(65536)
    except OSError:
        out()

    refs = []
    for m in RE_REF.finditer(content):
        ref = m.group(1)
        if ref not in refs:
            refs.append(ref)
    refs = refs[:MAX_REFS]
    if not refs:
        out()

    project = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    state_path = os.path.join(project, STATE_REL)
    log_path = os.path.join(project, LOG_REL)

    # Once-per-session dedupe via session-state.
    state = {}
    try:
        with open(state_path) as f:
            state = json.load(f)
        if not isinstance(state, dict):
            state = {}
    except (OSError, ValueError):
        state = {}
    recalled = state.get("recalled") or []
    fresh = [r for r in refs if r not in recalled]
    if not fresh:
        out()

    resolver = find_resolver()
    session_id = payload.get("session_id", "")
    artifact_dir = os.path.dirname(os.path.abspath(file_path)) or "."
    now = int(time.time())

    slices, resolved_refs = [], []
    for ref in fresh:
        text = resolve(resolver, ref, artifact_dir) if resolver else None
        if text is None and resolver:
            # Artifacts may live outside the opened file's dir — one retry from root.
            text = resolve(resolver, ref, project)
        append_log(log_path, {
            "ts": now,
            "session_id": session_id,
            "phase": state.get("phase", ""),
            "artifact": file_path,
            "ref": ref,
            "resolved": text is not None,
            "chars": len(text) if text else 0,
        })
        if text is not None:
            slices.append("--- %s ---\n%s" % (ref, text))
            resolved_refs.append(ref)

    if not slices:
        out()

    if isinstance(state.get("phase"), str) and state.get("phase"):
        state["recalled"] = recalled + resolved_refs
        try:
            with open(state_path, "w") as f:
                json.dump(state, f)
                f.write("\n")
        except OSError:
            pass

    out(
        "GRIST recall — %s declares %d ref(s); resolved slices below. "
        "Do NOT re-read the source artifacts for this content.\n\n%s"
        % (os.path.basename(file_path), len(resolved_refs), "\n\n".join(slices))
    )


if __name__ == "__main__":
    main()
