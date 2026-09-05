#!/usr/bin/env python3
"""grist-diff — orient on a PR / diff range without reading the diff.

Emits ONE compact table (path, +, -, hunks, class) plus a read plan, so the
reviewing agent never runs `git diff` on the whole PR just to decide what
matters. Generated / vendored / lockfile / snapshot / minified / binary files
are classified and excluded from the review set; their list is emitted in
the shape the review.grist.yaml `skipped:` key expects.

Usage:
    grist-diff.py [<range>] [--pr N] [--threshold 200] [--json] [--ignore GLOB]...

    <range>     git revision range, e.g. origin/main...HEAD (default). Three
                dots = merge-base diff, which is what a PR review wants.
    --pr N      resolve base/head via `gh pr view N` (GitHub) — overrides <range>.
    --mr N      resolve via `glab mr view N` (GitLab) — overrides <range>.
    --threshold lines of reviewable diff under which a single
                `git diff -U3 <range> -- <paths>` is cheaper than per-file reads.
    --ignore    extra glob(s) to exclude (repeatable). Also read one-per-line
                from .grist/review-ignore if present.
    --json      machine-readable output.

Exit 0 on success, 1 on git failure. Stdlib only. Python >= 3.7.
"""

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys

DEFAULT_RANGE = "origin/main...HEAD"
DEFAULT_THRESHOLD = 200
IGNORE_FILE = os.path.join(".grist", "review-ignore")

LOCKFILES = {
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock",
    "Cargo.lock", "poetry.lock", "Pipfile.lock", "uv.lock", "Gemfile.lock",
    "composer.lock", "go.sum", "mix.lock", "pubspec.lock", "flake.lock",
    "packages.lock.json", "Podfile.lock", "gradle.lockfile",
}

# (class, glob) — first match wins. Globs match the full repo-relative path.
BUILTIN_RULES = [
    ("vendor", "vendor/*"), ("vendor", "*/vendor/*"),
    ("vendor", "node_modules/*"), ("vendor", "*/node_modules/*"),
    ("vendor", "third_party/*"), ("vendor", "*/third_party/*"),
    ("snapshot", "*/__snapshots__/*"), ("snapshot", "__snapshots__/*"),
    ("snapshot", "*.snap"), ("snapshot", "*.ambr"),
    ("minified", "*.min.js"), ("minified", "*.min.css"), ("minified", "*.bundle.js"),
    ("minified", "*.map"),
    ("generated", "dist/*"), ("generated", "*/dist/*"),
    ("generated", "build/*"), ("generated", "*/build/*"),
    ("generated", "generated/*"), ("generated", "*/generated/*"),
    ("generated", "*.generated.*"), ("generated", "*_pb2.py"), ("generated", "*_pb2_grpc.py"),
    ("generated", "*.pb.go"), ("generated", "*.pb.cc"), ("generated", "*.pb.h"),
    ("generated", "*.g.dart"), ("generated", "*.freezed.dart"), ("generated", "*.gr.dart"),
    ("generated", "*.g.cs"), ("generated", "*.designer.cs"),
    ("generated", "*/__generated__/*"), ("generated", "*.graphql.ts"),
    ("generated", "schema.graphql"), ("generated", "*/openapi.json"), ("generated", "*/swagger.json"),
]


def die(msg, code=1):
    sys.stderr.write("grist-diff: %s\n" % msg)
    sys.exit(code)


def run(cmd, stdin=None, check=True):
    try:
        p = subprocess.run(cmd, input=stdin, capture_output=True, text=True)
    except OSError as e:
        die("cannot run %s: %s" % (cmd[0], e))
    if check and p.returncode != 0:
        die((p.stderr or p.stdout or "command failed").strip().splitlines()[-1])
    return p.stdout


def resolve_pr(number, tool):
    """Return (range, meta) using gh / glab; falls back with a warning."""
    if tool == "gh":
        out = run(["gh", "pr", "view", str(number), "--json",
                   "number,url,baseRefName,headRefName,headRefOid,additions,deletions"], check=False)
        try:
            d = json.loads(out)
        except ValueError:
            return None, None
        base = "origin/%s" % d.get("baseRefName", "main")
        head = d.get("headRefOid") or "origin/%s" % d.get("headRefName", "HEAD")
        return "%s...%s" % (base, head), {"pr": d.get("url"), "base": base, "head": head}
    if tool == "glab":
        out = run(["glab", "mr", "view", str(number), "--output", "json"], check=False)
        try:
            d = json.loads(out)
        except ValueError:
            return None, None
        base = "origin/%s" % d.get("target_branch", "main")
        head = d.get("sha") or "origin/%s" % d.get("source_branch", "HEAD")
        return "%s...%s" % (base, head), {"pr": d.get("web_url"), "base": base, "head": head}
    return None, None


def load_ignore_globs(extra):
    globs = list(extra or [])
    try:
        with open(IGNORE_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    globs.append(line)
    except OSError:
        pass
    return globs


def linguist_generated(paths):
    """Set of paths marked linguist-generated / linguist-vendored in .gitattributes."""
    if not paths:
        return set(), set()
    out = run(["git", "check-attr", "--stdin", "linguist-generated", "linguist-vendored"],
              stdin="\n".join(paths) + "\n", check=False)
    gen, ven = set(), set()
    for line in out.splitlines():
        # path: attr: value
        m = re.match(r"^(.*): (linguist-generated|linguist-vendored): (.*)$", line)
        if not m or m.group(3) in ("unspecified", "unset", "false"):
            continue
        (gen if m.group(2) == "linguist-generated" else ven).add(m.group(1))
    return gen, ven


def classify(path, binary, gen_attr, ven_attr, ignore_globs):
    base = os.path.basename(path)
    if binary:
        return "binary"
    if base in LOCKFILES:
        return "lockfile"
    if path in gen_attr:
        return "generated"
    if path in ven_attr:
        return "vendor"
    for g in ignore_globs:
        if fnmatch.fnmatch(path, g) or fnmatch.fnmatch(base, g):
            return "ignored"
    for cls, g in BUILTIN_RULES:
        if fnmatch.fnmatch(path, g):
            return cls
    return "code"


def numstat(rng):
    rows = []
    for line in run(["git", "diff", "--numstat", rng]).splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        add, dele, path = parts[0], parts[1], "\t".join(parts[2:])
        # renames: "old => new" or "{a => b}/x"
        if " => " in path:
            path = re.sub(r"\{[^}]* => ([^}]*)\}", r"\1", path)
            if " => " in path:
                path = path.split(" => ")[-1]
        binary = add == "-" or dele == "-"
        rows.append({
            "path": path,
            "add": 0 if binary else int(add),
            "del": 0 if binary else int(dele),
            "binary": binary,
        })
    return rows


def hunk_counts(rng):
    counts = {}
    current = None
    for line in run(["git", "diff", "-U0", "--no-color", rng]).splitlines():
        if line.startswith("diff --git "):
            m = re.match(r'^diff --git a/(.*?) b/(.*)$', line)
            current = m.group(2) if m else None
            if current is not None:
                counts.setdefault(current, 0)
        elif line.startswith("@@") and current is not None:
            counts[current] += 1
    return counts


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("range", nargs="?", default=None)
    ap.add_argument("--pr", type=int, help="GitHub PR number (uses gh)")
    ap.add_argument("--mr", type=int, help="GitLab MR number (uses glab)")
    ap.add_argument("--threshold", type=int, default=DEFAULT_THRESHOLD)
    ap.add_argument("--ignore", action="append", default=[], metavar="GLOB")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    meta = {}
    rng = args.range
    if args.pr is not None or args.mr is not None:
        tool = "gh" if args.pr is not None else "glab"
        resolved, meta = resolve_pr(args.pr if args.pr is not None else args.mr, tool)
        if resolved:
            rng = resolved
        else:
            sys.stderr.write("grist-diff: %s lookup failed; using range %s\n"
                             % (tool, rng or DEFAULT_RANGE))
            meta = {}
    rng = rng or DEFAULT_RANGE

    rows = numstat(rng)
    hunks = hunk_counts(rng)
    ignore_globs = load_ignore_globs(args.ignore)
    gen_attr, ven_attr = linguist_generated([r["path"] for r in rows])

    review, skipped = [], []
    for r in rows:
        r["hunks"] = hunks.get(r["path"], 0)
        r["class"] = classify(r["path"], r["binary"], gen_attr, ven_attr, ignore_globs)
        (review if r["class"] == "code" else skipped).append(r)

    review_lines = sum(r["add"] + r["del"] for r in review)
    skipped_lines = sum(r["add"] + r["del"] for r in skipped)
    review_paths = [r["path"] for r in review]
    if review_lines <= args.threshold and review_paths:
        plan = "git diff -U3 %s -- %s" % (rng, " ".join(review_paths))
        plan_kind = "single"
    elif review_paths:
        plan = "git diff -U3 %s -- <path>   (one file at a time, largest hunks first)" % rng
        plan_kind = "per-file"
    else:
        plan, plan_kind = "nothing reviewable", "none"

    result = {
        "range": rng,
        **{k: v for k, v in meta.items() if v},
        "threshold": args.threshold,
        "review": review,
        "skipped": skipped,
        "review_lines": review_lines,
        "skipped_lines": skipped_lines,
        "plan": plan,
        "plan_kind": plan_kind,
    }
    if args.json:
        json.dump(result, sys.stdout, indent=1)
        sys.stdout.write("\n")
        return

    width = max([len(r["path"]) for r in rows] + [4])
    print("range: %s" % rng)
    for k in ("pr", "base", "head"):
        if result.get(k):
            print("%s: %s" % (k, result[k]))
    print("%-*s %6s %6s %5s  %s" % (width, "path", "+", "-", "hunks", "class"))
    for r in sorted(rows, key=lambda r: (r["class"] != "code", -(r["add"] + r["del"]))):
        print("%-*s %6d %6d %5d  %s" % (width, r["path"], r["add"], r["del"], r["hunks"], r["class"]))
    print()
    print("review: %d files, %d lines (+%d/-%d)" % (
        len(review), review_lines, sum(r["add"] for r in review), sum(r["del"] for r in review)))
    print("skipped: %d files, %d lines" % (len(skipped), skipped_lines))
    if skipped:
        print("skipped_yaml:")
        for r in skipped:
            print("  - {path: %s, reason: %s}" % (r["path"], r["class"]))
    print("plan (%s, threshold %d): %s" % (plan_kind, args.threshold, plan))


if __name__ == "__main__":
    main()
