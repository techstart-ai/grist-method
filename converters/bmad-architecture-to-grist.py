#!/usr/bin/env python3
"""BMAD architecture.md → architecture.grist.yaml converter.

Best-effort heuristic parse of BMAD's prose architecture template. Output is
a draft — review and tighten before committing.

Extraction heuristics:
- "Tech Stack" section (tables or "key: value" bullets) → stack:
- "Components"/"Services" H3 sub-sections or bullets → components:
- "Decisions"/ADR-style headings, or prose lines containing "we will use",
  "chosen", "decided" → decisions: [{id: d<n>, decision, why}]
- NFR section bullets → nfrs:
- Risks section bullets → risks:

Usage:
    python bmad-architecture-to-grist.py architecture.md > architecture.grist.yaml
    python bmad-architecture-to-grist.py architecture.md --slug auth-v2 -o architecture.grist.yaml
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


STACK_CATEGORIES = {
    "runtime": ["runtime", "language"],
    "framework": ["framework"],
    "db": ["db", "database", "storage"],
    "cache": ["cache", "caching"],
    "queue": ["queue", "messaging", "message broker"],
    "iac": ["iac", "infrastructure", "infra"],
}

DECISION_CUES = re.compile(
    r"\b(we will use|we chose|we (?:have )?decided|chosen|decision:)\b", re.IGNORECASE
)


def split_sections(md: str, level: int = 2) -> dict:
    """Split markdown by headings of the given level. {lowercased-heading: body}."""
    sections = {}
    current_h = None
    buf = []
    pat = re.compile(r"^" + "#" * level + r"\s+(.+?)\s*$")
    for line in md.splitlines():
        m = pat.match(line)
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


def find_section(sections: dict, keys: list) -> str:
    for k in keys:
        for h, body in sections.items():
            if k in h:
                return body
    return ""


def parse_bullets(body: str) -> list:
    out = []
    for line in body.splitlines():
        m = re.match(r"^\s*[-*+]\s+(.+)$", line)
        if m:
            out.append(m.group(1).strip())
    return out


def strip_md(s: str) -> str:
    """Remove bold/italic/code markers."""
    return re.sub(r"[*_`]", "", s).strip()


def parse_stack(body: str) -> dict:
    """Parse tech stack from 'key: value' bullets or markdown tables."""
    raw = {}
    for line in parse_bullets(body):
        if ":" in line:
            k, v = line.split(":", 1)
            raw[strip_md(k).lower()] = strip_md(v)
    # markdown table rows: | Category | Choice | ...
    for line in body.splitlines():
        m = re.match(r"^\s*\|([^|]+)\|([^|]+)\|", line)
        if m:
            k, v = strip_md(m.group(1)).lower(), strip_md(m.group(2))
            if k and v and set(k) != {"-"} and not re.fullmatch(r"[-\s:]+", v):
                raw[k] = v
    stack = {}
    for cat, aliases in STACK_CATEGORIES.items():
        for alias in aliases:
            for k, v in raw.items():
                if alias in k:
                    stack.setdefault(cat, v)
                    break
            if cat in stack:
                break
    # keep unmatched keys too (kebab them) so nothing is silently dropped
    for k, v in raw.items():
        if k in ("category", "choice", "technology", "tech"):
            continue
        if not any(alias in k for aliases in STACK_CATEGORIES.values() for alias in aliases):
            stack[re.sub(r"[^a-z0-9]+", "-", k).strip("-")] = v
    return stack


def parse_components(body: str) -> list:
    """Components from H3 sub-sections, else from bullets."""
    comps = []
    h3_blocks = re.split(r"^###\s+", body, flags=re.MULTILINE)
    if len(h3_blocks) > 1:
        for i, blk in enumerate(h3_blocks[1:], start=1):
            lines = blk.splitlines()
            name = strip_md(lines[0]) if lines else "component-%d" % i
            rest = "\n".join(lines[1:])
            purpose = parse_first_paragraph(rest) or (parse_bullets(rest)[:1] or [""])[0]
            comps.append({
                "id": "C%d" % i,
                "name": re.sub(r"[^A-Za-z0-9]+", "-", name).strip("-").lower(),
                "purpose": purpose,
            })
        return comps
    for i, line in enumerate(parse_bullets(body), start=1):
        if ":" in line:
            name, purpose = line.split(":", 1)
        elif " — " in line:
            name, purpose = line.split(" — ", 1)
        elif " - " in line:
            name, purpose = line.split(" - ", 1)
        else:
            name, purpose = line, ""
        comps.append({
            "id": "C%d" % i,
            "name": re.sub(r"[^A-Za-z0-9]+", "-", strip_md(name)).strip("-").lower(),
            "purpose": strip_md(purpose),
        })
    return comps


def parse_decisions(body: str, md: str) -> list:
    """Decisions from a Decisions section (H3 blocks or bullets), plus prose cues."""
    decisions = []
    seen = set()

    def add(decision: str, why: str) -> None:
        decision = strip_md(decision)
        why = strip_md(why)
        key = decision.lower()
        if not decision or key in seen:
            return
        seen.add(key)
        decisions.append({
            "id": "d%d" % (len(decisions) + 1),
            "decision": decision,
            "why": why or "TBD",
        })

    if body:
        h3_blocks = re.split(r"^###\s+", body, flags=re.MULTILINE)
        if len(h3_blocks) > 1:
            for blk in h3_blocks[1:]:
                lines = blk.splitlines()
                title = re.sub(r"^ADR[-\s]*\d+\s*[:.\-]?\s*", "", lines[0].strip(), flags=re.IGNORECASE)
                rest = "\n".join(lines[1:])
                why = ""
                m = re.search(r"(?:rationale|why|because)\s*[:\-]?\s*(.+)", rest, re.IGNORECASE)
                if m:
                    why = m.group(1).splitlines()[0].strip()
                else:
                    why = parse_first_paragraph(rest)
                add(title, why)
        else:
            for line in parse_bullets(body):
                m = re.search(r"\b(?:because|why:|rationale:|—|:)\s*(.*)$", line)
                if ":" in line:
                    d, w = line.split(":", 1)
                    add(d, w)
                elif " — " in line:
                    d, w = line.split(" — ", 1)
                    add(d, w)
                elif m and m.group(1):
                    add(line[: m.start()], m.group(1))
                else:
                    add(line, "")

    # prose cues anywhere in the doc ("we will use X because Y", "X was chosen ...")
    for line in md.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if DECISION_CUES.search(line):
            sentence = re.split(r"(?<=[.!?])\s+", strip_md(line.lstrip("-*+ ")))[0]
            m = re.search(r"\b(?:because|since|as)\b\s*(.+?)[.!?]?$", sentence, re.IGNORECASE)
            if m:
                add(sentence[: m.start()].rstrip(" ,;"), m.group(1))
            else:
                add(sentence.rstrip("."), "")
    return decisions


def parse_risks(body: str) -> list:
    risks = []
    for i, line in enumerate(parse_bullets(body), start=1):
        if ":" in line:
            risk, mit = line.split(":", 1)
            risks.append({"id": "ar%d" % i, "risk": risk.strip(), "mitigation": mit.strip()})
        else:
            risks.append({"id": "ar%d" % i, "risk": line, "mitigation": "TBD"})
    return risks


def parse_first_paragraph(body: str) -> str:
    for para in body.split("\n\n"):
        p = para.strip()
        if p and not p.startswith("#") and not re.match(r"^\s*[-*+|]", p):
            return re.sub(r"\s+", " ", p)
    return ""


def yaml_escape(s: str) -> str:
    if not s:
        return '""'
    if any(c in s for c in [":", "#", "'", '"', "[", "]", "{", "}", "|", ">", "&", "*", "!", ","]):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if s.strip() != s or s.lower() in ("yes", "no", "true", "false", "null"):
        return '"' + s + '"'
    return s


def emit(slug: str, data: dict) -> str:
    """TIGHT style: no comments, flow lists for scalars, omit empty keys."""
    out = []
    out.append("arch: %s" % slug)
    out.append("prd: prd#%s" % slug)

    stack = data.get("stack") or {}
    if stack:
        out.append("stack:")
        for k, v in stack.items():
            out.append("  %s: %s" % (k, yaml_escape(v)))

    comps = data.get("components") or []
    if comps:
        out.append("components:")
        for c in comps:
            out.append("  - id: %s" % c["id"])
            out.append("    name: %s" % yaml_escape(c["name"]))
            if c.get("purpose"):
                out.append("    purpose: %s" % yaml_escape(c["purpose"]))

    decisions = data.get("decisions") or []
    if decisions:
        out.append("decisions:")
        for d in decisions:
            out.append("  - id: %s" % d["id"])
            out.append("    decision: %s" % yaml_escape(d["decision"]))
            out.append("    why: %s" % yaml_escape(d["why"]))

    nfrs = data.get("nfrs") or []
    if nfrs:
        out.append("nfrs: [%s]" % ", ".join(yaml_escape(n) for n in nfrs))

    risks = data.get("risks") or []
    if risks:
        out.append("risks:")
        for r in risks:
            out.append("  - id: %s" % r["id"])
            out.append("    risk: %s" % yaml_escape(r["risk"]))
            out.append("    mitigation: %s" % yaml_escape(r["mitigation"]))

    return "\n".join(out) + "\n"


def convert(md: str, slug: str) -> str:
    sections = split_sections(md)
    data = {}

    stack_body = find_section(sections, ["tech stack", "stack", "technology"])
    if stack_body:
        data["stack"] = parse_stack(stack_body)

    comp_body = find_section(sections, ["components", "services", "system components", "modules"])
    if comp_body:
        data["components"] = parse_components(comp_body)

    dec_body = find_section(sections, ["decisions", "architecture decision", "adr", "key decisions"])
    data["decisions"] = parse_decisions(dec_body, md)

    nfr_body = find_section(
        sections,
        ["non-functional", "nfrs", "nfr", "quality attributes", "performance"],
    )
    if nfr_body:
        data["nfrs"] = parse_bullets(nfr_body)

    risk_body = find_section(sections, ["risks"])
    if risk_body:
        data["risks"] = parse_risks(risk_body)

    return emit(slug, data)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path)
    ap.add_argument("--slug", help="arch slug (default: file stem, or parent dir for architecture.md)")
    ap.add_argument(
        "-o", "--output", type=Path,
        help="write output to this path (default: stdout)",
    )
    args = ap.parse_args()

    md = args.path.read_text(encoding="utf-8")
    stem = args.path.stem.lower()
    if stem in ("architecture", "arch") and args.path.resolve().parent.name:
        default_slug = args.path.resolve().parent.name.lower().replace(" ", "-")
    else:
        default_slug = stem.replace(" ", "-")
    slug = args.slug or default_slug

    text = convert(md, slug)
    if args.output:
        args.output.write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
