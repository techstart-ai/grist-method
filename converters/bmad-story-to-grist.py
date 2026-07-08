#!/usr/bin/env python3
"""BMAD story-*.md → story-*.grist.yaml converter.

Best-effort heuristic parse of BMAD's prose story template. Output is a
draft — review and tighten before committing.

Extraction heuristics:
- Story id S<n>.<m> from filename (story-S1.1.md, story-1.1.md) or H1 heading
- Title from the H1 (minus the id) or a "Title" section
- Acceptance criteria from bullets under an Acceptance heading; a bullet
  containing given/when/then keeps them collapsed on one line
- Tasks from checkbox lists (- [ ] / - [x]) anywhere, else bullets under a
  Tasks heading
- Epic ref (E<n>) from an explicit mention, else derived from the story id

Usage:
    python bmad-story-to-grist.py story-S1.1.md > story-S1.1.grist.yaml
    python bmad-story-to-grist.py story-1.1.md --slug auth-v2 -o story-S1.1.grist.yaml
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def split_sections(md: str) -> dict:
    """Split markdown by H2 headings. {lowercased-heading: body}."""
    sections = {}
    current_h = None
    buf = []
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


def find_section(sections: dict, keys: list) -> str:
    for k in keys:
        for h, body in sections.items():
            if k in h:
                return body
    return ""


def parse_bullets(body: str) -> list:
    out = []
    for line in body.splitlines():
        m = re.match(r"^\s*[-*+]\s+(?!\[[ xX]\])(.+)$", line)
        if m:
            out.append(m.group(1).strip())
    return out


def parse_checkboxes(body: str) -> list:
    """Checkbox bullets → [{text, done}]."""
    out = []
    for line in body.splitlines():
        m = re.match(r"^\s*[-*+]\s+\[([ xX])\]\s+(.+)$", line)
        if m:
            out.append({"text": m.group(2).strip(), "done": m.group(1).lower() == "x"})
    return out


def strip_md(s: str) -> str:
    return re.sub(r"[*_`]", "", s).strip()


STORY_ID_RE = re.compile(r"\bS?(\d+)[.\-](\d+)\b")


def extract_story_id(path: Path, md: str) -> str:
    m = re.search(r"story[-_ ]*S?(\d+)[.\-](\d+)", path.stem, re.IGNORECASE)
    if m:
        return "S%s.%s" % (m.group(1), m.group(2))
    h1 = re.search(r"^#\s+(.+)$", md, re.MULTILINE)
    if h1:
        m = STORY_ID_RE.search(h1.group(1))
        if m:
            return "S%s.%s" % (m.group(1), m.group(2))
    m = STORY_ID_RE.search(md)
    if m:
        return "S%s.%s" % (m.group(1), m.group(2))
    return "S0.0"


def extract_title(md: str, sections: dict, story_id: str) -> str:
    h1 = re.search(r"^#\s+(.+)$", md, re.MULTILINE)
    if h1:
        title = strip_md(h1.group(1))
        # drop leading "Story S1.1:" / "S1.1 —" style prefixes
        title = re.sub(
            r"^(?:story\s*)?S?\d+[.\-]\d+\s*[:.\-—]?\s*", "", title, flags=re.IGNORECASE
        ).strip()
        if title:
            return title
    body = find_section(sections, ["title"])
    if body:
        return strip_md(body.splitlines()[0])
    return "<TBD>"


def extract_epic(md: str, story_id: str) -> str:
    m = re.search(r"\b(E\d+)\b", md)
    if m:
        return m.group(1)
    m = re.match(r"S(\d+)\.", story_id)
    if m:
        return "E%s" % m.group(1)
    return "E0"


GWT_RE = re.compile(r"\b(given|when|then)\b", re.IGNORECASE)


def parse_ac(body: str) -> list:
    """Acceptance criteria bullets; multi-line given/when/then blocks collapse."""
    ac = []
    items = parse_bullets(body) or [c["text"] for c in parse_checkboxes(body)]
    if not items:
        # numbered lists
        for line in body.splitlines():
            m = re.match(r"^\s*\d+[.)]\s+(.+)$", line)
            if m:
                items.append(m.group(1).strip())
    merged = []
    for item in items:
        item = strip_md(item)
        # continuation lines like "when ..." / "then ..." attach to the previous
        if merged and re.match(r"^(when|then|and)\b", item, re.IGNORECASE) and GWT_RE.match(merged[-1]):
            merged[-1] += ", " + item
        else:
            merged.append(item)
    for i, item in enumerate(merged, start=1):
        ac.append({"id": "ac%d" % i, "test": re.sub(r"\s+", " ", item)})
    return ac


def parse_tasks(md: str, sections: dict) -> list:
    boxes = parse_checkboxes(md)
    if not boxes:
        body = find_section(sections, ["tasks", "subtasks", "implementation"])
        boxes = [{"text": b, "done": False} for b in parse_bullets(body)] if body else []
    return [
        {"id": "t%d" % i, "do": strip_md(b["text"]), "done": b["done"]}
        for i, b in enumerate(boxes, start=1)
    ]


def yaml_escape(s: str) -> str:
    if not s:
        return '""'
    if any(c in s for c in [":", "#", "'", '"', "[", "]", "{", "}", "|", ">", "&", "*", "!", ","]):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if s.strip() != s or s.lower() in ("yes", "no", "true", "false", "null"):
        return '"' + s + '"'
    return s


def emit(data: dict) -> str:
    """TIGHT style: no comments, omit empty keys."""
    out = []
    out.append("story: %s" % data["story"])
    out.append("epic: prd#%s" % data["epic"])
    if data.get("slug"):
        out.append("prd: prd#%s" % data["slug"])
    out.append("title: %s" % yaml_escape(data["title"]))

    tasks = data.get("tasks") or []
    if tasks:
        out.append("tasks:")
        for t in tasks:
            out.append("  - id: %s" % t["id"])
            out.append("    do: %s" % yaml_escape(t["do"]))

    ac = data.get("ac") or []
    if ac:
        out.append("ac:")
        for a in ac:
            out.append("  - id: %s" % a["id"])
            out.append("    test: %s" % yaml_escape(a["test"]))

    status = "done" if tasks and all(t["done"] for t in tasks) else (
        "in-progress" if any(t["done"] for t in tasks) else "backlog"
    )
    out.append("status: %s" % status)
    return "\n".join(out) + "\n"


def convert(md: str, path: Path, slug: str) -> str:
    sections = split_sections(md)
    story_id = extract_story_id(path, md)
    data = {
        "story": story_id,
        "epic": extract_epic(md, story_id),
        "slug": slug,
        "title": extract_title(md, sections, story_id),
        "tasks": parse_tasks(md, sections),
        "ac": parse_ac(
            find_section(sections, ["acceptance", "success criteria", "definition of done"])
        ),
    }
    return emit(data)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path)
    ap.add_argument("--slug", help="PRD slug for the prd# ref (default: parent dir name)")
    ap.add_argument(
        "-o", "--output", type=Path,
        help="write output to this path (default: stdout)",
    )
    args = ap.parse_args()

    md = args.path.read_text(encoding="utf-8")
    slug = args.slug or args.path.resolve().parent.name.lower().replace(" ", "-")

    text = convert(md, args.path, slug)
    if args.output:
        args.output.write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
