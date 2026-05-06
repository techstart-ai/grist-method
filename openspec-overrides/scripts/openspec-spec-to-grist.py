#!/usr/bin/env python3
"""Convert OpenSpec spec.md files to spec.grist.yaml.

Parses the OpenSpec spec format:

    ### Requirement: <name>
    The system SHALL <statement>.

    #### Scenario: <name>
    - **WHEN** <trigger>
    - **THEN** <outcome>

Emits a spec.grist.yaml conforming to schemas/spec.grist.yaml.
Best-effort regex parser — review output before committing.

Usage:
    python3 openspec-spec-to-grist.py openspec/specs/<capability>/spec.md
    python3 openspec-spec-to-grist.py --slug auth-login openspec/specs/auth-login/spec.md
    python3 openspec-spec-to-grist.py --in-place openspec/specs/auth-login/spec.md
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REQ_BLOCK_RE = re.compile(
    r"^###\s+Requirement:\s*(?P<name>.+?)\s*$"
    r"(?P<body>.*?)"
    r"(?=^###\s+Requirement:|^##\s+|\Z)",
    re.MULTILINE | re.DOTALL,
)
SCENARIO_BLOCK_RE = re.compile(
    r"^####\s+Scenario:\s*(?P<name>.+?)\s*$"
    r"(?P<body>.*?)"
    r"(?=^####\s+Scenario:|^###\s+Requirement:|^##\s+|\Z)",
    re.MULTILINE | re.DOTALL,
)
WHEN_RE = re.compile(r"^\s*-\s*\*\*WHEN\*\*\s*(.+?)\s*$", re.MULTILINE)
THEN_RE = re.compile(r"^\s*-\s*\*\*THEN\*\*\s*(.+?)\s*$", re.MULTILINE)
PURPOSE_RE = re.compile(r"^##\s+Purpose\s*\n(.+?)(?=^##|\Z)", re.MULTILINE | re.DOTALL)


def parse_purpose(text: str) -> str:
    m = PURPOSE_RE.search(text)
    if not m:
        # Fallback: first non-heading paragraph
        for para in text.split("\n\n"):
            p = para.strip()
            if p and not p.startswith("#"):
                return re.sub(r"\s+", " ", p)[:200]
        return ""
    body = m.group(1).strip()
    for para in body.split("\n\n"):
        p = para.strip()
        if p and not p.startswith("#"):
            return re.sub(r"\s+", " ", p)[:200]
    return ""


def parse_requirements(text: str) -> list[dict]:
    out = []
    for i, m in enumerate(REQ_BLOCK_RE.finditer(text), start=1):
        name = m.group("name").strip()
        body = m.group("body")
        # The requirement statement is the first non-empty line after the heading,
        # before the first scenario.
        pre_scenario = body.split("\n#### Scenario:", 1)[0]
        statement = ""
        for line in pre_scenario.splitlines():
            line = line.strip()
            if line and not line.startswith("#") and not line.startswith("-"):
                statement = line
                break
        if not statement:
            statement = name  # fallback to req name

        scenarios = []
        for j, sm in enumerate(SCENARIO_BLOCK_RE.finditer(body), start=1):
            sbody = sm.group("body")
            wm = WHEN_RE.search(sbody)
            tm = THEN_RE.search(sbody)
            scenarios.append(
                {
                    "id": f"s{j}",
                    "name": sm.group("name").strip(),
                    "when": wm.group(1).strip() if wm else "",
                    "then": tm.group(1).strip() if tm else "",
                }
            )

        out.append(
            {
                "id": f"req-{i}",
                "name": name,
                "req": statement,
                "scenarios": scenarios,
            }
        )
    return out


def yaml_quote(s: str) -> str:
    if not s:
        return '""'
    if any(c in s for c in [":", "#", '"', "'", "[", "]", "{", "}", "|", ">", "&", "*", "!"]):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if s.strip() != s or s.lower() in ("yes", "no", "true", "false", "null"):
        return '"' + s + '"'
    return s


def emit_yaml(slug: str, purpose: str, requirements: list[dict]) -> str:
    lines = [
        f"spec: {slug}",
        "version: 0.1.0",
        "status: active",
        f"purpose: {yaml_quote(purpose) if purpose else '<TBD>'}",
        "requirements:" if requirements else "requirements: []",
    ]
    for r in requirements:
        lines.append(f"  - id: {r['id']}")
        lines.append(f"    req: {yaml_quote(r['req'])}")
        if r["scenarios"]:
            lines.append("    scenarios:")
            for s in r["scenarios"]:
                lines.append(f"      - id: {s['id']}")
                if s["when"]:
                    lines.append(f"        when: {yaml_quote(s['when'])}")
                if s["then"]:
                    lines.append(f"        then: {yaml_quote(s['then'])}")
        else:
            lines.append("    scenarios: []")
    lines.append("history: []")
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path, help="path to spec.md")
    ap.add_argument("--slug", help="capability slug (default: parent dir name)")
    ap.add_argument(
        "--in-place",
        action="store_true",
        help="write spec.grist.yaml next to spec.md (default: stdout)",
    )
    args = ap.parse_args(argv[1:])

    if not args.path.exists():
        print(f"file not found: {args.path}", file=sys.stderr)
        return 1

    md = args.path.read_text(encoding="utf-8")
    slug = args.slug or args.path.parent.name.lower().replace(" ", "-") or "spec"
    purpose = parse_purpose(md)
    requirements = parse_requirements(md)

    yaml = emit_yaml(slug, purpose, requirements)

    if args.in_place:
        out = args.path.with_name("spec.grist.yaml")
        out.write_text(yaml, encoding="utf-8")
        print(f"wrote {out}", file=sys.stderr)
        print(f"  {len(requirements)} requirements, "
              f"{sum(len(r['scenarios']) for r in requirements)} scenarios", file=sys.stderr)
    else:
        sys.stdout.write(yaml)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
