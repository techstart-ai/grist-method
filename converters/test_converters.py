#!/usr/bin/env python3
"""Tests for the BMAD → GRIST converters.

Run:
    python3 -m unittest discover converters
    python3 converters/test_converters.py

Stdlib only. Assertions are structural (keys, id shapes, non-emptiness),
not exact-string, so fixture files can evolve without breaking the suite.
"""
from __future__ import annotations

import importlib.util
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent


def load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


prd_conv = load("bmad_prd_to_grist", "bmad-prd-to-grist.py")
arch_conv = load("bmad_architecture_to_grist", "bmad-architecture-to-grist.py")
story_conv = load("bmad_story_to_grist", "bmad-story-to-grist.py")


def top_keys(yaml_text: str) -> list:
    """Top-level (column-0) mapping keys of a YAML document."""
    return re.findall(r"^([A-Za-z][A-Za-z0-9_-]*):", yaml_text, re.MULTILINE)


def assert_yamlish(tc: unittest.TestCase, text: str) -> None:
    """Sanity-check YAML shape without a YAML lib: every non-blank line is a
    key, a list item, or an indented continuation; no tabs; balanced quotes."""
    tc.assertTrue(text.endswith("\n"))
    for i, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        tc.assertNotIn("\t", line, "tab on line %d" % i)
        ok = re.match(r"^\s*(- )?[A-Za-z][A-Za-z0-9_-]*:( .*|$)", line) or re.match(
            r"^\s*- \S", line
        )
        tc.assertTrue(ok, "line %d not YAML-ish: %r" % (i, line))
        tc.assertEqual(line.count('"') % 2, 0, "unbalanced quotes on line %d" % i)
    tc.assertGreaterEqual(len(top_keys(text)), 2)


class TestPrdConverter(unittest.TestCase):
    PRD_MD = REPO / "examples" / "auth-v2" / "PRD.md"

    def setUp(self):
        if not self.PRD_MD.exists():
            self.skipTest("examples/auth-v2/PRD.md not present")
        self.md = self.PRD_MD.read_text(encoding="utf-8")

    def run_convert(self) -> str:
        sections = prd_conv.split_sections(self.md)
        data = {}
        for key, candidates in prd_conv.HEADING_MAP.items():
            body = prd_conv.find_section(sections, candidates)
            if not body:
                continue
            if key in ("problem", "goal"):
                data[key] = prd_conv.parse_first_paragraph(body)
            elif key == "epics":
                data[key] = prd_conv.parse_epics(body)
            elif key == "risks":
                data[key] = prd_conv.parse_risks(body)
            elif key == "acceptance":
                data[key] = prd_conv.parse_acceptance(body)
            else:
                data[key] = prd_conv.parse_bullets(body)
        return prd_conv.emit("auth-v2", data)

    def test_roundtrip_structure(self):
        out = self.run_convert()
        assert_yamlish(self, out)
        keys = top_keys(out)
        self.assertEqual(keys[0], "prd")
        self.assertIn("prd: auth-v2", out)
        self.assertIn("epics", keys)
        # epics have E<n> ids
        epic_ids = re.findall(r"- id: (E\d+)", out)
        self.assertGreaterEqual(len(epic_ids), 1)
        # nonempty problem and goal
        for field in ("problem", "goal"):
            m = re.search(r"^%s: (.+)$" % field, out, re.MULTILINE)
            self.assertIsNotNone(m, "missing %s" % field)
            val = m.group(1).strip().strip('"')
            self.assertTrue(val and val != "<TBD>", "empty %s" % field)

    def test_output_flag_writes_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "prd.grist.yaml"
            proc = subprocess.run(
                [sys.executable, str(HERE / "bmad-prd-to-grist.py"),
                 str(self.PRD_MD), "--slug", "auth-v2", "-o", str(dest)],
                capture_output=True, text=True,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(proc.stdout, "")
            self.assertTrue(dest.exists())
            self.assertIn("prd: auth-v2", dest.read_text(encoding="utf-8"))

    def test_default_is_stdout(self):
        proc = subprocess.run(
            [sys.executable, str(HERE / "bmad-prd-to-grist.py"), str(self.PRD_MD)],
            capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("prd:", proc.stdout)


ARCH_FIXTURE = """\
# Auth v2 Architecture

## Overview

An OIDC broker service in front of the existing session layer.

## Tech Stack

- Runtime: node20
- Framework: nextjs15
- Database: postgres16
- Cache: redis7

## Components

### OIDC Broker

Handles the Okta handshake, token exchange and refresh.

### Session Store

Persists sessions in Redis with ttl-based eviction.

## Architecture Decisions

### ADR-1: Opaque session tokens to client

Rationale: revocation must be possible before token expiry.

### ADR-2: Refresh on backend only

Rationale: token-leak risk on the client is unacceptable.

## Non-Functional Requirements

- p95 < 200ms for /auth/*
- audit log every signin

## Risks

- Redis outage: fall back to 1h grace cache
"""


class TestArchConverter(unittest.TestCase):
    def test_structure(self):
        out = arch_conv.convert(ARCH_FIXTURE, "auth-v2")
        assert_yamlish(self, out)
        keys = top_keys(out)
        self.assertEqual(keys[0], "arch")
        self.assertIn("arch: auth-v2", out)
        self.assertIn("prd: prd#auth-v2", out)
        # stack extracted
        self.assertIn("stack", keys)
        self.assertIn("runtime: node20", out)
        self.assertIn("db: postgres16", out)
        # components with C<n> ids and purposes
        comp_ids = re.findall(r"- id: (C\d+)", out)
        self.assertEqual(comp_ids, ["C1", "C2"])
        self.assertIn("oidc-broker", out)
        # decisions with d<n> ids and a why
        dec_ids = re.findall(r"- id: (d\d+)", out)
        self.assertGreaterEqual(len(dec_ids), 2)
        self.assertRegex(out, r"decision: .*[Oo]paque")
        self.assertRegex(out, r"why: .*revocation")
        # nfrs flow list, risks present
        self.assertRegex(out, re.compile(r"^nfrs: \[.+\]$", re.MULTILINE))
        self.assertIn("risks", keys)
        self.assertRegex(out, r"mitigation: .*grace cache")

    def test_prose_decision_cues(self):
        md = "# X\n\n## Design\n\nWe will use Postgres because it is boring.\n"
        out = arch_conv.convert(md, "x")
        self.assertRegex(out, r"decision: .*[Pp]ostgres")
        self.assertRegex(out, r"why: .*boring")

    def test_omits_empty_keys(self):
        out = arch_conv.convert("# Empty\n\nNothing here.\n", "empty")
        keys = top_keys(out)
        for absent in ("stack", "components", "decisions", "nfrs", "risks"):
            self.assertNotIn(absent, keys)

    def test_no_comments_in_output(self):
        out = arch_conv.convert(ARCH_FIXTURE, "auth-v2")
        for line in out.splitlines():
            self.assertFalse(line.lstrip().startswith("#"), line)


STORY_FIXTURE = """\
# Story S1.1: Okta OIDC handshake endpoint

Belongs to epic E1 of the auth-v2 PRD.

## Tasks

- [x] POST /auth/okta/callback receives code
- [ ] exchange code for tokens via okta SDK
- [ ] persist session to the session store
- [ ] set httpOnly cookie

## Acceptance Criteria

- Given a valid code, when the callback is hit, then it returns 302 + cookie
- callback returns 401 for invalid code
"""


class TestStoryConverter(unittest.TestCase):
    def convert(self, md: str, name: str = "story-S1.1.md") -> str:
        return story_conv.convert(md, Path(name), "auth-v2")

    def test_structure(self):
        out = self.convert(STORY_FIXTURE)
        assert_yamlish(self, out)
        keys = top_keys(out)
        self.assertEqual(keys[0], "story")
        self.assertIn("story: S1.1", out)
        self.assertIn("epic: prd#E1", out)
        self.assertIn("prd: prd#auth-v2", out)
        self.assertRegex(out, r"title: .*[Oo]kta OIDC handshake endpoint")
        # tasks with t<n> ids
        task_ids = re.findall(r"- id: (t\d+)", out)
        self.assertEqual(task_ids, ["t1", "t2", "t3", "t4"])
        # ac with ac<n> ids; given/when/then collapsed into one criterion
        ac_ids = re.findall(r"- id: (ac\d+)", out)
        self.assertEqual(ac_ids, ["ac1", "ac2"])
        self.assertRegex(out, r"test: .*[Gg]iven a valid code.*302")
        # one task done → in-progress
        self.assertIn("status: in-progress", out)

    def test_id_from_filename_variants(self):
        out = self.convert("# Some title\n\n- [ ] a task\n", name="story-2.3.md")
        self.assertIn("story: S2.3", out)
        self.assertIn("epic: prd#E2", out)

    def test_status_backlog_when_nothing_done(self):
        out = self.convert("# Story S1.2: x\n\n- [ ] only task\n", name="story-S1.2.md")
        self.assertIn("status: backlog", out)

    def test_no_comments_in_output(self):
        out = self.convert(STORY_FIXTURE)
        for line in out.splitlines():
            self.assertFalse(line.lstrip().startswith("#"), line)


if __name__ == "__main__":
    unittest.main()
