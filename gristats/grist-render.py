#!/usr/bin/env python3
"""grist-render — turn a review.grist.yaml into a PR review, with zero model tokens.

The reviewing agent emits YAML (schemas/review.grist.yaml). This script owns
every word of prose the humans see: the review body, inline comment text,
the approve/comment/request-changes decision, and the gh / glab calls.
Full sentences throughout (GRIST auto-clarity for client-facing text).

Usage:
    grist-render.py <review.grist.yaml> [--target md|github|gitlab]
                    [--repo owner/repo] [--number N] [--out DIR] [--post]

    --target md       print the Markdown body only (default; works anywhere).
    --target github   write <out>/<name>.github.json (a Pull Request Reviews
                      API payload: event + body + inline comments) and print the
                      `gh api` command that posts it. One call, one review.
    --target gitlab   write <out>/<name>.gitlab.sh: one `glab mr note` for the
                      body plus one discussion per inline finding (position
                      requires base/head shas in the YAML), and `glab mr approve`
                      for zone green.
    --post            actually run the gh / glab commands. Without it nothing
                      leaves the machine.

Zone mapping: green -> APPROVE, yellow -> COMMENT, red -> REQUEST_CHANGES.
Findings with class `dismiss` are counted but never posted.

Exit 0 on success, 1 on bad input. Stdlib only (PyYAML used if present).
"""

import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys

try:
    import yaml as _yaml
except ImportError:
    _yaml = None

HERE = os.path.dirname(os.path.abspath(__file__))

ZONE_EVENT = {"green": "APPROVE", "yellow": "COMMENT", "red": "REQUEST_CHANGES"}
ZONE_LABEL = {"green": "Approve", "yellow": "Comment", "red": "Request changes"}
SEVERITY_LABEL = {"crit": "critical", "high": "high", "med": "medium", "low": "low"}
CLASS_HEADING = {
    "patch": "Must fix",
    "decision-needed": "Needs a decision",
    "defer": "Deferred (not introduced by this change)",
}
CLASS_ORDER = ["patch", "decision-needed", "defer"]


def die(msg):
    sys.stderr.write("grist-render: %s\n" % msg)
    sys.exit(1)


# --- loading ---------------------------------------------------------------

def _load_lite():
    spec = importlib.util.spec_from_file_location("grist_get", os.path.join(HERE, "grist-get.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod._yaml_lite


def _flow_map(s):
    """Parse a raw `{k: v, k2: v2}` string (grist-get's lite parser keeps these raw)."""
    if not (isinstance(s, str) and s.startswith("{") and s.endswith("}")):
        return s
    out = {}
    for part in re.split(r",\s*(?=[A-Za-z_][\w-]*\s*:)", s[1:-1].strip()):
        if ":" not in part:
            continue
        k, v = part.split(":", 1)
        out[k.strip()] = v.strip().strip("'\"")
    return out


def _normalize(node):
    if isinstance(node, list):
        return [_normalize(_flow_map(x)) for x in node]
    if isinstance(node, dict):
        return {k: _normalize(_flow_map(v)) for k, v in node.items()}
    return node


def load(path):
    try:
        with open(path) as f:
            text = f.read()
    except OSError as e:
        die("cannot read %s: %s" % (path, e))
    data = None
    if _yaml is not None:
        try:
            data = _yaml.safe_load(text)
        except Exception:
            data = None
    if not isinstance(data, dict):
        data = _normalize(_load_lite()(text))
    if not isinstance(data, dict) or "review" not in data:
        die("%s is not a review.grist.yaml (missing top-level `review:`)" % path)
    return data


# --- prose ----------------------------------------------------------------

def sentence(s):
    s = str(s or "").strip()
    if not s:
        return ""
    first = s.split(" ", 1)[0]
    if re.match(r"^[a-z]+(?:-[a-z]+)*$", first):  # plain word only — never touch paths, ids, code
        s = s[0].upper() + s[1:]
    if s[-1] not in ".!?":
        s += "."
    return s


def split_loc(loc):
    """'path:line' -> (path, line|None). Handles 'path:12-18' by taking 12."""
    if not loc or not isinstance(loc, str):
        return None, None
    m = re.match(r"^(.*?):(\d+)(?:-\d+)?$", loc.strip())
    if not m:
        return loc.strip(), None
    return m.group(1), int(m.group(2))


def finding_body(f):
    parts = [sentence(f.get("title"))]
    detail = sentence(f.get("detail"))
    if detail and detail != parts[0]:
        parts.append(detail)
    if f.get("fix"):
        parts.append("Suggested fix: " + sentence(f["fix"]))
    if f.get("ac_ref"):
        parts.append("This violates acceptance criterion %s." % f["ac_ref"])
    sev = SEVERITY_LABEL.get(str(f.get("severity", "")).lower())
    tag = "**%s**" % f.get("id", "f?")
    if sev:
        tag += " · %s" % sev
    if f.get("class") == "decision-needed":
        tag += " · needs a decision"
    return tag + " — " + " ".join(p for p in parts if p)


def render_md(d):
    zone = str(d.get("zone", "yellow")).lower()
    findings = [f for f in (d.get("findings") or []) if isinstance(f, dict)]
    live = [f for f in findings if f.get("class") != "dismiss"]
    lines = []
    lines.append("## Review: %s" % sentence(d.get("verdict") or "no verdict recorded"))
    lines.append("")
    meta = []
    if d.get("pr"):
        meta.append("PR %s" % d["pr"])
    if d.get("base") and d.get("head"):
        meta.append("diff `%s..%s`" % (str(d["base"])[:12], str(d["head"])[:12]))
    elif d.get("diff_source"):
        meta.append("diff `%s`" % d["diff_source"])
    meta.append("decision: **%s**" % ZONE_LABEL.get(zone, zone))
    lines.append("_" + " · ".join(meta) + "_")
    lines.append("")

    for cls in CLASS_ORDER:
        group = [f for f in live if f.get("class") == cls]
        if not group:
            continue
        lines.append("### %s" % CLASS_HEADING[cls])
        for f in group:
            loc = f.get("loc")
            prefix = ("`%s` — " % loc) if loc else ""
            lines.append("- %s%s" % (prefix, finding_body(f)))
        lines.append("")

    verified = [v for v in (d.get("verified") or []) if isinstance(v, dict)]
    if verified:
        lines.append("### Verified")
        for v in verified:
            how = sentence(v.get("how"))
            lines.append("- %s%s" % (sentence(v.get("what")), (" " + how) if how else ""))
        lines.append("")

    handoffs = [h for h in (d.get("handoffs") or []) if isinstance(h, dict)]
    if handoffs:
        lines.append("### Hand-offs")
        for h in handoffs:
            lines.append("- [ ] **%s**: %s" % (h.get("to", "owner"), sentence(h.get("what"))))
        lines.append("")

    resolutions = [r for r in (d.get("resolutions") or []) if isinstance(r, dict)]
    if resolutions:
        lines.append("### Previous findings")
        for r in resolutions:
            note = sentence(r.get("note"))
            extra = (" in `%s`" % str(r["resolved_in"])[:12]) if r.get("resolved_in") else ""
            lines.append("- %s: %s%s%s" % (r.get("finding"), r.get("status", "pending"), extra,
                                            (". " + note) if note else ""))
        lines.append("")

    skipped = [s for s in (d.get("skipped") or []) if isinstance(s, dict)]
    if skipped:
        lines.append("<details><summary>Skipped: %d file%s not reviewed (generated or vendored)</summary>"
                     % (len(skipped), "" if len(skipped) == 1 else "s"))
        lines.append("")
        for s in skipped:
            lines.append("- `%s` — %s" % (s.get("path"), s.get("reason", "skipped")))
        lines.append("")
        lines.append("</details>")
        lines.append("")

    counts = d.get("counts")
    if isinstance(counts, dict):
        parts = []
        for k, label in (("patch", "to fix"), ("decision_needed", "need a decision"),
                         ("defer", "deferred"), ("dismissed", "dismissed")):
            v = counts.get(k)
            if v not in (None, 0, "0"):
                parts.append("%s %s" % (v, label))
        if parts:
            lines.append("_%s._" % ", ".join(parts))
            lines.append("")
    lines.append("<sub>Rendered by grist-render from review#%s. Findings are addressable as review#%s#f&lt;n&gt;.</sub>"
                 % (d.get("review"), d.get("review")))
    return "\n".join(lines).rstrip() + "\n"


# --- targets ----------------------------------------------------------------

def parse_pr(d, repo_opt, number_opt):
    """Return (owner/repo, number) from --repo/--number or the YAML `pr:` field."""
    repo, number = repo_opt, number_opt
    pr = str(d.get("pr") or "")
    m = re.search(r"github\.com/([^/]+/[^/]+)/pull/(\d+)", pr) or re.match(r"^([^/\s#!]+/[^/\s#!]+)#(\d+)$", pr)
    if m:
        repo = repo or m.group(1)
        number = number or int(m.group(2))
    m = re.search(r"/merge_requests/(\d+)", pr) or re.match(r"^!(\d+)$", pr)
    if m and not number:
        number = int(m.group(1))
    if not number:
        m = re.match(r"^(?:pr|mr)-(\d+)$", str(d.get("review") or ""))
        if m:
            number = int(m.group(1))
    return repo, number


def inline_comments(d):
    out = []
    for f in d.get("findings") or []:
        if not isinstance(f, dict) or f.get("class") == "dismiss":
            continue
        path, line = split_loc(f.get("loc"))
        if not path or not line:
            continue
        out.append({"path": path, "line": line, "side": "RIGHT", "body": finding_body(f)})
    return out


def target_github(d, args, body, out_dir, name):
    repo, number = parse_pr(d, args.repo, args.number)
    if not number:
        die("cannot determine PR number — set `pr: owner/repo#n` in the YAML or pass --number")
    payload = {"event": ZONE_EVENT.get(str(d.get("zone", "yellow")).lower(), "COMMENT"),
               "body": body, "comments": inline_comments(d)}
    path = os.path.join(out_dir, name + ".github.json")
    with open(path, "w") as f:
        json.dump(payload, f, indent=1)
        f.write("\n")
    endpoint = "repos/%s/pulls/%d/reviews" % (repo or "{owner}/{repo}", number)
    cmd = ["gh", "api", "--method", "POST", endpoint, "--input", path]
    if not repo:
        cmd = ["gh", "api", "--method", "POST", "repos/{owner}/{repo}/pulls/%d/reviews" % number, "--input", path]
    print("payload: %s (%d inline comment%s, event %s)"
          % (path, len(payload["comments"]), "" if len(payload["comments"]) == 1 else "s", payload["event"]))
    print("command: " + " ".join(cmd))
    return [cmd]


def target_gitlab(d, args, body, out_dir, name):
    _, number = parse_pr(d, args.repo, args.number)
    if not number:
        die("cannot determine MR iid — set `pr: !n` or a merge_requests URL in the YAML, or pass --number")
    base, head = str(d.get("base") or ""), str(d.get("head") or "")
    shas_ok = bool(re.match(r"^[0-9a-f]{7,40}$", base) and re.match(r"^[0-9a-f]{7,40}$", head))
    body_path = os.path.join(out_dir, name + ".gitlab.md")
    with open(body_path, "w") as f:
        f.write(body)
    cmds = [["glab", "mr", "note", str(number), "-m", body]]
    if shas_ok:
        for c in inline_comments(d):
            cmds.append([
                "glab", "api", "--method", "POST",
                "projects/:id/merge_requests/%d/discussions" % number,
                "-f", "body=" + c["body"],
                "-f", "position[position_type]=text",
                "-f", "position[base_sha]=" + base,
                "-f", "position[start_sha]=" + base,
                "-f", "position[head_sha]=" + head,
                "-f", "position[new_path]=" + c["path"],
                "-f", "position[new_line]=%d" % c["line"],
            ])
    else:
        print("note: base/head are not commit shas — inline discussions skipped, body note only")
    if str(d.get("zone", "")).lower() == "green":
        cmds.append(["glab", "mr", "approve", str(number)])
    script = os.path.join(out_dir, name + ".gitlab.sh")
    with open(script, "w") as f:
        f.write("#!/usr/bin/env bash\nset -euo pipefail\n")
        for c in cmds:
            if c[:3] == ["glab", "mr", "note"]:
                f.write('glab mr note %d -m "$(cat %s)"\n' % (number, _shquote(body_path)))
                continue
            f.write(" ".join(_shquote(x) for x in c) + "\n")
    os.chmod(script, 0o755)
    print("script: %s (%d command%s)" % (script, len(cmds), "" if len(cmds) == 1 else "s"))
    return cmds


def _shquote(s):
    if re.match(r"^[\w@%+=:,./-]+$", s):
        return s
    return "'" + s.replace("'", "'\"'\"'") + "'"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--target", choices=["md", "github", "gitlab"], default="md")
    ap.add_argument("--repo", help="owner/repo (GitHub) — overrides the YAML pr: field")
    ap.add_argument("--number", type=int, help="PR / MR number — overrides the YAML pr: field")
    ap.add_argument("--out", help="directory for payload files (default: next to the YAML)")
    ap.add_argument("--post", action="store_true", help="run the gh/glab commands")
    args = ap.parse_args()

    d = load(args.file)
    body = render_md(d)
    if args.target == "md":
        sys.stdout.write(body)
        return

    out_dir = args.out or os.path.dirname(os.path.abspath(args.file))
    os.makedirs(out_dir, exist_ok=True)
    name = re.sub(r"\.grist\.ya?ml$", "", os.path.basename(args.file))
    cmds = target_github(d, args, body, out_dir, name) if args.target == "github" \
        else target_gitlab(d, args, body, out_dir, name)

    if not args.post:
        print("dry run — re-run with --post to publish")
        return
    for c in cmds:
        p = subprocess.run(c)
        if p.returncode != 0:
            die("command failed (%d): %s" % (p.returncode, " ".join(c)))
    print("posted.")


if __name__ == "__main__":
    main()
