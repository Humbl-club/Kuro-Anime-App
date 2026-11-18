#!/usr/bin/env python3
"""Self-tests for check_bdd_traceability.py (fixture trees are built in temp directories)."""
import contextlib
import importlib.util
import io
import json
import shutil
import subprocess
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


TESTDATA = Path(__file__).resolve().parent / "testdata" / "bdd_acceptance_logs"
ACC = "docs/tracker-gaps-2026-11/acceptance/"
SWIFT_TAG = "@swift:SessionSDKTests/failedEmailSignInPublishesOnlyTheMessage"
SWIFT_FEATURE = f"Feature: F\n  {SWIFT_TAG}\n  Scenario: Swift one\n"


@unittest.skipUnless(shutil.which("git"), "git not available")
class BddAcceptanceTests(TreeCase):
    def setUp(self):
        super().setUp()
        self.git("init", "-q")

    def git(self, *args):
        run = subprocess.run(
            ["git", "-C", str(self.root), "-c", "user.name=t", "-c", "user.email=t@example.invalid", *args],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        return run.stdout.strip()

    def commit_all(self, message="c"):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def log(self, name, text):
        self.write(f"{ACC}logs/{name}", text)
        return f"{ACC}logs/{name}"

    def fixture_log(self, name):
        return (TESTDATA / name).read_text(encoding="utf-8")

    def record(self, ws, sha, runs, scenarios, gates=()):
        record = {
            "schemaVersion": 1,
            "workstream": ws,
            "testedCommit": sha,
            "recordedAt": "2026-11-18T00:00:00Z",
            "runs": runs,
            "scenarios": scenarios,
            "unresolvedGates": list(gates),
        }
        self.write(f"{ACC}{ws}.json", json.dumps(record, indent=2))

    def accepted(self, ws="W9"):
        return self.run_cli("--accepted", ws)

    def swift_run(self, log_path, run_id="swift-1"):
        return {
            "id": run_id,
            "layer": "swift",
            "command": "xcodebuild test -only-testing:KuroTests/SessionSDKTests",
            "context": {"kind": "simulator", "simulator": "00000000-0000-0000-0000-000000000000"},
            "exitCode": 0,
            "log": log_path,
        }

    def entry(self, scenario, tag, run="swift-1", result="pass", feature="W9-x.feature"):
        return {"feature": feature, "scenario": scenario, "tag": tag, "result": result, "run": run}

    def swift_setup(self, feature_text=SWIFT_FEATURE):
        self.write(FEATURES + "W9-x.feature", feature_text)
        sha = self.commit_all()
        log_path = self.log("W9-swift-1.txt", self.fixture_log("swift-xcodebuild.log"))
        return sha, log_path

    def test_accepted_scope_and_happy_path(self):
        text = (
            "Feature: F\n"
            "  @workstream-F2\n  Rule: R1\n    @pkg:A/b\n    Scenario: Needs F2\n"
            f"  Rule: R2\n    {SWIFT_TAG}\n    Scenario: Swift one\n"
        )
        sha, log_path = self.swift_setup(text)
        entry = self.entry("Swift one", SWIFT_TAG)
        self.record("W9", sha, [self.swift_run(log_path)], [entry])
        code, out = self.accepted()
        self.assertEqual(code, 0, out)
        self.assertIn("Accepted W9: 1/1", out)
        self.record("W9", sha, [self.swift_run(log_path)], [])
        code, out = self.accepted()
        self.assertEqual(code, 1)
        self.assertIn("no result", out)

    def test_record_commit_rules(self):
        sha, log_path = self.swift_setup()
        runs, scenarios = [self.swift_run(log_path)], [self.entry("Swift one", SWIFT_TAG)]
        self.record("W9", sha, runs, scenarios)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "record")
        self.assertEqual(self.accepted()[0], 0)
        self.write("KuroTests/A.swift", "struct A {}\n")
        self.commit_all("source change")
        code, out = self.accepted()
        self.assertEqual(code, 1)
        self.assertIn("changed outside acceptance records", out)
        self.git("reset", "-q", "--hard", "HEAD~1")
        self.assertEqual(self.accepted()[0], 0)
        self.write("Kuro/x.swift", "struct X {}\n")
        code, out = self.accepted()
        self.assertEqual(code, 1)
        self.assertIn("uncommitted changes", out)

    def sql_case(self, log_text):
        self.write("supabase/tests/rls/107_x.sql", "select 1;\n")
        self.write(FEATURES + "W9-x.feature", "Feature: F\n  @sql:rls/107_x.sql\n  Scenario: Sql one\n")
        sha = self.commit_all()
        run = {
            "id": "sql-1",
            "layer": "sql",
            "command": "bash scripts/db/run_local_db_tests.sh",
            "context": {"kind": "local-db"},
            "exitCode": 0,
            "log": "",
        }
        if log_text is not None:
            run["log"] = self.log("W9-sql-1.txt", log_text)
        else:
            run["log"] = f"{ACC}logs/W9-sql-1.txt"
        self.record("W9", sha, [run], [self.entry("Sql one", "@sql:rls/107_x.sql", run="sql-1")])
        return self.accepted()

    def test_sql_requires_passing_run(self):
        self.assertEqual(self.sql_case(None)[0], 1)
        for bad in (
            "BLOCKED 107_x.sql no local PostgreSQL\n",
            "PASS  107_x.sql  12 assertions, 1 blocked markers, 0 findings\n",
            "PASS  107_x.sql  12 assertions, 0 blocked markers, 0 findings, 1 scope(s) BLOCKED\n",
            "FAIL  107_x.sql  after 3 assertions\n",
        ):
            code, out = self.sql_case(bad)
            self.assertEqual(code, 1, bad)
            self.assertIn("SQL test did not run and pass", out)
        code, out = self.sql_case("PASS  107_x.sql  12 assertions, 0 blocked markers, 0 findings\n")
        self.assertEqual(code, 0, out)

    def load_case(self, mode="qualify", verdict="pass", preflight=True, run_key="k1", present="absent"):
        self.write(FEATURES + "W9-x.feature", "Feature: F\n  @load:prof\n  Scenario: Load one\n")
        sha = self.commit_all()
        report = {
            "mode": mode,
            "runKey": run_key,
            "preflight": {"passed": preflight},
            "lanes": {"profiles": {"profiles": {"prof": {"verdict": verdict}}}},
        }
        self.write(f"{ACC}load/report.json", json.dumps(report))
        self.write(f"{ACC}load/cleanup.json", json.dumps({"cleanup": [{"index": 1, "profileData": {"prof": present}}]}))
        run = {
            "id": "load-1",
            "layer": "load",
            "command": "node scripts/load_test_backend.js --qualify",
            "context": {
                "kind": "load-qualification",
                "loadReport": f"{ACC}load/report.json",
                "loadRunKey": "k1",
                "cleanupReport": f"{ACC}load/cleanup.json",
            },
            "exitCode": 0,
            "log": self.log("W9-load-1.txt", "report written\n"),
        }
        self.record("W9", sha, [run], [self.entry("Load one", "@load:prof", run="load-1")])
        return self.accepted()

    def test_load_requires_qualification_report(self):
        for kwargs in (
            {"mode": "wiring"},
            {"verdict": "insufficient"},
            {"preflight": False},
            {"run_key": "other"},
            {"present": "present"},
        ):
            code, out = self.load_case(**kwargs)
            self.assertEqual(code, 1, kwargs)
            self.assertIn("load evidence is not a passing qualification run", out)
        code, out = self.load_case()
        self.assertEqual(code, 0, out)

    def test_results_and_tags(self):
        sha, log_path = self.swift_setup()
        runs = [self.swift_run(log_path)]
        for result, expected in (
            ("blocked", "not accepted: blocked"),
            ("fail", "not accepted: fail"),
            ("insufficient", "not accepted: insufficient"),
            ("ok", "invalid result ok"),
        ):
            self.record("W9", sha, runs, [self.entry("Swift one", SWIFT_TAG, result=result)])
            code, out = self.accepted()
            self.assertEqual(code, 1)
            self.assertIn(expected, out)
        self.record("W9", sha, runs, [self.entry("Swift one", "@swift:A/old")])
        self.assertIn("tag changed since record", self.accepted()[1])
        entries = [self.entry("Swift one", SWIFT_TAG), self.entry("Gone", "@swift:A/x")]
        self.record("W9", sha, runs, entries)
        self.assertIn("stale record entry", self.accepted()[1])
        # a test named only on a skipped line does not pass
        skipped = self.log("W9-skip.txt", "Test case 'SessionSDKTests/failedEmailSignInPublishesOnlyTheMessage()' skipped\n")
        self.record("W9", sha, [self.swift_run(skipped)], [self.entry("Swift one", SWIFT_TAG)])
        self.assertIn("test did not pass in log", self.accepted()[1])

    def test_layer_patterns_against_captured_logs(self):
        tags = {
            "pkg": ("@pkg:SupabaseLibraryBackendTests/importedMetadataProjectsOnlyBehindFencedColumns", "pkg-swift-testing.log"),
            "ui": ("@ui:NavshellUITests/testBackSwipeReturnsToPreviousPage", "ui-xctest.log"),
            "deno": (
                "@deno:supabase/functions/concierge-apply/handler_test.ts::planned item wire shape (the p_items contract the SQL test 70_import_apply_undo_transactions.sql uses)",
                "deno-test.log",
            ),
        }
        self.write("KuroTests/A.swift", "struct A {}\n")
        for layer, (tag, log_name) in tags.items():
            self.write(FEATURES + "W9-x.feature", f"Feature: F\n  {tag}\n  Scenario: S1\n")
            sha = self.commit_all(layer)
            context = {"kind": "local"}
            if layer == "ui":
                context = {"kind": "simulator", "simulator": "UUID"}
            run = {"id": "r1", "layer": layer, "command": "x", "context": context, "exitCode": 0,
                   "log": self.log(f"W9-{layer}.txt", self.fixture_log(log_name))}
            self.record("W9", sha, [run], [self.entry("S1", tag, run="r1")])
            code, out = self.accepted()
            self.assertEqual(code, 0, f"{layer}: {out}")

    def test_pkg_labelled_test_matches_display_name(self):
        suite = (
            "struct LabelSuite {\n"
            '    @Test("A date-only edit sends exactly one PATCH carrying only the date column")\n'
            "    func dateOnlyEdit() {}\n}\n"
        )
        self.write("Packages/KuroModules/Tests/KuroLibraryTests/L.swift", suite)
        tag = "@pkg:LabelSuite/dateOnlyEdit"
        self.write(FEATURES + "W9-x.feature", f"Feature: F\n  {tag}\n  Scenario: S1\n")
        sha = self.commit_all()
        run = {"id": "r1", "layer": "pkg", "command": "swift test", "context": {"kind": "local"}, "exitCode": 0,
               "log": self.log("W9-pkg.txt", self.fixture_log("pkg-swift-testing.log"))}
        self.record("W9", sha, [run], [self.entry("S1", tag, run="r1")])
        code, out = self.accepted()
        self.assertEqual(code, 0, out)

    def test_gated_and_manual(self):
        text = (
            "Feature: F\n"
            "  @gated @owner-gate\n  Rule: Gated\n    @manual:awaits-D-D @owner-gate\n    Scenario: Waiting\n"
            "  Rule: Manual\n    @manual:visual @owner-gate\n    Scenario: Looks right\n"
        )
        self.write(FEATURES + "W9-x.feature", text)
        self.write("evidence/shot.png", "x")
        sha = self.commit_all()
        run = {"id": "m1", "layer": "manual", "command": "owner walk", "exitCode": 0,
               "context": {"kind": "owner", "owner": "max", "evidence": "evidence/shot.png"},
               "log": self.log("W9-m1.txt", "owner accepted\n")}
        entry = self.entry("Looks right", "@manual:visual", run="m1")
        self.record("W9", sha, [run], [entry], gates=[])
        code, out = self.accepted()
        self.assertEqual(code, 1)
        self.assertIn("gated scenarios but no unresolved gate named", out)
        self.assertIn("gated (excluded)", out)
        self.record("W9", sha, [run], [entry], gates=["D-D pending"])
        self.assertEqual(self.accepted()[0], 0)
        run["context"]["evidence"] = "evidence/missing.png"
        self.record("W9", sha, [run], [entry], gates=["D-D pending"])
        self.assertEqual(self.accepted()[0], 1)

    def test_record_template(self):
        text = (
            "Feature: F\n  @workstream-W9\n  Rule: Gated\n"
            "  Rule: Real\n    @pkg:A/b\n    Scenario: One\n    @swift:A/c\n    Scenario: Two\n"
        )
        self.write(FEATURES + "W9-x.feature", text)
        sha = self.commit_all()
        code, out = self.run_cli("--record-template", "W9")
        self.assertEqual(code, 0)
        template = json.loads(out)
        self.assertEqual(template["testedCommit"], sha)
        self.assertEqual([s["result"] for s in template["scenarios"]], ["blocked", "blocked"])
        self.assertEqual(template["runs"], [])
        self.write(f"{ACC}W9.json", out)
        code, out = self.accepted()
        self.assertEqual(code, 1)
        self.assertEqual(out.count("not accepted: blocked"), 2)

    def test_usage_errors(self):
        self.assertEqual(self.run_cli("--accepted", "")[0], 2)
        self.assertEqual(self.run_cli("--accepted", "W9", "--record-template", "W9")[0], 2)
        self.assertEqual(self.run_cli("--bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
