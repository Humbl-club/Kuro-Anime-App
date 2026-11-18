"""Focused offline routing, drift and failure-boundary regressions."""

import copy
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import policy


class PolicyFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data = copy.deepcopy(policy.read_json(policy.ROOT / policy.MANIFEST))
        refs = list(self.data["authority"])
        for route in self.data["routes"]:
            refs.extend(route["sources"])
        for check in self.data["checks"].values():
            refs.extend(check["sources"])
        refs.append("AGENTS.md")
        for ref in set(refs):
            source = policy.ROOT / ref
            dest = self.root / ref
            if source.is_dir():
                dest.mkdir(parents=True, exist_ok=True)
            else:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(source.read_text())
        self.save()

    def save(self):
        target = self.root / policy.MANIFEST
        target.parent.mkdir(exist_ok=True)
        target.write_text(json.dumps(self.data))

    def cli(self, *args, event=None):
        return subprocess.run(
            [sys.executable, str(policy.ROOT / "scripts/agents/policy.py"), "--root", str(self.root), *args],
            input=json.dumps(event) if event is not None else None,
            text=True, capture_output=True, check=False,
        )


class PolicyTests(PolicyFixture):
    def test_current_checkout_references_validate(self):
        self.assertEqual(policy.load()["schema_version"], 2)

    def test_discovery_catalog_supplies_exact_valid_ids_and_existing_sources(self):
        result = self.cli("--discover")
        self.assertEqual(result.returncode, 0, result.stderr)
        routes = json.loads(result.stdout)["routes"]
        self.assertEqual([r["id"] for r in routes], [r["id"] for r in self.data["routes"]])
        for route in routes:
            self.assertTrue(all((self.root / p).exists() for p in route["sources"]))
        self.assertFalse((self.root / ".claude").exists())

    def test_filename_discovery_finds_package_owner_without_assuming_app_folder(self):
        result = self.cli("--files", "*LibraryProgress.swift")
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        owner = "Packages/KuroModules/Sources/KuroLibrary/LibraryProgress.swift"
        self.assertEqual(value["files"], [owner])
        self.assertIn("library_progress", value["routes_by_file"][owner])

    def test_nonexistent_but_route_matching_path_requires_discovery(self):
        result = self.cli("--paths", "Kuro/Library/LibraryProgress.swift")
        self.assertEqual(result.returncode, 2, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value["missing_paths"], ["Kuro/Library/LibraryProgress.swift"])
        self.assertEqual(value["status"], "discovery_required")
        self.assertEqual(value["unmapped"], [])
        self.assertIn("library_progress", [r["id"] for r in value["routes"]])

    def test_filename_miss_is_not_hidden_among_successful_matches(self):
        result = self.cli("--files", "LibraryProgress.swift", "NeverExisted.swift")
        self.assertEqual(result.returncode, 2, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value["unmatched_patterns"], ["NeverExisted.swift"])
        self.assertEqual(len(value["files"]), 1)

    def test_repeated_filename_options_preserve_every_pattern(self):
        result = self.cli("--files", "LibraryProgress.swift", "--files", "LibraryStore.swift", "--files", "NeverExisted.swift")
        self.assertEqual(result.returncode, 2, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(len(value["files"]), 2)
        self.assertEqual(value["unmatched_patterns"], ["NeverExisted.swift"])

    def test_discovery_avoids_archived_build_hidden_retired_and_symlink_files(self):
        for folder in ["archive", "Packages/.build", ".claude", "node_modules", "Kuro/Live"]:
            dest = self.root / folder / "Probe.swift"
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text("must not be read")
        (self.root / "Kuro/Live/SupabaseService.swift").write_text("retired")
        (self.root / "Kuro/Live/Link.swift").symlink_to(self.root / "Kuro/Live/Probe.swift")
        with mock.patch.object(Path, "read_text", side_effect=AssertionError("Inventory must not read file bodies")):
            value = policy.find_files(self.root, self.data, ["Probe.swift", "Link.swift", "SupabaseService.swift"])
        self.assertEqual(value["files"], ["Kuro/Live/Probe.swift"])
        self.assertEqual(value["unmatched_patterns"], ["Link.swift", "SupabaseService.swift"])

    def test_discovery_truncation_preserves_total_and_requires_narrowing(self):
        value = policy.find_files(self.root, self.data, ["*.swift"], limit=1)
        self.assertEqual(len(value["files"]), 1)
        self.assertTrue(value["truncated"])
        self.assertGreater(value["total_matches"], 1)
        self.assertIn("narrow", value["instruction"])

    def test_discovery_rejects_escaping_patterns_and_invalid_limits(self):
        for pattern in ["../*.swift", "/tmp/*.swift"]:
            with self.subTest(pattern=pattern), self.assertRaises(policy.PolicyError):
                policy.find_files(self.root, self.data, [pattern])
        for limit in [0, 501]:
            with self.subTest(limit=limit), self.assertRaises(policy.PolicyError):
                policy.find_files(self.root, self.data, ["*.swift"], limit=limit)

    def test_discovery_does_not_silently_ignore_other_cli_actions(self):
        for args in [("--discover", "--route", "identity"), ("--files", "*.swift", "--check"), ("--discover", "--files", "*.swift")]:
            result = self.cli(*args)
            self.assertEqual(result.returncode, 2)
            self.assertIn("separately", result.stderr)

    def test_shared_routing_works_without_any_claude_files(self):
        shutil.rmtree(self.root / ".claude", ignore_errors=True)
        (self.root / "CLAUDE.md").unlink(missing_ok=True)
        self.assertEqual(policy.load(self.root)["schema_version"], 2)
        result = self.cli("--route", "library_progress", "--route", "identity")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["unmapped"], [])
        self.assertNotIn("claude_adapter", json.loads(result.stdout))

    def test_shared_validation_does_not_read_claude_configuration(self):
        original_read = Path.read_text

        def guarded_read(path, *args, **kwargs):
            if ".claude" in path.parts or path.name == "CLAUDE.md":
                raise AssertionError("Shared validation tried to read Claude configuration")
            return original_read(path, *args, **kwargs)

        with mock.patch.object(Path, "read_text", guarded_read):
            policy.load(self.root)

    def test_claude_check_is_explicit_and_requires_its_adapter(self):
        shutil.rmtree(self.root / ".claude", ignore_errors=True)
        result = self.cli("--check-claude")
        self.assertEqual(result.returncode, 1)
        self.assertIn(".claude/adapter.json", result.stderr)
        self.assertEqual(self.cli("--check").returncode, 0)

    def test_shared_manifest_rejects_provider_adapter_configuration(self):
        self.data["claude_adapter"] = {"provider_settings": "must stay outside shared schema"}
        with self.assertRaisesRegex(policy.PolicyError, "manifest fields"):
            policy.validate(self.root, self.data)

    def test_current_native_source_folders_have_context_routes(self):
        paths = [str(path.relative_to(policy.ROOT)) for path in (policy.ROOT / "Kuro").rglob("*.swift")]
        result = policy.resolve(policy.ROOT, self.data, paths)
        self.assertEqual(result["unmapped"], [])

    def test_existing_package_manifest_has_a_context_route(self):
        result = self.cli("--paths", "Packages/KuroModules/Package.swift")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([r["id"] for r in json.loads(result.stdout)["routes"]], ["infrastructure"])

    def test_progress_routes_to_current_owners_not_retired_service(self):
        result = policy.resolve(self.root, self.data, ["Kuro/Library/LibraryActions.swift"])
        self.assertEqual(result["status"], "context_candidates")
        sources = result["routes"][0]["sources"]
        self.assertIn("Packages/KuroModules/Sources/KuroLibrary/ProgressOutbox.swift", sources)
        self.assertIn("Packages/KuroModules/Sources/KuroLibrary/LibraryProgress.swift", sources)
        self.assertIn("Kuro/Home/HomeStore.swift", sources)
        self.assertIn("Kuro/Collection/CollectionStore+Lists.swift", sources)
        self.assertFalse(any("SupabaseService" in source for source in sources))
        self.assertIn("package_progress", result["checks"])

    def test_transport_combines_identity_and_library(self):
        result = policy.resolve(self.root, self.data, ["Kuro/Composition/PostgrestLibraryTransport.swift"])
        self.assertEqual({route["id"] for route in result["routes"]}, {"library_progress", "identity"})

    def test_view_combines_presentation_and_capability(self):
        result = policy.resolve(self.root, self.data, ["Kuro/Views/Collection/NewView.swift"])
        self.assertEqual({route["id"] for route in result["routes"]}, {"home_collection_releases", "navigation_ui"})

    def test_glob_star_respects_directories_and_double_star_recurses(self):
        self.assertTrue(policy.matches("Kuro/Views/Collection/Deep/New.swift", "Kuro/Views/**"))
        self.assertTrue(policy.matches("Kuro/Library", "Kuro/Library/**"))
        self.assertFalse(policy.matches("scripts/agents/nested_enrichment.py", "scripts/*enrichment*"))
        self.assertTrue(policy.matches("scripts/series_enrichment_worker.py", "scripts/*enrichment*"))

    def test_edge_change_combines_intake_and_server_contract(self):
        result = policy.resolve(self.root, self.data, ["supabase/functions/bulk-import-anime/mapping.ts"])
        self.assertEqual({route["id"] for route in result["routes"]}, {"edge_functions", "catalog_intake"})

    def test_unknown_path_does_not_disappear_among_known_paths(self):
        result = self.cli("--paths", "Kuro/Library/LibraryActions.swift", "new_area/feature.swift", "--route", "identity")
        self.assertEqual(result.returncode, 2, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value["status"], "discovery_required")
        self.assertEqual(value["unmapped"], ["new_area/feature.swift"])
        self.assertIn("identity", [route["id"] for route in value["routes"]])

    def test_archive_and_retired_file_require_discovery_even_with_explicit_route(self):
        result = policy.resolve(self.root, self.data, ["archive/old.swift", "Kuro/Library/SupabaseService.swift"], ["library_progress"])
        self.assertEqual(len(result["unmapped"]), 2)

    def test_unknown_route_fails_without_fallback(self):
        result = self.cli("--route", "looks_like_library")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Unknown routes", result.stderr)
        self.assertIn("--discover first", result.stderr)
        self.assertIn("library_progress", result.stderr)

    def test_rpc_lookup_includes_later_prepared_replacement(self):
        for folder, filename, body in (
            ("supabase/migrations", "20260101000000_old.sql", "CREATE FUNCTION public.example(p int) RETURNS int AS $$ SELECT p $$ LANGUAGE sql;"),
            ("supabase/prepared-migrations", "20260201000000_new.sql", "-- source candidate\ncreate or replace function public.example(p int) returns int as $$ select p $$ language sql;"),
        ):
            dest = self.root / folder / filename
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(body)
        result = policy.rpc_definitions(self.root, "example")
        self.assertEqual([item["line"] for item in result], [1, 2])
        self.assertTrue(result[-1]["path"].endswith("20260201000000_new.sql"))
        response = self.cli("--rpc", "example")
        self.assertEqual(response.returncode, 0, response.stderr)
        self.assertIn("Neither folder proves", json.loads(response.stdout)["sql_evidence_limit"])

    def test_rpc_lookup_preserves_multiple_definitions_and_rejects_prefixes(self):
        dest = self.root / "supabase/migrations/20260101000000_multiple.sql"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text('CREATE FUNCTION public.example_other() RETURNS int;\nCREATE FUNCTION public.example() RETURNS int;\nCREATE OR REPLACE FUNCTION "public"."example"() RETURNS int;')
        self.assertEqual([item["line"] for item in policy.rpc_definitions(self.root, "example")], [2, 3])

    def test_unknown_rpc_requires_discovery_even_with_valid_route(self):
        result = self.cli("--route", "library_progress", "--rpc", "missing_function")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(json.loads(result.stdout)["unresolved_rpcs"], ["missing_function"])

    def test_rpc_lookup_rejects_nonidentifiers(self):
        with self.assertRaises(policy.PolicyError):
            policy.rpc_definitions(self.root, "../file;select")

    def test_current_progress_internal_helper_lookup_exposes_later_body(self):
        result = policy.rpc_definitions(policy.ROOT, "_apply_progress_mutations_for_user")
        self.assertGreaterEqual(len(result), 2)
        self.assertTrue(any(item["path"].endswith("20261008100000_import_status_fence_preserves_units.sql") for item in result))

    def test_paths_cannot_escape_repo_or_follow_external_symlink(self):
        for path in ("../elsewhere/file.swift", "/tmp/file.swift"):
            with self.subTest(path=path), self.assertRaises(policy.PolicyError):
                policy.resolve(self.root, self.data, [path])
        with tempfile.TemporaryDirectory() as outside:
            (self.root / "external").symlink_to(outside, target_is_directory=True)
            with self.assertRaises(policy.PolicyError):
                policy.resolve(self.root, self.data, ["external/file.swift"])

    def test_missing_owner_reference_is_a_failure(self):
        (self.root / "Kuro/Library/LibraryActions.swift").unlink()
        with self.assertRaisesRegex(policy.PolicyError, "missing path"):
            policy.load(self.root)

    def test_existing_retired_service_is_not_a_valid_owner_reference(self):
        old = self.root / "Kuro/Services/SupabaseService.swift"
        old.write_text("retired")
        self.data["routes"][0]["sources"] = ["Kuro/Services/SupabaseService.swift"]
        with self.assertRaisesRegex(policy.PolicyError, "retired owner"):
            policy.validate(self.root, self.data)

    def test_history_cannot_become_required_authority(self):
        (self.root / "archive").mkdir()
        (self.root / "archive/old.md").write_text("retired")
        self.data["routes"][0]["sources"] = ["archive/old.md"]
        with self.assertRaisesRegex(policy.PolicyError, "historical material"):
            policy.validate(self.root, self.data)

    def test_internal_symlink_cannot_promote_archived_source(self):
        (self.root / "archive").mkdir()
        old = self.root / "archive/old.swift"
        old.write_text("retired")
        alias = self.root / "Kuro/Library/Alias.swift"
        alias.symlink_to(old)
        result = policy.resolve(self.root, self.data, ["Kuro/Library/Alias.swift"])
        self.assertEqual(result["status"], "discovery_required")
        self.data["routes"][0]["sources"] = ["Kuro/Library/Alias.swift"]
        with self.assertRaisesRegex(policy.PolicyError, "historical material"):
            policy.validate(self.root, self.data)

    def test_unknown_check_and_profile_are_rejected(self):
        for key, value in (("checks", ["imaginary_check"]), ("profile", "imaginary_profile")):
            data = copy.deepcopy(self.data)
            data["routes"][0][key] = value
            with self.subTest(key=key), self.assertRaises(policy.PolicyError):
                policy.validate(self.root, data)

    def test_duplicate_route_and_catchall_are_rejected(self):
        data = copy.deepcopy(self.data)
        data["routes"].append(data["routes"][0])
        with self.assertRaisesRegex(policy.PolicyError, "duplicate route"):
            policy.validate(self.root, data)
        self.data["routes"][0]["paths"] = ["**"]
        with self.assertRaisesRegex(policy.PolicyError, "catch-all"):
            policy.validate(self.root, self.data)

    def test_duplicate_json_and_unsupported_schema_are_rejected(self):
        path = self.root / "duplicate.yaml"
        path.write_text('{"schema_version":1,"schema_version":2}')
        with self.assertRaisesRegex(policy.PolicyError, "Duplicate configuration"):
            policy.read_json(path)
        self.data["schema_version"] = 99
        with self.assertRaisesRegex(policy.PolicyError, "schema_version"):
            policy.validate(self.root, self.data)
        self.data["schema_version"] = 2
        self.data["typo"] = True
        with self.assertRaisesRegex(policy.PolicyError, "manifest fields"):
            policy.validate(self.root, self.data)

    def test_resolving_is_read_only(self):
        def snapshot():
            return {str(path.relative_to(self.root)): path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        before = snapshot()
        result = self.cli("--route", "library_progress")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(snapshot(), before)


@unittest.skipUnless((policy.ROOT / policy.CLAUDE_MANIFEST).is_file(), "Optional Claude adapter not installed")
class ClaudeAdapterTests(PolicyFixture):
    def setUp(self):
        super().setUp()
        self.adapter = copy.deepcopy(policy.read_json(policy.ROOT / policy.CLAUDE_MANIFEST))
        refs = ["CLAUDE.md", policy.CLAUDE_MANIFEST, self.adapter["settings"]]
        refs.extend(worker["file"] for worker in self.adapter["workers"].values())
        for ref in refs:
            dest = self.root / ref
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text((policy.ROOT / ref).read_text())

    def test_current_installed_adapter_validates(self):
        self.assertEqual(policy.load_claude()["schema_version"], 1)

    def test_explicit_adapter_validation_never_applies_env_or_runs_hooks(self):
        before = dict(os.environ)
        with mock.patch.object(subprocess, "run", side_effect=AssertionError("Hook execution forbidden")):
            policy.validate_claude(self.root, self.data, self.adapter)
        self.assertEqual(dict(os.environ), before)

    def test_read_only_worker_cannot_gain_shell_by_changing_manifest(self):
        self.adapter["workers"]["Explore"]["tools"].append("Bash")
        with self.assertRaisesRegex(policy.PolicyError, "Read-only worker"):
            policy.validate_claude(self.root, self.data, self.adapter)

    def test_model_tool_and_policy_omission_drift_fail(self):
        path = self.root / ".claude/agents/Explore.md"
        original = path.read_text()
        for text in (
            original.replace("model: haiku", "model: opus"),
            original.replace("tools: Read, Grep, Glob", "tools: Read, Grep, Glob, Bash"),
            original.replace("effort: low", "effort: low\nomitClaudeMd: true"),
        ):
            path.write_text(text)
            with self.subTest(text=text[:90]), self.assertRaises(policy.PolicyError):
                policy.validate_claude(self.root, self.data, self.adapter)
        path.write_text(original)

    def test_adapter_must_import_shared_policy(self):
        path = self.root / "CLAUDE.md"
        path.write_text(path.read_text().replace("@AGENTS.md", "AGENTS.md"))
        with self.assertRaisesRegex(policy.PolicyError, "must import"):
            policy.validate_claude(self.root, self.data, self.adapter)

    def test_adapter_cannot_silently_enable_untracked_advisor_model(self):
        path = self.root / ".claude/settings.json"
        settings = json.loads(path.read_text())
        settings["env"].pop("CLAUDE_CODE_DISABLE_ADVISOR_TOOL")
        path.write_text(json.dumps(settings))
        with self.assertRaisesRegex(policy.PolicyError, "implicit server-side advisor"):
            policy.validate_claude(self.root, self.data, self.adapter)

    def test_startup_hook_outputs_context_without_running_checks(self):
        nested = self.root / "Kuro/Library"
        result = self.cli("--claude-start", event={"cwd": str(nested)})
        self.assertEqual(result.returncode, 0, result.stderr)
        context = json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("validation PASS", context)
        self.assertIn(str(self.root), context)
        self.assertIn("--discover", context)
        self.assertIn("--files", context)

    def test_startup_failure_is_visible_and_nonzero(self):
        (self.root / "Kuro/Library/LibraryActions.swift").unlink()
        result = self.cli("--claude-start", event={"cwd": str(self.root)})
        self.assertEqual(result.returncode, 1)
        self.assertIn("validation FAILED", json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"])


if __name__ == "__main__":
    unittest.main()
