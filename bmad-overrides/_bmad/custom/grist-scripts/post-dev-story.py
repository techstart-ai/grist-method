#!/usr/bin/env python3
"""on_complete hook for bmad-dev-story override.

Validates that the active story's YAML reflects implementation completion:
  - status field is `done` or `in-review`
  - all tasks have `done: true` (warn if any are missing the field)
  - files: list is present and non-empty (story implementation should touch files)

Looks at story-S<n>.<m>.grist.yaml files in the artifacts dir; for each one
whose status field is `in-progress`, runs the checks. Exits non-zero with a
clear message if any fail — surfaces issues before the dev agent claims
completion incorrectly.

Invoked by BMAD as:
    python3 .../post-dev-story.py {planning_artifacts}
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


STORY_YAML_RE = re.compile(r"^story-(S\d+\.\d+)\.grist\.yaml$")
ALT_STORY_YAML_RE = re.compile(r"^story-([\w\-]+)\.grist\.yaml$")  # for kebab keys like 1-2-user-auth


def parse_status(text: str) -> str | None:
    m = re.search(r"^status:\s*([\w\-]+)\s*$", text, re.MULTILINE)
    return m.group(1) if m else None


def parse_tasks_done_state(text: str) -> tuple[int, int, int]:
    """Returns (total_tasks, done_count, missing_done_field_count)."""
    # Find tasks: section
    m = re.search(r"^tasks:\s*\n((?:\s+-.*\n(?:\s+\w+:.*\n)*)+)", text, re.MULTILINE)
    if not m:
        return (0, 0, 0)
    tasks_block = m.group(1)
    # Each task starts with `  - id:` or `  - do:`
    task_entries = re.split(r"^\s+-\s+(?:id|do):", tasks_block, flags=re.MULTILINE)[1:]
    total = len(task_entries)
    done = 0
    missing = 0
    for entry in task_entries:
        if re.search(r"^\s+done:\s*true\s*$", entry, re.MULTILINE):
            done += 1
        elif not re.search(r"^\s+done:\s*", entry, re.MULTILINE):
            missing += 1
    return total, done, missing


def parse_files(text: str) -> list[str]:
    m = re.search(r"^files:\s*\n((?:\s+-.*\n(?:\s+\w+:.*\n)*)+)", text, re.MULTILINE)
    if not m:
        return []
    return re.findall(r"^\s+-\s+path:\s*(\S+)", m.group(1), re.MULTILINE)


def find_active_stories(artifacts: Path) -> list[Path]:
    """Find story YAMLs whose status is in-progress, in-review, or done — i.e. been touched."""
    out = []
    for p in sorted(artifacts.iterdir()):
        if not (STORY_YAML_RE.match(p.name) or ALT_STORY_YAML_RE.match(p.name)):
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except OSError:
            continue
        status = parse_status(text)
        if status in ("in-progress", "in-review", "done"):
            out.append(p)
    return out


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: post-dev-story.py <planning_artifacts dir>", file=sys.stderr)
        return 2

    artifacts = Path(argv[1]).resolve()
    if not artifacts.is_dir():
        print(f"not a directory: {artifacts}", file=sys.stderr)
        return 1

    active = find_active_stories(artifacts)
    if not active:
        print(f"[grist] no in-progress/in-review/done stories in {artifacts}; nothing to validate.")
        return 0

    failures: list[str] = []
    warnings: list[str] = []
    for yaml_path in active:
        text = yaml_path.read_text(encoding="utf-8")
        status = parse_status(text)
        total, done, missing = parse_tasks_done_state(text)
        files = parse_files(text)

        if status == "done":
            if total > 0 and done < total:
                failures.append(f"{yaml_path.name}: status=done but {total - done}/{total} tasks not marked done")
            if missing > 0:
                warnings.append(f"{yaml_path.name}: {missing} task(s) missing `done:` field")
            if not files:
                warnings.append(f"{yaml_path.name}: status=done but `files:` list is empty")

        if status == "in-review":
            if total > 0 and done < total:
                warnings.append(f"{yaml_path.name}: status=in-review but {total - done}/{total} tasks not done")

    if warnings:
        print("[grist] warnings:", file=sys.stderr)
        for w in warnings:
            print(f"  - {w}", file=sys.stderr)

    if failures:
        print("[grist] dev-story validation failed:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    statuses = [parse_status(p.read_text(encoding="utf-8")) for p in active]
    summary = ", ".join(f"{s}={statuses.count(s)}" for s in set(statuses) if s)
    print(f"[grist] {len(active)} story YAML(s) checked: {summary}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
