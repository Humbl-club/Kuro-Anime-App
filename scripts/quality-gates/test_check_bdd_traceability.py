#!/usr/bin/env python3
"""Self-tests for check_bdd_traceability.py (fixture trees are built in temp directories)."""
import contextlib
import importlib.util
import io
import shutil
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


SWIFT_SUITE = """import Testing

@MainActor
@Suite("x", .timeLimit(.minutes(1)))
struct LibraryTagsStoreTests {
    @Test("Filter {by} tag") func filterByTagShowsOnlyTaggedEntries() async {}

    func helper() {}
}

extension LibraryTagsStoreTests {
    @Test
    func second() {}
}
"""

FEATURES = "docs/superpowers/specs/s/features/"
LANDED = "scripts/quality-gates/bdd_landed.txt"


class TreeCase(unittest.TestCase):
    def setUp(self):
        self.mod = load_checker()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def run_cli(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = self.mod.main(["--root", str(self.root), *args])
        return code, out.getvalue()


class BddTraceabilityResolveTests(TreeCase):
    def test_swift_testing_resolution(self):
        self.write("KuroTests/A.swift", SWIFT_SUITE)
        r = self.mod.resolve
        self.assertIsNone(r(self.root, "@swift:LibraryTagsStoreTests/filterByTagShowsOnlyTaggedEntries"))
        self.assertIsNone(r(self.root, "@swift:LibraryTagsStoreTests/second"))
        self.assertEqual(
            r(self.root, "@swift:LibraryTagsStoreTests/missing"),
            "no @Test func missing in LibraryTagsStoreTests",
        )
        self.assertEqual(
            r(self.root, "@swift:LibraryTagsStoreTests/helper"),
            "no @Test func helper in LibraryTagsStoreTests",
        )

    def test_pkg_resolution_scope(self):
        self.write("KuroTests/A.swift", SWIFT_SUITE)
        reason = self.mod.resolve(self.root, "@pkg:LibraryTagsStoreTests/second")
        self.assertEqual(reason, "suite LibraryTagsStoreTests not found in Packages/KuroModules/Tests")
        self.write("Packages/KuroModules/Tests/KuroLibraryTests/A.swift", SWIFT_SUITE)
        self.assertIsNone(self.mod.resolve(self.root, "@pkg:LibraryTagsStoreTests/second"))

    def test_ui_resolution_xctest(self):
        self.write(
            "KuroUITests/G.swift",
            "final class GuestBrowsingUITests: XCTestCase {\n"
            "    func testSignedOutLaunchShowsDiscoverNotAuthWall() {}\n}\n",
        )
        good = "@ui:GuestBrowsingUITests/testSignedOutLaunchShowsDiscoverNotAuthWall"
        self.assertIsNone(self.mod.resolve(self.root, good))
        bad = "@ui:GuestBrowsingUITests/signedOutLaunchShowsDiscoverNotAuthWall"
        self.write(FEATURES + "W.feature", f"Feature: F\n  {bad}\n  Scenario: S\n")
        code, out = self.run_cli()
        self.assertEqual(code, 1)
        self.assertIn("@ui name must be the XCTest method (test…)", out)

    def test_landed_scope(self):
        self.write(FEATURES + "A.feature", "Feature: F\n  @swift:X/a\n  Scenario: S\n")
        self.write(FEATURES + "B.feature", "Feature: F\n  @swift:X/b\n  Scenario: S\n")
        self.write(LANDED, "# landed\nA.feature\n")
        code, out = self.run_cli()
        self.assertEqual(code, 1)
        self.assertIn("A.feature:3: S: suite X not found in KuroTests", out)
        self.assertIn("1 unresolved", out)
        self.assertIn("1 pending (not landed)", out)
        self.assertIn("B.feature:3: S: pending (not landed)", out)
        self.write(LANDED, "")
        code, out = self.run_cli()
        self.assertEqual(code, 0)
        self.assertIn("2 pending (not landed)", out)
        (self.root / LANDED).unlink()
        code, out = self.run_cli()
        self.assertEqual(code, 0)
        self.write(FEATURES + "B.feature", "Feature: F\n  Scenario: S\n")
        code, out = self.run_cli()
        self.assertEqual(code, 1)
        self.assertIn("missing test tag", out)

    def test_sql_and_deno_resolution(self):
        r = self.mod.resolve
        self.write("supabase/tests/rls/107_library_tags.sql", "select 1;\n")
        self.assertIsNone(r(self.root, "@sql:rls/107_library_tags.sql"))
        self.assertIn("not found", r(self.root, "@sql:rls/999_none.sql"))
        self.write(
            "supabase/functions/x/handler_test.ts",
            'Deno.test("deletes tags and custom lists", () => {});\n'
            'Deno.test({\n  name: "object form",\n  fn() {},\n});\n',
        )
        f = "supabase/functions/x/handler_test.ts"
        self.assertIsNone(r(self.root, f"@deno:{f}::deletes tags and custom lists"))
        self.assertIsNone(r(self.root, f"@deno:{f}::object form"))
        self.assertIn("not found", r(self.root, "@deno:supabase/functions/y/h.ts::a"))
        self.assertIn("no Deno.test", r(self.root, f"@deno:{f}::other name"))

    @unittest.skipUnless(shutil.which("node"), "node not available")
    def test_load_resolution(self):
        self.write(
            "scripts/load/backend_workload.js",
            'module.exports = { TRACKER_GAP_PROFILES: { "collection-with-tags-and-lists": {} } };\n',
        )
        r = self.mod.resolve
        self.assertIsNone(r(self.root, "@load:collection-with-tags-and-lists"))
        self.assertEqual(r(self.root, "@load:nope"), "unknown load profile nope")
        self.write("scripts/load/backend_workload.js", "module.exports = {};\n")
        self.assertEqual(r(self.root, "@load:nope"), "no TRACKER_GAP_PROFILES (F3)")

    def test_cli_exit_codes(self):
        self.write("KuroTests/A.swift", SWIFT_SUITE)
        self.write(LANDED, "W.feature\n")
        self.write(FEATURES + "W.feature", "Feature: F\n  @swift:LibraryTagsStoreTests/second\n  Scenario: S\n")
        code, out = self.run_cli()
        self.assertEqual(code, 0)
        self.assertIn("0 unresolved", out)
        self.write(FEATURES + "W.feature", "Feature: F\n  @swift:LibraryTagsStoreTests/nope\n  Scenario: S\n")
        code, out = self.run_cli()
        self.assertEqual(code, 1)
        self.assertTrue(out.startswith("docs/superpowers/specs/s/features/W.feature:3:"), out)


if __name__ == "__main__":
    unittest.main()
