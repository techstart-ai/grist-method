#!/usr/bin/env python3
"""GRIST diff-discipline hook (Claude Code PreToolUse, matcher: Bash).

Closes the gap read-discipline leaves open: a whole-PR `git diff` is the
single largest context leak in a code review and it never goes through the
Read tool. This hook denies:

  1. `git diff <range>` with no pathspec whose reviewable size exceeds
     GRIST_DIFF_THRESHOLD lines (default 200). The size is measured with
     `git diff --numstat` on the same arguments — cheap, local, deterministic.
  2. `gh pr diff` / `glab mr diff` with no `--name-only` — network-sized,
     so denied outright in favour of grist-diff.py --pr / --mr.

Always allowed: --stat/--numstat/--name-only/--name-status/--shortstat/
--dirstat/--check/--quiet/--exit-code forms, any command with an explicit
pathspec (`-- <path>`), output piped through a limiter (head, grep, wc, awk,
sed -n, tail, cut, sort, uniq) or redirected to a file, and anything that is
not a diff at all. Small diffs under the threshold are allowed whole because
one call is cheaper than N per-file calls.

Contract (Claude Code hooks):
  stdin  — JSON: {tool_name: "Bash", tool_input: {command, ...}, cwd, ...}
  stdout — on deny: {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                            "permissionDecision": "deny",
                                            "permissionDecisionReason": "..."}}
  exit   — always 0 (fail open; a broken hook must never block work)

Escape hatches: GRIST_NO_HOOKS=1 disables; GRIST_DIFF_THRESHOLD=N tunes.
Stdlib only. Python >= 3.7.
"""

import json
import os
import re
import shlex
import subprocess
import sys

DEFAULT_THRESHOLD = 200

SUMMARY_FLAGS = {
    "--stat", "--numstat", "--name-only", "--name-status", "--shortstat",
    "--dirstat", "--check", "--quiet", "--exit-code", "--summary", "--compact-summary",
}
LIMITERS = {"head", "grep", "rg", "wc", "awk", "tail", "cut", "sort", "uniq", "sed", "jq", "python3", "python"}
GIT_DIFF_VALUE_FLAGS = {"-U", "--unified", "--diff-filter", "--color", "-l", "--diff-algorithm",
                        "--src-prefix", "--dst-prefix", "--output", "-O", "--relative"}


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


def threshold():
    try:
        return int(os.environ.get("GRIST_DIFF_THRESHOLD", DEFAULT_THRESHOLD))
    except ValueError:
        return DEFAULT_THRESHOLD


def segments(command):
    """Split a shell command line into pipelines, each a list of argv lists."""
    out = []
    for seg in re.split(r"\s*(?:&&|\|\||;|\n)\s*", command):
        if not seg.strip():
            continue
        stages = []
        for stage in re.split(r"\s*\|(?!\|)\s*", seg):
            try:
                argv = shlex.split(stage, posix=True)
            except ValueError:
                argv = stage.split()
            if argv:
                stages.append(argv)
        if stages:
            out.append(stages)
    return out


def strip_env_prefix(argv):
    i = 0
    while i < len(argv) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", argv[i]):
        i += 1
    return argv[i:]


def has_redirect(stage_text):
    return bool(re.search(r"(?<![<>])>\s*\S", stage_text))


def classify(argv):
    """Return ('git', args) | ('gh', args) | ('glab', args) | None."""
    argv = strip_env_prefix(argv)
    if len(argv) >= 2 and os.path.basename(argv[0]) == "git":
        # skip global options like -C <dir> / --no-pager
        i = 1
        while i < len(argv) and argv[i].startswith("-"):
            if argv[i] in ("-C", "-c", "--git-dir", "--work-tree"):
                i += 2
            else:
                i += 1
        if i < len(argv) and argv[i] == "diff":
            return "git", argv[i + 1:], argv[1:i]
    if len(argv) >= 3 and os.path.basename(argv[0]) == "gh" and argv[1] == "pr" and argv[2] == "diff":
        return "gh", argv[3:], []
    if len(argv) >= 3 and os.path.basename(argv[0]) == "glab" and argv[1] == "mr" and argv[2] == "diff":
        return "glab", argv[3:], []
    return None


def git_diff_size(global_opts, args, cwd):
    """Total +/- lines for `git diff <args>` via --numstat; None on any failure."""
    clean = []
    skip = False
    for a in args:
        if skip:
            skip = False
            continue
        if a in GIT_DIFF_VALUE_FLAGS:
            skip = True
            continue
        if a.startswith("-") and a != "--":
            continue  # drop presentation flags; keep refs and "--"
        clean.append(a)
    cmd = ["git"] + list(global_opts) + ["diff", "--numstat"] + clean
    try:
        p = subprocess.run(cmd, cwd=cwd or None, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    if p.returncode != 0:
        return None
    total = 0
    for line in p.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) >= 3 and parts[0].isdigit() and parts[1].isdigit():
            total += int(parts[0]) + int(parts[1])
    return total


def main():
    try:
        payload = json.load(sys.stdin)  # always drain stdin first (avoid SIGPIPE)
    except (json.JSONDecodeError, ValueError):
        payload = None
    if os.environ.get("GRIST_NO_HOOKS") == "1" or not isinstance(payload, dict):
        allow()
    if payload.get("tool_name") != "Bash":
        allow()
    tool_input = payload.get("tool_input") or {}
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not command or not isinstance(command, str):
        allow()
    if not re.search(r"\b(?:git\s+(?:(?:-\S+\s+\S+\s+|--\S+\s+)*)diff|gh\s+pr\s+diff|glab\s+mr\s+diff)\b", command):
        allow()

    cwd = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    limit = threshold()

    for stages in segments(command):
        producer = stages[0]
        info = classify(producer)
        if not info:
            continue
        kind, args, global_opts = info
        # A downstream limiter or a file redirect keeps the output out of context.
        if any(os.path.basename(strip_env_prefix(s)[0]) in LIMITERS for s in stages[1:] if strip_env_prefix(s)):
            continue
        if has_redirect(command):
            continue
        if any(a in SUMMARY_FLAGS or a.split("=")[0] in SUMMARY_FLAGS for a in args):
            continue
        if kind in ("gh", "glab"):
            deny(
                "GRIST diff discipline: `%s %s diff` pulls the whole %s into context. "
                "Orient first: python3 gristats/grist-diff.py --%s <n> (table of files, sizes, "
                "generated/vendor classification, read plan), then read hunks per file with "
                "git diff -U3 <base>...<head> -- <path>. Add --name-only to list files, or set "
                "GRIST_NO_HOOKS=1 to bypass."
                % (kind, "pr" if kind == "gh" else "mr", "PR" if kind == "gh" else "MR",
                   "pr" if kind == "gh" else "mr")
            )
        if "--" in args:
            continue  # explicit pathspec — targeted read
        size = git_diff_size(global_opts, args, cwd)
        if size is None or size <= limit:
            continue
        refs = " ".join(a for a in args if not a.startswith("-")) or "<range>"
        deny(
            "GRIST diff discipline: `git diff %s` is %d changed lines (>%d). "
            "Orient first: python3 gristats/grist-diff.py %s (compact table + read plan, "
            "skips generated/lockfile/vendor files), then read hunks one file at a time: "
            "git diff -U3 %s -- <path>. `git diff --stat %s` is always allowed. "
            "Tune with GRIST_DIFF_THRESHOLD=N or bypass with GRIST_NO_HOOKS=1."
            % (refs, size, limit, refs if refs != "<range>" else "", refs, refs)
        )
    allow()


if __name__ == "__main__":
    main()
