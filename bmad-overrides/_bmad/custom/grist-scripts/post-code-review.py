#!/usr/bin/env python3
"""on_complete hook for bmad-code-review override.

Validates that a review-<story_key>.grist.yaml exists for the just-completed
review pass and has the required structure. If missing, attempts to extract
findings from the in-story markdown bullets that step-04-present.md writes,
and emits a draft review YAML.

Behavior:
  1. Look for the most recently modified review-*.grist.yaml in the artifacts
     dirs. If exists and well-formed, validate and exit 0.
  2. If missing, scan story-*.md files for a "### Review Findings" section
     and convert the bullets into a draft review-<story_key>.grist.yaml.
  3. Exit non-zero if validation fails.

Invoked by BMAD as:
    python3 .../post-code-review.py {planning_artifacts} {implementation_artifacts}
"""
from __future__ import annotations

import re
import sys
from datetime import date
from pathlib import Path


REVIEW_YAML_RE = re.compile(r"^review-([\w\-]+)\.grist\.yaml$")
STORY_MD_RE = re.compile(r"^story-([\w\-]+)\.md$|^([\w\-]+\d-\d-[\w\-]+)\.md$")
REQUIRED_FIELDS = ("review", "story", "date", "findings", "counts")
BULLET_RE = re.compile(
    r"^-\s+\[(?P<box>[ x])\]\s+\[Review\]\[(?P<class>Decision|Patch|Defer)\]\s+(?P<title>[^—\[]+?)(?:\s*—\s*(?P<detail>.+?))?(?:\s*\[(?P<loc>[^\]]+)\])?\s*$",
    re.MULTILINE,
)


def collect_dirs(*paths: str) -> list[Path]:
    out = []
    for p in paths:
        if p:
            pp = Path(p).resolve()
            if pp.is_dir():
                out.append(pp)
    return out


def find_review_yamls(dirs: list[Path]) -> list[Path]:
    out = []
    for d in dirs:
        for p in d.iterdir():
            if REVIEW_YAML_RE.match(p.name):
                out.append(p)
    return sorted(out, key=lambda p: p.stat().st_mtime, reverse=True)


def validate(yaml_path: Path) -> list[str]:
    text = yaml_path.read_text(encoding="utf-8")
    issues = []
    for field in REQUIRED_FIELDS:
        if not re.search(rf"^{field}\s*:", text, re.MULTILINE):
            issues.append(f"missing required field: {field}")
    if not re.search(r"^findings:\s*\n\s*-\s+id:", text, re.MULTILINE):
        # findings: [] is also OK (clean review)
        if not re.search(r"^findings:\s*\[\s*\]\s*$", text, re.MULTILINE):
            issues.append("findings: list malformed (expected `- id: f<n>` entries or empty `[]`)")
    return issues


def find_story_with_findings(dirs: list[Path]) -> tuple[Path, str] | None:
    """Find a story-*.md whose body contains a `### Review Findings` section.
    Returns (story_path, story_key)."""
    candidates = []
    for d in dirs:
        for p in d.iterdir():
            if not p.name.endswith(".md"):
                continue
            try:
                text = p.read_text(encoding="utf-8")
            except OSError:
                continue
            if "### Review Findings" not in text:
                continue
            # Extract story key from filename: story-S1.1.md or 1-2-user-auth.md
            stem = p.stem
            stem = re.sub(r"^story-", "", stem)
            candidates.append((p, stem, p.stat().st_mtime))
    if not candidates:
        return None
    candidates.sort(key=lambda t: t[2], reverse=True)
    return (candidates[0][0], candidates[0][1])


def parse_findings_from_story(md_text: str) -> list[dict]:
    """Extract review bullets from a story file's `### Review Findings` section."""
    m = re.search(
        r"###\s+Review\s+Findings\s*\n(.+?)(?=\n##|\Z)",
        md_text,
        re.DOTALL,
    )
    if not m:
        return []
    section = m.group(1)
    findings = []
    for i, bm in enumerate(BULLET_RE.finditer(section), start=1):
        cls_map = {"Decision": "decision-needed", "Patch": "patch", "Defer": "defer"}
        findings.append(
            {
                "id": f"f{i}",
                "class": cls_map[bm.group("class")],
                "loc": (bm.group("loc") or "general:-").strip(),
                "title": (bm.group("title") or "").strip(),
                "detail": (bm.group("detail") or "").strip(),
                "box": bm.group("box"),
            }
        )
    return findings


def yaml_quote(s: str) -> str:
    if not s:
        return '""'
    if any(c in s for c in [":", "#", '"', "'", "[", "]", "{", "}", "|", ">", "&", "*", "!"]):
        return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
    if s.strip() != s:
        return '"' + s + '"'
    return s


def emit_review_yaml(story_key: str, findings: list[dict]) -> str:
    counts = {"decision_needed": 0, "patch": 0, "defer": 0, "dismissed": 0}
    for f in findings:
        if f["class"] == "decision-needed":
            counts["decision_needed"] += 1
        elif f["class"] == "patch":
            counts["patch"] += 1
        elif f["class"] == "defer":
            counts["defer"] += 1

    lines = [
        f"review: {yaml_quote(story_key)}",
        f"story: {yaml_quote(f'story#{story_key}')}",
        f"date: {date.today().isoformat()}",
        "mode: full",
        'diff_source: ""',
        "spec: null",
        "layers_ran: []",
        "failed_layers: []",
        "findings:" if findings else "findings: []",
    ]
    for f in findings:
        lines.append(f"  - id: {f['id']}")
        lines.append(f"    class: {f['class']}")
        lines.append(f"    loc: {yaml_quote(f['loc'])}")
        lines.append(f"    title: {yaml_quote(f['title'])}")
        lines.append(f"    detail: {yaml_quote(f['detail'])}")
    lines.append("counts:")
    for k, v in counts.items():
        lines.append(f"  {k}: {v}")
    lines.append("resolutions: []")
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: post-code-review.py <planning_artifacts> [implementation_artifacts]", file=sys.stderr)
        return 2

    dirs = collect_dirs(*argv[1:])
    if not dirs:
        print("[grist] no valid artifact dirs given", file=sys.stderr)
        return 1

    existing = find_review_yamls(dirs)
    if existing:
        latest = existing[0]
        issues = validate(latest)
        if issues:
            print(f"[grist] {latest.name} has issues:", file=sys.stderr)
            for i in issues:
                print(f"  - {i}", file=sys.stderr)
            return 1
        print(f"[grist] {latest.name} present and valid.")
        return 0

    # Fallback: extract from a story file with Review Findings section
    found = find_story_with_findings(dirs)
    if not found:
        print(
            "[grist] no review-<key>.grist.yaml present and no story file has a "
            "`### Review Findings` section to extract from. "
            "Either the review wrote zero findings (clean review — emit a stub manually) "
            "or the workflow did not append findings.",
            file=sys.stderr,
        )
        return 1

    story_path, story_key = found
    md = story_path.read_text(encoding="utf-8")
    findings = parse_findings_from_story(md)
    out_path = story_path.with_name(f"review-{story_key}.grist.yaml")
    out_path.write_text(emit_review_yaml(story_key, findings), encoding="utf-8")
    issues = validate(out_path)
    if issues:
        print(f"[grist] wrote {out_path.name} but it has issues:", file=sys.stderr)
        for i in issues:
            print(f"  - {i}", file=sys.stderr)
        return 1
    print(f"[grist] extracted {len(findings)} finding(s) from {story_path.name} → {out_path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
