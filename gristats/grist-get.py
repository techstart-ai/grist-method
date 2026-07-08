#!/usr/bin/env python3
"""grist-get: resolve a GRIST reference to just the matching YAML node.

Usage:
    grist-get.py <ref> [--dir <search-dir>]
    grist-get.py --list <type>[#<slug>] [--dir <search-dir>]

Ref grammar:
    <type>[#<slug>]#<id-path>

    type     one of: prd, arch (alias: architecture), story, spec, change, review
    slug     optional artifact slug; matched against the artifact's top-level
             type key (e.g. `prd: auth-v2`)
    id-path  an id found at any depth (`E1`, `d2`, `r1`), a dotted path
             (`E1.S1.1`), or a top-level key (`goal`)

Examples:
    grist-get.py prd#E1
    grist-get.py prd#auth-v2#E1
    grist-get.py prd#goal
    grist-get.py arch#d2
    grist-get.py story#S1.1
    grist-get.py spec#auth#r1
    grist-get.py --list prd

Zero required dependencies: uses PyYAML when importable, otherwise falls back
to a minimal built-in parser covering the GRIST YAML subset (top-level scalar
keys, block lists of dicts with `id:` fields, flow lists `[a, b]`, block lists
of scalars). It is NOT a general YAML parser.

Output: one header line `# <file>:<line>` followed by the raw source lines of
the matching node (dedented). Exits 1 with a one-line stderr message when the
ref is not found or ambiguous.
"""

import argparse
import os
import re
import sys

try:
    import yaml as _yaml  # optional; not required
except ImportError:
    _yaml = None

# type -> (filename prefixes, top-level slug keys)
TYPES = {
    "prd": (["prd"], ["prd"]),
    "arch": (["arch"], ["arch", "architecture"]),
    "architecture": (["arch"], ["arch", "architecture"]),
    "story": (["story"], ["story"]),
    "spec": (["spec"], ["spec"]),
    "change": (["change"], ["change"]),
    "review": (["review"], ["review"]),
}

SUFFIX = ".grist.yaml"
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv"}
TITLE_KEYS = ("title", "name", "criterion", "test", "do", "decision", "risk",
              "contract", "goal", "why")


def die(msg):
    print("grist-get: " + msg, file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# minimal YAML-subset parser (fallback when PyYAML is unavailable)
# ---------------------------------------------------------------------------

def _unquote(s):
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        return s[1:-1]
    return s


def _parse_scalar(s):
    s = s.strip()
    if s.startswith("[") and s.endswith("]"):
        inner = s[1:-1].strip()
        if not inner:
            return []
        return [_unquote(p) for p in inner.split(",")]
    if s.startswith("{") and s.endswith("}"):  # flow map: keep raw
        return s
    return _unquote(s)


def _split_kv(content):
    """Split 'key: value' or 'key:' -> (key, rest) or None."""
    m = re.match(r"^([A-Za-z_][\w.-]*):(\s+.*)?$", content)
    if not m:
        return None
    return m.group(1), (m.group(2) or "").strip()


def _yaml_lite(text):
    """Parse the GRIST YAML subset into dicts/lists/strings."""
    rows = []  # (indent, content)
    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        rows.append((len(raw) - len(raw.lstrip(" ")), raw.strip()))

    def parse(i, indent):
        if i >= len(rows):
            return None, i
        if rows[i][1].startswith("- ") or rows[i][1] == "-":
            return parse_list(i, rows[i][0])
        return parse_map(i, indent)

    def parse_map(i, indent):
        out = {}
        while i < len(rows) and rows[i][0] == indent and not rows[i][1].startswith("-"):
            kv = _split_kv(rows[i][1])
            if kv is None:  # unrecognized line; skip
                i += 1
                continue
            key, rest = kv
            i += 1
            if rest:
                out[key] = _parse_scalar(rest)
            elif i < len(rows) and rows[i][0] > indent:
                out[key], i = parse(i, rows[i][0])
            else:
                out[key] = None
        return out, i

    def parse_list(i, indent):
        out = []
        while i < len(rows) and rows[i][0] == indent and rows[i][1].startswith("-"):
            content = rows[i][1][1:].strip()
            if not content:  # bare '-' with nested block
                i += 1
                if i < len(rows) and rows[i][0] > indent:
                    item, i = parse(i, rows[i][0])
                    out.append(item)
                continue
            kv = _split_kv(content)
            if kv is None:  # scalar item
                out.append(_parse_scalar(content))
                i += 1
                continue
            # dict item: inline first pair, further keys at indent+2 (aligned)
            item = {}
            key, rest = kv
            child_indent = indent + 2
            i += 1
            if rest:
                item[key] = _parse_scalar(rest)
            elif i < len(rows) and rows[i][0] > child_indent:
                item[key], i = parse(i, rows[i][0])
            else:
                item[key] = None
            while i < len(rows) and rows[i][0] == child_indent and not rows[i][1].startswith("- "):
                sub, i2 = parse_map(i, child_indent)
                if i2 == i:
                    break
                item.update(sub)
                i = i2
            out.append(item)
        return out, i

    data, _ = parse(0, 0)
    return data if isinstance(data, dict) else {}


def load_data(text):
    if _yaml is not None:
        try:
            data = _yaml.safe_load(text)
            return data if isinstance(data, dict) else {}
        except Exception:
            pass  # malformed for strict YAML; fall back
    return _yaml_lite(text)


# ---------------------------------------------------------------------------
# raw-source line scanner (locates nodes and returns source slices)
# ---------------------------------------------------------------------------

def _indent(line):
    return len(line) - len(line.lstrip(" "))


def _is_code(line):
    s = line.strip()
    return bool(s) and not s.startswith("#")


def _block_end(lines, start, indent):
    """First line index after `start` whose indent <= indent (exclusive end)."""
    end = start + 1
    last = start
    while end < len(lines):
        if _is_code(lines[end]):
            if _indent(lines[end]) <= indent:
                break
            last = end
        end += 1
    return last + 1


_ID_RE = re.compile(r"^(\s*)(-\s+)?id:\s*(.+?)\s*$")


def find_id_nodes(lines, target, lo=0, hi=None):
    """Find list items whose `id:` equals target within lines[lo:hi].

    Returns list of (start, end) 0-based, end exclusive."""
    hi = len(lines) if hi is None else hi
    hits = []
    for k in range(lo, hi):
        m = _ID_RE.match(lines[k])
        if not m or _unquote(m.group(3)) != target:
            continue
        if m.group(2):  # `- id: X` — the item starts here
            start, dash_indent = k, len(m.group(1))
        else:  # id on a later line of the item; walk up to the dash line
            start, dash_indent = None, None
            for j in range(k - 1, lo - 1, -1):
                if not _is_code(lines[j]):
                    continue
                ind = _indent(lines[j])
                if lines[j].lstrip().startswith("- ") and ind < _indent(lines[k]):
                    start, dash_indent = j, ind
                    break
                if ind < _indent(lines[k]):
                    break
            if start is None:
                continue
        hits.append((start, min(_block_end(lines, start, dash_indent), hi)))
    return hits


def find_top_key(lines, key):
    """Find a top-level `key:` block. Returns (start, end) or None."""
    pat = re.compile(r"^%s:(\s|$)" % re.escape(key))
    for k, line in enumerate(lines):
        if _is_code(line) and _indent(line) == 0 and pat.match(line):
            return (k, _block_end(lines, k, 0))
    return None


def find_membership(lines, member, lo, hi):
    """Within lines[lo:hi], find a flow-list or scalar list item containing
    `member` as a token. Returns line index or None."""
    token = re.compile(r"(?<![\w.])%s(?![\w.])" % re.escape(member))
    for k in range(lo, hi):
        s = lines[k].strip()
        if not _is_code(lines[k]):
            continue
        if ("[" in s and token.search(s.split("[", 1)[1])) or \
           (s.startswith("- ") and _unquote(s[2:]) == member):
            return k
    return None


# ---------------------------------------------------------------------------
# artifact discovery
# ---------------------------------------------------------------------------

class Artifact:
    def __init__(self, path):
        self.path = path
        with open(path, "r", encoding="utf-8") as f:
            self.text = f.read()
        self.lines = self.text.splitlines()
        self._data = None

    @property
    def data(self):
        if self._data is None:
            self._data = load_data(self.text)
        return self._data

    def slug(self, slug_keys):
        for key in slug_keys:
            v = self.data.get(key)
            if isinstance(v, str) and "#" not in v:
                return v
        return None


def find_artifacts(root, prefixes):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in sorted(filenames):
            low = fn.lower()
            if low.endswith(SUFFIX) and any(low.startswith(p) for p in prefixes):
                out.append(os.path.join(dirpath, fn))
    return sorted(out)


def canonical(paths, prefixes):
    """Prefer exactly-named files (prd.grist.yaml) over prefix matches."""
    exact = [p for p in paths
             if os.path.basename(p).lower() in {pre + SUFFIX for pre in prefixes}]
    return exact if exact else paths


# ---------------------------------------------------------------------------
# resolution
# ---------------------------------------------------------------------------

def emit(path, lines, start, end):
    print("# %s:%d" % (path, start + 1))
    block = [l for l in lines[start:end]]
    pad = min((_indent(l) for l in block if _is_code(l)), default=0)
    for l in block:
        print(l[pad:] if len(l) >= pad else l)


def emit_file(path, lines):
    emit(path, lines, 0, len(lines))


def resolve_in(art, id_path, lo, hi, root):
    """Resolve id_path within art.lines[lo:hi].

    Returns ('node', start, end) | ('line', k) | ('file', path) | None."""
    # 1. whole path as an id
    hits = find_id_nodes(art.lines, id_path, lo, hi)
    if len(hits) == 1:
        return ("node", hits[0][0], hits[0][1])
    if len(hits) > 1:
        die("ambiguous id '%s' in %s (%d matches)" % (id_path, art.path, len(hits)))
    # 2. top-level key (only at file scope)
    if lo == 0 and "." not in id_path:
        span = find_top_key(art.lines, id_path)
        if span:
            return ("node", span[0], span[1])
    # 3. dotted path: resolve head, then rest inside it
    if "." in id_path:
        for cut in range(1, len(id_path)):
            if id_path[cut] != ".":
                continue
            head, rest = id_path[:cut], id_path[cut + 1:]
            heads = find_id_nodes(art.lines, head, lo, hi)
            if len(heads) != 1:
                continue
            inner = resolve_in(art, rest, heads[0][0], heads[0][1], root)
            if inner:
                return inner
            # membership in a flow/block list (e.g. stories: [S1.1, ...])
            k = find_membership(art.lines, rest, heads[0][0], heads[0][1])
            if k is not None:
                story = find_story_file(root, rest)
                if story:
                    return ("file", story)
                return ("line", k)
    return None


def find_story_file(root, story_id):
    prefixes, slug_keys = TYPES["story"]
    for p in find_artifacts(root, prefixes):
        base = os.path.basename(p).lower()
        art = Artifact(p)
        if art.slug(slug_keys) == story_id or story_id.lower() in base:
            return p
    return None


def cmd_get(ref, root):
    parts = ref.split("#")
    if len(parts) < 2 or len(parts) > 3 or not all(parts):
        die("bad ref '%s' (expected <type>[#<slug>]#<id-path>)" % ref)
    rtype = parts[0].lower()
    if rtype not in TYPES:
        die("unknown type '%s' (expected one of: %s)"
            % (parts[0], ", ".join(sorted(set(TYPES) - {"architecture"}))))
    slug = parts[1] if len(parts) == 3 else None
    id_path = parts[-1]
    prefixes, slug_keys = TYPES[rtype]

    paths = find_artifacts(root, prefixes)
    if not paths:
        die("no %s*%s files found under %s" % ("|".join(prefixes), SUFFIX, root))
    arts = [Artifact(p) for p in paths]
    if slug is not None:
        arts = [a for a in arts if a.slug(slug_keys) == slug]
        if not arts:
            die("no %s artifact with slug '%s' under %s" % (rtype, slug, root))

    results = []
    for art in arts:
        res = resolve_in(art, id_path, 0, len(art.lines), root)
        if res is None and art.slug(slug_keys) == id_path:
            res = ("node", 0, len(art.lines))  # ref addresses the whole artifact
        if res:
            results.append((art, res))

    if not results:
        die("'%s' not found in: %s" % (ref, ", ".join(a.path for a in arts)))
    if len(results) > 1:
        keep = canonical([a.path for a, _ in results], prefixes)
        results = [(a, r) for a, r in results if a.path in keep]
    if len(results) > 1:
        die("ambiguous ref '%s'; candidates: %s (disambiguate with #<slug>)"
            % (ref, ", ".join(a.path for a, _ in results)))

    art, res = results[0]
    if res[0] == "node":
        emit(art.path, art.lines, res[1], res[2])
    elif res[0] == "line":
        emit(art.path, art.lines, res[1], res[1] + 1)
    else:  # file
        story = Artifact(res[2] if len(res) > 2 else res[1])
        emit_file(story.path, story.lines)


# ---------------------------------------------------------------------------
# --list
# ---------------------------------------------------------------------------

def _first_title(d):
    for key in TITLE_KEYS:
        v = d.get(key)
        if isinstance(v, str):
            return v
    for k, v in d.items():
        if k != "id" and isinstance(v, str):
            return v
    return ""


def collect_ids(value, out):
    if isinstance(value, dict):
        for v in value.values():
            collect_ids(v, out)
    elif isinstance(value, list):
        for item in value:
            if isinstance(item, dict) and isinstance(item.get("id"), str):
                out.append((item["id"], _first_title(item)))
            collect_ids(item, out)


def cmd_list(spec, root):
    parts = spec.split("#")
    rtype = parts[0].lower()
    slug = parts[1] if len(parts) > 1 and parts[1] else None
    if rtype not in TYPES:
        die("unknown type '%s'" % parts[0])
    prefixes, slug_keys = TYPES[rtype]
    paths = find_artifacts(root, prefixes)
    arts = [Artifact(p) for p in paths]
    if slug is not None:
        arts = [a for a in arts if a.slug(slug_keys) == slug]
    else:
        keep = canonical([a.path for a in arts], prefixes)
        arts = [a for a in arts if a.path in keep]
    if not arts:
        die("no %s artifact found under %s" % (rtype, root))
    for art in arts:
        if len(arts) > 1:
            print("# %s" % art.path)
        for key, v in art.data.items():
            if isinstance(v, str):
                short = v if len(v) <= 72 else v[:69] + "..."
                print("%s  %s" % (key, short))
        ids = []
        collect_ids(art.data, ids)
        for iid, title in ids:
            print("%s  %s" % (iid, title))


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        prog="grist-get.py",
        description="Resolve a GRIST reference (e.g. prd#E1) to just the "
                    "matching YAML node.")
    ap.add_argument("ref", nargs="?", help="reference: <type>[#<slug>]#<id-path>")
    ap.add_argument("--dir", default=".", metavar="DIR",
                    help="directory to search (default: cwd)")
    ap.add_argument("--list", dest="list_spec", metavar="TYPE[#SLUG]",
                    help="list addressable ids in the artifact of TYPE")
    args = ap.parse_args()

    root = os.path.abspath(args.dir)
    if not os.path.isdir(root):
        die("no such directory: %s" % root)
    if args.list_spec:
        cmd_list(args.list_spec, root)
    elif args.ref:
        cmd_get(args.ref, root)
    else:
        ap.print_usage(sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
