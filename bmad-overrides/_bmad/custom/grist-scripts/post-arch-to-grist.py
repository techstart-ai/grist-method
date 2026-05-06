#!/usr/bin/env python3
"""on_complete hook for bmad-create-architecture override.

Validates that architecture.grist.yaml exists alongside architecture.md and
has the required top-level fields. Does NOT auto-convert from prose — the
architecture document has too much technical nuance for regex extraction;
the agent must emit it natively per grist-architecture-emission.md.

If the YAML is missing, prints a loud warning so the user catches it before
downstream agents (story creation, dev) try to read it.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


REQUIRED_FIELDS = ("arch", "prd", "components", "decisions")


def validate(yaml_path: Path) -> list[str]:
    text = yaml_path.read_text(encoding="utf-8")
    issues = []
    for field in REQUIRED_FIELDS:
        if not re.search(rf"^{field}\s*:", text, re.MULTILINE):
            issues.append(f"missing required field: {field}")
    if not re.search(r"^arch:\s*\S+", text, re.MULTILINE):
        issues.append("arch field is empty or missing slug")
    if not re.search(r"^components:\s*\n\s*-\s+id:", text, re.MULTILINE):
        issues.append("components list empty — at least one C<n> entry required")
    return issues


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: post-arch-to-grist.py <architecture.md path>", file=sys.stderr)
        return 2

    arch_md = Path(argv[1]).resolve()
    out_yaml = arch_md.with_name("architecture.grist.yaml")

    if not out_yaml.exists():
        print(
            f"[grist] WARNING: {out_yaml.name} was not emitted by the workflow.\n"
            f"        Architecture YAML is required for downstream agents.\n"
            f"        Re-run bmad-create-architecture with grist-architecture-emission.md\n"
            f"        loaded as a persistent fact, or hand-author the YAML now.",
            file=sys.stderr,
        )
        return 1

    issues = validate(out_yaml)
    if issues:
        print(f"[grist] {out_yaml.name} has issues:", file=sys.stderr)
        for i in issues:
            print(f"  - {i}", file=sys.stderr)
        return 1

    print(f"[grist] {out_yaml.name} present and valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
