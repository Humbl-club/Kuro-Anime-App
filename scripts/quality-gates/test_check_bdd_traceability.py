#!/usr/bin/env python3
"""Self-tests for check_bdd_traceability.py (fixture trees are built in temp directories)."""
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

CHECKER = Path(__file__).resolve().parent / "check_bdd_traceability.py"


def load_checker():
    spec = importlib.util.spec_from_file_location("check_bdd_traceability", CHECKER)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module  # dataclasses need the module registered
    spec.loader.exec_module(module)
    return module


class BddTraceabilityParseTests(unittest.TestCase):
    def setUp(self):
        self.mod = load_checker()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def feature(self, name, text):
        path = self.dir / name
        path.write_text(text, encoding="utf-8")
        return path

    def problems(self, name, text):
        self.feature(name, text)
        findings = self.mod.check(self.dir, name)
        return [f.problem for f in findings]

    def test_valid_single_tag(self):
        path = self.feature("W9-x.feature", "Feature: F\n\n  @sql:rls/107_x.sql\n  Scenario: One\n    Given a\n")
        scenarios = self.mod.parse_feature(path)
        self.assertEqual(len(scenarios), 1)
        self.assertEqual(scenarios[0].test_tags, ["@sql:rls/107_x.sql"])

    def test_missing_tag(self):
        self.feature("W9-x.feature", "Feature: F\n\n  Scenario: One\n    Given a\n")
        findings = self.mod.check(self.dir, "W9-x.feature")
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].problem, "missing test tag")
        self.assertEqual(findings[0].line, 3)

    def test_two_tags(self):
        problems = self.problems("W9-x.feature", "Feature: F\n\n  @pkg:A/b @swift:C/d\n  Scenario: One\n")
        self.assertEqual(problems, ["2 test tags (@pkg:A/b, @swift:C/d)"])

    def test_deno_name_with_spaces(self):
        tag = "@deno:supabase/functions/x/handler_test.ts::deletes tags and custom lists"
        path = self.feature("W9-x.feature", f"Feature: F\n\n  {tag}\n  Scenario: One\n")
        scenarios = self.mod.parse_feature(path)
        self.assertEqual(scenarios[0].test_tags, [tag])
        self.assertEqual(self.mod.check(self.dir, "W9-x.feature"), [])

    def test_manual_requires_owner_gate(self):
        ok = self.problems("W9-x.feature", "Feature: F\n\n  @manual:awaits-D-D @owner-gate\n  Scenario: One\n")
        self.assertEqual(ok, [])
        bad = self.problems("W9-x.feature", "Feature: F\n\n  @manual:awaits-D-D\n  Scenario: One\n")
        self.assertEqual(bad, ["@manual needs @owner-gate"])

    def test_gated_feature_and_rule_skip(self):
        self.assertEqual(self.problems("W1-x.feature", "@gated\nFeature: F\n\n  Scenario: A\n  Scenario: B\n"), [])
        text = (
            "Feature: F\n\n"
            "  @gated @owner-gate\n  Rule: R1\n\n    Scenario: A\n\n"
            "  Rule: R2\n\n    Scenario: B\n"
        )
        self.feature("W1-x.feature", text)
        findings = self.mod.check(self.dir, "W1-x.feature")
        self.assertEqual([(f.scenario, f.problem) for f in findings], [("B", "missing test tag")])
        scenarios = self.mod.parse_feature(self.dir / "W1-x.feature")
        self.assertTrue(scenarios[0].gated)
        self.assertFalse(scenarios[1].gated)
        text = "@gated\nFeature: F\n\n  @manual:awaits-D-X\n  Scenario: A\n"
        self.assertEqual(self.problems("W1-x.feature", text), ["@manual needs @owner-gate"])

    def test_unknown_layer(self):
        self.assertEqual(
            self.problems("W9-x.feature", "Feature: F\n\n  @foo:bar\n  Scenario: One\n"),
            ["unknown test layer @foo:bar"],
        )

    def test_workstream_and_duplicate_names(self):
        text = (
            "Feature: F\n\n"
            "  @workstream-F2\n  Rule: R1\n\n    @pkg:A/b\n    Scenario: In F2\n\n"
            "  Rule: R2\n\n    @pkg:A/c\n    Scenario: In W9\n"
        )
        path = self.feature("W9-x.feature", text)
        scenarios = self.mod.parse_feature(path)
        self.assertEqual([s.workstream for s in scenarios], ["F2", "W9"])
        path = self.feature("W3-y.feature", "@workstream-W3a\nFeature: F\n\n  @pkg:A/b\n  Scenario: S\n")
        self.assertEqual(self.mod.parse_feature(path)[0].workstream, "W3a")
        problems = self.problems(
            "W9-d.feature", "Feature: F\n\n  @pkg:A/b\n  Scenario: Same\n\n  @pkg:A/c\n  Scenario: Same\n"
        )
        self.assertEqual(problems, ["duplicate scenario name"])


if __name__ == "__main__":
    unittest.main()
