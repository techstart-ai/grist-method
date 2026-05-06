#!/usr/bin/env python3
"""BMAD PRD.md → prd.grist.yaml converter.

Best-effort regex parse of BMAD's standard PRD.md sections. Output is a
draft — review and tighten before committing. Sections BMAD doesn't emit
verbatim (problem, goal) are extracted from the first paragraph or first
H2 section if present.

Usage:
    python bmad-prd-to-grist.py PRD.md > prd.grist.yaml
    python bmad-prd-to-grist.py PRD.md --slug auth-v2 > prd.grist.yaml
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


HEADING_MAP = {
    "problem": ["problem statement", "problem", "background", "context"],
    "goal": ["goal", "goals", "objective", "objectives"],
    "nonGoals": ["non-goals", "non goals", "out of scope"],
    "invariants": ["invariants", "constraints", "must-haves"],
    "epics": ["epics", "epic list", "features"],
    "acceptance": ["acceptance criteria", "success criteria", "definition of done"],
    "risks": ["risks", "risks and mitigations", "risks & mitigations"],
    "nfrs": ["non-functional requirements", "nfrs", "nfr", "performance", "quality attributes"],
    "stakeholders": ["stakeholders", "approvers"],
}


def split_sections(md: str) -> dict[str, str]:
    """Split markdown by H2 headings. Returns {lowercased-heading: body}."""
    sections = {}
    current_h = None
    buf: list[str] = []
    for line in md.splitlines():
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            if current_h is not None:
                sections[current_h.lower().strip()] = "\n".join(buf).strip()
            current_h = m.group(1)
            buf = []
        else:
            buf.append(line)
    if current_h is not None:
        sections[current_h.lower().strip()] = "\n".join(buf).strip()
    return sections


def find_section(sections: dict[str, str], keys: list[str]) -> str | None:
    for k in keys:
        for h, body in sections.items():
            if k in h:
                return body
    return None


def parse_bullets(body: str) -> list[str]:
    out = []
    for line in body.splitlines():
        m = re.match(r"^\s*[-*+]\s+(.+)$", line)
        if m:
            out.append(m.group(1).strip())
    return out


def parse_first_paragraph(body: str) -> str:
    for para in body.split("\n\n"):
        p = para.strip()
        if p and not p.startswith("#"):
            return re.sub(r"\s+", " ", p)
    return ""


def parse_epics(body: str) -> list[dict]:
    """Parse epic list. Accepts either bullet list or H3 sub-sections."""
    epics: list[dict] = []
    h3_blocks = re.split(r"^###\s+", body, flags=re.MULTILINE)
    if len(h3_blocks) > 1:
        for i, blk in enumerate(h3_blocks[1:], start=1):
            lines = blk.splitlines()
            title = lines[0].strip() if lines else f"Epic {i}"
            stories = [
                s.strip() for s in re.findall(r"\b(S\d+\.\d+)\b", blk)
            ]
            epics.append({"id": f"E{i}", "title": title, "stories": stories or []})
        return epics
    for i, line in enumerate(parse_bullets(body), start=1):
        epics.append({"id": f"E{i}", "title": line, "stories": []})
    return epics


def parse_risks(body: str) -> list[dict]:
    risks = []
    for i, line in enumerate(parse_bullets(body), start=1):
        if ":" in line:
            risk, mit = line.split(":", 1)
            risks.append(
                {"id": f"r{i}", "risk": risk.strip(), "mitigation": mit.strip()}
            )
        else:
            risks.append({"id": f"r{i}", "risk": line, "mitigation": "TBD"})
    return risks


def parse_acceptance(body: str) -> list[dict]:
    return [
        {"id": f"ac{i}", "criterion": line}
        for i, line in enumerate(parse_bullets(body), start=1)
    ]


def yaml_escape(s: str) -> str:
    """Minimal YAML scalar escape — quote if any of these chars present."""
    if not s:
        return '""'
    if any(c in s for c in [":", "#", "'", '"', "[", "]", "{", "}", "|", ">", "&", "*", "!"]):
        return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
    if s.strip() != s or s.lower() in ("yes", "no", "true", "false", "null"):
        return '"' + s + '"'
    return s


def emit(slug: str, data: dict) -> str:
    out: list[str] = []
    out.append(f"prd: {slug}")
    out.append("phase: planning")
    out.append("inputs: []")
    out.append(f"problem: {yaml_escape(data.get('problem', '<TBD>'))}")
    out.append(f"goal: {yaml_escape(data.get('goal', '<TBD>'))}")

    out.append("nonGoals:")
    for x in data.get("nonGoals", []):
        out.append(f"  - {yaml_escape(x)}")
    if not data.get("nonGoals"):
        out[-1] = "nonGoals: []"

    out.append("invariants:")
    for x in data.get("invariants", []):
        out.append(f"  - {yaml_escape(x)}")
    if not data.get("invariants"):
        out[-1] = "invariants: []"

    out.append("epics:")
    epics = data.get("epics", [])
    if not epics:
        out[-1] = "epics: []"
    for e in epics:
        out.append(f"  - id: {e['id']}")
        out.append(f"    title: {yaml_escape(e['title'])}")
        stories = e.get("stories", [])
        if stories:
            out.append(f"    stories: [{', '.join(stories)}]")
        else:
            out.append("    stories: []")

    out.append("acceptance:")
    acc = data.get("acceptance", [])
    if not acc:
        out[-1] = "acceptance: []"
    for a in acc:
        out.append(f"  - id: {a['id']}")
        out.append(f"    criterion: {yaml_escape(a['criterion'])}")

    out.append("risks:")
    risks = data.get("risks", [])
    if not risks:
        out[-1] = "risks: []"
    for r in risks:
        out.append(f"  - id: {r['id']}")
        out.append(f"    risk: {yaml_escape(r['risk'])}")
        out.append(f"    mitigation: {yaml_escape(r['mitigation'])}")

    out.append("nfrs:")
    nfrs = data.get("nfrs", [])
    if not nfrs:
        out[-1] = "nfrs: []"
    for n in nfrs:
        out.append(f"  - {yaml_escape(n)}")

    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path)
    ap.add_argument("--slug", help="PRD slug (default: file stem)")
    args = ap.parse_args()

    md = args.path.read_text(encoding="utf-8")
    slug = args.slug or args.path.stem.lower().replace(" ", "-")
    sections = split_sections(md)

    data: dict = {}
    for key, candidates in HEADING_MAP.items():
        body = find_section(sections, candidates)
        if not body:
            continue
        if key in ("problem", "goal"):
            data[key] = parse_first_paragraph(body)
        elif key == "epics":
            data[key] = parse_epics(body)
        elif key == "risks":
            data[key] = parse_risks(body)
        elif key == "acceptance":
            data[key] = parse_acceptance(body)
        else:
            data[key] = parse_bullets(body)

    sys.stdout.write(emit(slug, data))
    return 0


if __name__ == "__main__":
    sys.exit(main())
