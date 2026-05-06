#!/usr/bin/env python3
"""gristats — measure GRIST token impact.

Two layers:

1. **Artifact size comparison** (offline, deterministic) — compares prose
   .md artifacts to their .grist.yaml equivalents using bytes + token
   estimates (tiktoken if available, char/4 heuristic otherwise).

2. **Claude Code session tracking** (real input/output tokens) — parses
   ~/.claude/projects/<hash>/<session>.jsonl transcripts, groups token
   usage by GRIST phase (design / iterate / ship), reports cache hit rate.

Subcommands:
    gristats compare <a> <b>          pairwise file comparison
    gristats project <dir>            walk dir for .md ↔ .grist.yaml pairs
    gristats sessions [--days N]      parse Claude Code transcripts
    gristats summary [--days N]       combined dashboard
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

# --- Token estimation -------------------------------------------------------

try:
    import tiktoken
    _ENC = tiktoken.get_encoding("cl100k_base")
    TOKENIZER = "tiktoken-cl100k_base"

    def estimate_tokens(s: str) -> int:
        return len(_ENC.encode(s))
except Exception:
    TOKENIZER = "chars/4 heuristic (install tiktoken for accuracy)"

    def estimate_tokens(s: str) -> int:
        return max(1, len(s) // 4)


# --- Layer 1: artifact size comparison --------------------------------------

@dataclass
class FileStats:
    path: Path
    bytes_: int
    tokens: int

    @classmethod
    def of(cls, path: Path) -> "FileStats":
        text = path.read_text(encoding="utf-8", errors="replace")
        return cls(path=path, bytes_=len(text.encode("utf-8")), tokens=estimate_tokens(text))


def pct_drop(a: int, b: int) -> str:
    if a == 0:
        return "—"
    return f"{(a - b) / a * 100:5.1f}%"


def cmd_compare(args: argparse.Namespace) -> int:
    a = FileStats.of(Path(args.a))
    b = FileStats.of(Path(args.b))
    print(f"tokenizer: {TOKENIZER}\n")
    print(f"{'file':<50} {'bytes':>10} {'tokens':>10}")
    print("-" * 72)
    print(f"{str(a.path):<50} {a.bytes_:>10} {a.tokens:>10}")
    print(f"{str(b.path):<50} {b.bytes_:>10} {b.tokens:>10}")
    print("-" * 72)
    print(f"{'reduction':<50} {pct_drop(a.bytes_, b.bytes_):>10} {pct_drop(a.tokens, b.tokens):>10}")
    return 0


# Pairs we know how to match. Each entry = (prose_stem, grist_stem) — case-insensitive,
# `.tight.` and similar variants on the grist side accepted.
PAIR_STEMS = [
    ("prd",          "prd"),
    ("architecture", "architecture"),
    ("proposal",     "change"),
    ("design",       "change"),
    ("tasks",        "change"),
    ("spec",         "spec"),
]
STORY_PROSE_RE = re.compile(r"^(story-[\w\-\.]+)\.md$", re.IGNORECASE)
STORY_YAML_RE = re.compile(r"^(story-[\w\-\.]+?)(?:\.[\w\-]+)?\.grist\.yaml$", re.IGNORECASE)


def _match_grist(filenames: set[str], stem: str) -> str | None:
    """Find a file matching <stem>(.<variant>)?.grist.yaml, case-insensitive."""
    target_lower = stem.lower()
    pat = re.compile(rf"^{re.escape(target_lower)}(?:\.[\w\-]+)?\.grist\.yaml$", re.IGNORECASE)
    for f in filenames:
        if pat.match(f):
            return f
    return None


def _match_prose(filenames: set[str], stem: str) -> str | None:
    """Find <stem>.md, case-insensitive."""
    target_lower = stem.lower() + ".md"
    for f in filenames:
        if f.lower() == target_lower:
            return f
    return None


def find_pairs(root: Path) -> list[tuple[Path, Path]]:
    """Return list of (prose_path, grist_path) where both exist in same dir."""
    pairs: list[tuple[Path, Path]] = []
    seen: set[tuple[str, str]] = set()
    for dirpath, _, filenames in os.walk(root):
        files = set(filenames)
        d = Path(dirpath)
        for prose_stem, grist_stem in PAIR_STEMS:
            prose_name = _match_prose(files, prose_stem)
            grist_name = _match_grist(files, grist_stem)
            if prose_name and grist_name:
                key = (str(d / prose_name), str(d / grist_name))
                if key in seen:
                    continue
                seen.add(key)
                pairs.append((d / prose_name, d / grist_name))
        # story-S<n>.<m>.md ↔ story-S<n>.<m>(.<variant>)?.grist.yaml
        story_yamls: dict[str, str] = {}
        for f in filenames:
            m = STORY_YAML_RE.match(f)
            if m:
                story_yamls[m.group(1).lower()] = f
        for f in filenames:
            m = STORY_PROSE_RE.match(f)
            if m and m.group(1).lower() in story_yamls:
                pairs.append((d / f, d / story_yamls[m.group(1).lower()]))
    return pairs


def cmd_project(args: argparse.Namespace) -> int:
    root = Path(args.dir).resolve()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 1

    pairs = find_pairs(root)
    if not pairs:
        print(f"no .md ↔ .grist.yaml pairs found under {root}")
        print("(GRIST artifacts may not be present yet, or names don't match known patterns)")
        return 0

    print(f"tokenizer: {TOKENIZER}")
    print(f"scanning:  {root}")
    print(f"found:     {len(pairs)} prose ↔ grist pair(s)\n")
    print(f"{'pair':<60} {'prose tok':>10} {'grist tok':>10} {'cut':>7}")
    print("-" * 90)

    total_prose = total_grist = 0
    for prose, grist in pairs:
        ps = FileStats.of(prose)
        gs = FileStats.of(grist)
        total_prose += ps.tokens
        total_grist += gs.tokens
        rel = str(prose.relative_to(root)) + "  →  " + grist.name
        if len(rel) > 58:
            rel = "…" + rel[-57:]
        print(f"{rel:<60} {ps.tokens:>10} {gs.tokens:>10} {pct_drop(ps.tokens, gs.tokens):>7}")

    print("-" * 90)
    print(f"{'TOTAL':<60} {total_prose:>10} {total_grist:>10} {pct_drop(total_prose, total_grist):>7}")
    if total_prose > 0:
        ratio = total_prose / max(total_grist, 1)
        print(f"\noverall ratio: {ratio:.1f}× (prose / grist)")
    return 0


# --- Layer 2: Claude Code session parser ------------------------------------

CLAUDE_PROJECTS_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home() / ".claude"))) / "projects"

# Phase-detection patterns. Order matters — first match wins per turn.
PHASE_PATTERNS = [
    ("ship",     re.compile(r"(?:^|\s)/grist\s+ship(?:\s|$)|/grist-ship\b", re.IGNORECASE)),
    ("design",   re.compile(r"(?:^|\s)/grist\s+design(?:\s|$)|/grist-design\b|bmad-create-(?:prd|architecture|story)\b", re.IGNORECASE)),
    ("iterate",  re.compile(r"(?:^|\s)/grist\s+iterate(?:\s|$)|/grist-iterate\b|/openspec:proposal\b|/opsx:propose\b|/opsx:new\b|/opsx:continue\b|/opsx:ff\b", re.IGNORECASE)),
    ("ship",     re.compile(r"bmad-dev-story\b|bmad-code-review\b|/opsx:apply\b|/opsx:verify\b", re.IGNORECASE)),
    ("caveman",  re.compile(r"(?:^|\s)/caveman(?:\s|$)|/caveman-(?:commit|review|compress)\b", re.IGNORECASE)),
    ("off",      re.compile(r"(?:^|\s)/grist\s+off(?:\s|$)|stop grist\b|normal mode\b", re.IGNORECASE)),
]


@dataclass
class PhaseStats:
    turns: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read: int = 0
    cache_creation: int = 0


@dataclass
class SessionSummary:
    file: Path
    project: str
    started: datetime | None = None
    ended: datetime | None = None
    by_phase: dict[str, PhaseStats] = field(default_factory=lambda: defaultdict(PhaseStats))

    @property
    def total_input(self) -> int:
        return sum(p.input_tokens for p in self.by_phase.values())

    @property
    def total_output(self) -> int:
        return sum(p.output_tokens for p in self.by_phase.values())

    @property
    def total_cache_read(self) -> int:
        return sum(p.cache_read for p in self.by_phase.values())

    @property
    def total_cache_creation(self) -> int:
        return sum(p.cache_creation for p in self.by_phase.values())


def detect_phase(text: str) -> str | None:
    for label, pat in PHASE_PATTERNS:
        if pat.search(text):
            return label
    return None


def iter_session_turns(jsonl_path: Path):
    """Yield parsed turn dicts. Skips malformed lines."""
    with jsonl_path.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def parse_session(jsonl_path: Path) -> SessionSummary:
    project = jsonl_path.parent.name.replace("-", "/")
    summary = SessionSummary(file=jsonl_path, project=project)
    current_phase = "unlabeled"

    for turn in iter_session_turns(jsonl_path):
        ts = turn.get("timestamp")
        if ts:
            try:
                dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                if summary.started is None or dt < summary.started:
                    summary.started = dt
                if summary.ended is None or dt > summary.ended:
                    summary.ended = dt
            except (ValueError, TypeError):
                pass

        ttype = turn.get("type")
        msg = turn.get("message")
        if not isinstance(msg, dict):
            continue

        # Phase detection on user text turns
        if ttype == "user":
            content = msg.get("content")
            text = ""
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                for blk in content:
                    if isinstance(blk, dict) and blk.get("type") == "text":
                        text += blk.get("text", "") + "\n"
            if text:
                phase = detect_phase(text)
                if phase == "off":
                    current_phase = "unlabeled"
                elif phase:
                    current_phase = phase

        # Token accumulation on assistant turns with usage
        if ttype == "assistant":
            usage = msg.get("usage")
            if not isinstance(usage, dict):
                continue
            ps = summary.by_phase[current_phase]
            ps.turns += 1
            ps.input_tokens += int(usage.get("input_tokens", 0) or 0)
            ps.output_tokens += int(usage.get("output_tokens", 0) or 0)
            ps.cache_read += int(usage.get("cache_read_input_tokens", 0) or 0)
            ps.cache_creation += int(usage.get("cache_creation_input_tokens", 0) or 0)

    return summary


def discover_sessions(days: int | None, project_filter: str | None) -> list[Path]:
    if not CLAUDE_PROJECTS_DIR.is_dir():
        return []
    cutoff = None
    if days is not None:
        cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).timestamp()
    out: list[Path] = []
    for proj in sorted(CLAUDE_PROJECTS_DIR.iterdir()):
        if not proj.is_dir():
            continue
        if project_filter and project_filter not in proj.name:
            continue
        for jsonl in proj.glob("*.jsonl"):
            try:
                if cutoff and jsonl.stat().st_mtime < cutoff:
                    continue
            except OSError:
                continue
            out.append(jsonl)
    return out


def fmt_tokens(n: int) -> str:
    if n >= 1_000_000:
        return f"{n / 1_000_000:.2f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}k"
    return str(n)


def cmd_sessions(args: argparse.Namespace) -> int:
    sessions_paths = discover_sessions(args.days, args.project)
    if not sessions_paths:
        scope = f"last {args.days}d" if args.days else "all time"
        print(f"no Claude Code sessions found ({scope}, project filter: {args.project or 'none'})")
        print(f"  expected at: {CLAUDE_PROJECTS_DIR}")
        return 0

    summaries = [parse_session(p) for p in sessions_paths]

    # Aggregate
    total_by_phase: dict[str, PhaseStats] = defaultdict(PhaseStats)
    for s in summaries:
        for phase, ps in s.by_phase.items():
            t = total_by_phase[phase]
            t.turns += ps.turns
            t.input_tokens += ps.input_tokens
            t.output_tokens += ps.output_tokens
            t.cache_read += ps.cache_read
            t.cache_creation += ps.cache_creation

    grand_input = sum(p.input_tokens for p in total_by_phase.values())
    grand_output = sum(p.output_tokens for p in total_by_phase.values())
    grand_cache_read = sum(p.cache_read for p in total_by_phase.values())
    grand_cache_creation = sum(p.cache_creation for p in total_by_phase.values())
    cache_total_input = grand_cache_read + grand_cache_creation
    cache_hit_rate = grand_cache_read / max(cache_total_input, 1) * 100

    scope = f"last {args.days}d" if args.days else "all time"
    print(f"Claude Code sessions ({scope})")
    print(f"  sessions: {len(summaries)}")
    print(f"  turns:    {sum(p.turns for p in total_by_phase.values())}")
    print(f"  input:    {fmt_tokens(grand_input)}")
    print(f"  output:   {fmt_tokens(grand_output)}")
    print(f"  cache:    {fmt_tokens(grand_cache_read)} read / {fmt_tokens(grand_cache_creation)} new — {cache_hit_rate:.0f}% hit rate")
    print()

    print(f"{'phase':<14}{'turns':>8}{'input':>12}{'cache-read':>14}{'cache-new':>12}{'output':>10}")
    print("-" * 70)
    phase_order = ["design", "iterate", "ship", "caveman", "unlabeled"]
    seen = set()
    for phase in phase_order + sorted(set(total_by_phase) - set(phase_order)):
        if phase not in total_by_phase or phase in seen:
            continue
        seen.add(phase)
        ps = total_by_phase[phase]
        print(
            f"{phase:<14}{ps.turns:>8}"
            f"{fmt_tokens(ps.input_tokens):>12}"
            f"{fmt_tokens(ps.cache_read):>14}"
            f"{fmt_tokens(ps.cache_creation):>12}"
            f"{fmt_tokens(ps.output_tokens):>10}"
        )

    if args.verbose:
        print("\nper-session:")
        for s in sorted(summaries, key=lambda x: x.ended or datetime.min.replace(tzinfo=timezone.utc), reverse=True):
            label = s.ended.strftime("%Y-%m-%d %H:%M") if s.ended else "?"
            phases = ",".join(f"{ph}:{ps.turns}t/{fmt_tokens(ps.input_tokens)}in" for ph, ps in s.by_phase.items())
            print(f"  {label}  {s.project[:40]:<40}  {phases}")

    return 0


def cmd_summary(args: argparse.Namespace) -> int:
    print("=" * 72)
    print("GRIST stats summary")
    print("=" * 72)
    print()
    if args.dir:
        print(">>> artifact comparison")
        cmd_project(argparse.Namespace(dir=args.dir))
        print()
    print(">>> session token usage")
    cmd_sessions(argparse.Namespace(days=args.days, project=args.project, verbose=False))
    return 0


# --- Entry ------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="gristats", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_cmp = sub.add_parser("compare", help="compare two files (bytes + tokens)")
    p_cmp.add_argument("a", help="first file (typically .md)")
    p_cmp.add_argument("b", help="second file (typically .grist.yaml)")
    p_cmp.set_defaults(func=cmd_compare)

    p_proj = sub.add_parser("project", help="walk dir for .md ↔ .grist.yaml pairs")
    p_proj.add_argument("dir", help="project root or planning artifacts dir")
    p_proj.set_defaults(func=cmd_project)

    p_sess = sub.add_parser("sessions", help="parse Claude Code transcripts by phase")
    p_sess.add_argument("--days", type=int, default=None, help="restrict to last N days (default: all)")
    p_sess.add_argument("--project", help="substring filter on project hash dir name")
    p_sess.add_argument("--verbose", "-v", action="store_true", help="per-session breakdown")
    p_sess.set_defaults(func=cmd_sessions)

    p_sum = sub.add_parser("summary", help="combined dashboard")
    p_sum.add_argument("--dir", help="project root for artifact pairs (optional)")
    p_sum.add_argument("--days", type=int, default=7, help="session window (default: 7)")
    p_sum.add_argument("--project", help="substring filter on project hash dir name")
    p_sum.set_defaults(func=cmd_summary)

    return ap


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv[1:])
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
