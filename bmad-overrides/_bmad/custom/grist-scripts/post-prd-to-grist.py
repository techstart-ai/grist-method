#!/usr/bin/env python3
"""on_complete hook for bmad-create-prd override.

Behavior:
  1. If <planning_artifacts>/prd.grist.yaml already exists (agent emitted it
     natively), validate shape and exit 0.
  2. Else, convert <planning_artifacts>/prd.md to prd.grist.yaml via the
     bmad-prd-to-grist converter and write it next to prd.md.
  3. On any error, print to stderr and exit non-zero so BMAD surfaces it.

Invoked by BMAD as:
    python3 .../grist-scripts/post-prd-to-grist.py {planning_artifacts}/prd.md
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


REQUIRED_FIELDS = ("prd", "problem", "goal", "epics", "acceptance")


def find_converter(start: Path) -> Path | None:
    """Locate bmad-prd-to-grist.py. Walk up looking for converters/."""
    for p in [start, *start.parents]:
        candidate = p / "grist" / "converters" / "bmad-prd-to-grist.py"
        if candidate.exists():
            return candidate
        candidate = p / "_bmad" / "custom" / "grist-scripts" / "bmad-prd-to-grist.py"
        if candidate.exists():
            return candidate
    return None


def validate(yaml_path: Path) -> list[str]:
    """Cheap structural check — no PyYAML dep. Returns list of issues."""
    text = yaml_path.read_text(encoding="utf-8")
    issues = []
    for field in REQUIRED_FIELDS:
        if not re.search(rf"^{field}\s*:", text, re.MULTILINE):
            issues.append(f"missing required field: {field}")
    if not re.search(r"^prd:\s*\S+", text, re.MULTILINE):
        issues.append("prd field is empty or missing slug")
    return issues


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: post-prd-to-grist.py <prd.md path>", file=sys.stderr)
        return 2

    prd_md = Path(argv[1]).resolve()
    if not prd_md.exists():
        print(f"prd.md not found: {prd_md}", file=sys.stderr)
        return 1

    out_yaml = prd_md.with_name("prd.grist.yaml")

    if out_yaml.exists():
        issues = validate(out_yaml)
        if issues:
            print(f"[grist] {out_yaml.name} exists but has issues:", file=sys.stderr)
            for i in issues:
                print(f"  - {i}", file=sys.stderr)
            return 1
        print(f"[grist] {out_yaml.name} present and valid; no conversion needed.")
        return 0

    converter = find_converter(prd_md.parent)
    if converter is None:
        print(
            "[grist] converter not found; expected at converters/bmad-prd-to-grist.py "
            "or _bmad/custom/grist-scripts/bmad-prd-to-grist.py",
            file=sys.stderr,
        )
        return 1

    slug = prd_md.parent.name.lower().replace(" ", "-") or "prd"
    try:
        result = subprocess.run(
            ["python3", str(converter), str(prd_md), "--slug", slug],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        print("[grist] converter failed:", file=sys.stderr)
        print(e.stderr, file=sys.stderr)
        return e.returncode

    out_yaml.write_text(result.stdout, encoding="utf-8")
    issues = validate(out_yaml)
    if issues:
        print(f"[grist] converted but {out_yaml.name} has issues:", file=sys.stderr)
        for i in issues:
            print(f"  - {i}", file=sys.stderr)
        return 1

    print(f"[grist] wrote {out_yaml}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
