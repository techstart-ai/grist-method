#!/usr/bin/env python3
"""on_complete hook for bmad-create-story override.

Validates that for every story-S<n>.<m>.md present in <planning_artifacts>,
a matching story-S<n>.<m>.grist.yaml also exists and has required fields.
Updates sprint-status.grist.yaml if present (lightweight: just records that
the story file was emitted).

Invoked by BMAD as:
    python3 .../post-story-to-grist.py {planning_artifacts}
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


REQUIRED_FIELDS = ("story", "epic", "prd", "title", "tasks", "ac", "files", "status")
STORY_RE = re.compile(r"^story-(S\d+\.\d+)\.md$")


def validate(yaml_path: Path) -> list[str]:
    text = yaml_path.read_text(encoding="utf-8")
    issues = []
    for field in REQUIRED_FIELDS:
        if not re.search(rf"^{field}\s*:", text, re.MULTILINE):
            issues.append(f"missing required field: {field}")
    if not re.search(r"^story:\s*S\d+\.\d+", text, re.MULTILINE):
        issues.append("story field missing or not S<n>.<m> format")
    return issues


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: post-story-to-grist.py <planning_artifacts dir>", file=sys.stderr)
        return 2

    artifacts = Path(argv[1]).resolve()
    if not artifacts.is_dir():
        print(f"not a directory: {artifacts}", file=sys.stderr)
        return 1

    md_stories = sorted(p for p in artifacts.iterdir() if STORY_RE.match(p.name))
    if not md_stories:
        print(f"[grist] no story-S<n>.<m>.md files in {artifacts}; nothing to validate.")
        return 0

    failures = []
    for md in md_stories:
        sid = STORY_RE.match(md.name).group(1)
        yaml_path = md.with_name(f"story-{sid}.grist.yaml")
        if not yaml_path.exists():
            failures.append(f"{yaml_path.name} missing for {md.name}")
            continue
        issues = validate(yaml_path)
        if issues:
            failures.append(f"{yaml_path.name}: " + "; ".join(issues))

    if failures:
        print("[grist] story validation failed:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(f"[grist] {len(md_stories)} story YAML(s) present and valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
