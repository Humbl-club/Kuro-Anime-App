"""Offline release-runner regressions; never invoke Apple tooling or a simulator."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


class NativeUnitGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kuro-ios-gate-")
        self.work = Path(self.temporary.name)
        binary = self.work / "bin"
        binary.mkdir()
        (binary / "python3").symlink_to(sys.executable)
        scripts = {
            "xcrun": "import os\nprint(os.environ['KURO_FAKE_DEVICES'])\n",
            "xcodebuild": """import json, os, pathlib, sys
with open(os.environ['KURO_RUNNER_ARGS'], 'a') as file:
    file.write(json.dumps(sys.argv[1:])+'\\n')
print(os.environ.get('KURO_FAKE_TEST_LOG', ''))
sys.exit(int(os.environ.get('KURO_FAKE_XCODE_EXIT', '0')))
""",
        }
        for name, body in scripts.items():
            script = binary / name
            script.write_text(f"#!{sys.executable}\n{body}")
            script.chmod(0o755)
        self.environment = dict(os.environ)
        self.environment.update({
            "PATH": str(binary) + os.pathsep + os.environ["PATH"],
            "KURO_IOS_UNIT_REPORT_DIR": str(self.work / "reports"),
            "KURO_RUNNER_ARGS": str(self.work / "calls.jsonl"),
            "KURO_FAKE_DEVICES": json.dumps({"devices": {"iOS-26.2": [
                {"name": "iPhone 17 Pro", "isAvailable": True, "state": "Shutdown", "udid": "11111111-1111-1111-1111-111111111111"},
                {"name": "iPhone 17 Pro", "isAvailable": True, "state": "Booted", "udid": "22222222-2222-2222-2222-222222222222"},
            ]}}),
        })

    def tearDown(self):
        self.temporary.cleanup()

    def run_gate(self):
        return subprocess.run(["bash", str(ROOT / "scripts/quality-gates/test_ios_unit.sh")],
                              env=self.environment, capture_output=True, text=True)

    def test_zero_selected_tests_is_failure_despite_successful_xcode_exit(self):
        self.environment["KURO_FAKE_TEST_LOG"] = "** TEST SUCCEEDED **"
        result = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertIn("no selected cases executed", result.stdout)

    def test_real_uuid_and_unique_results_with_nonzero_execution(self):
        self.environment["KURO_FAKE_TEST_LOG"] = "Test case 'LibraryHTTPContractTests/progress()' passed"
        for _ in range(2):
            result = self.run_gate()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = [json.loads(row) for row in (self.work / "calls.jsonl").read_text().splitlines()]
        destinations = [call[call.index("-destination") + 1] for call in calls]
        self.assertEqual(destinations, ["platform=iOS Simulator,id=22222222-2222-2222-2222-222222222222"] * 2)
        paths = [call[call.index("-resultBundlePath") + 1] for call in calls]
        self.assertNotEqual(paths[0], paths[1])
        self.assertTrue(all(call[call.index("-only-testing:KuroTests")] for call in calls))

    def test_failed_xcode_exit_cannot_pass_even_after_a_passing_case(self):
        self.environment["KURO_FAKE_TEST_LOG"] = "Test case 'LibraryHTTPContractTests/progress()' passed"
        self.environment["KURO_FAKE_XCODE_EXIT"] = "65"
        self.assertEqual(self.run_gate().returncode, 1)

    def test_missing_required_simulator_refuses_xcode_execution(self):
        self.environment["KURO_FAKE_DEVICES"] = '{"devices": {}}'
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No available iPhone 17 Pro simulator", result.stderr)
        self.assertFalse((self.work / "calls.jsonl").exists())

    def test_named_suite_mode_still_rejects_missing_suite(self):
        log = self.work / "selected.log"
        log.write_text("Test case 'PresentSuite/example()' passed\n")
        helper = ROOT / "scripts/quality-gates/ios_verify_helpers.sh"
        command = f"source {shlex.quote(str(helper))}; kuro_verify_selected_ios_tests {shlex.quote(str(log))} PresentSuite MissingSuite"
        result = subprocess.run(["bash", "-c", command], env=self.environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MissingSuite", result.stderr)


if __name__ == "__main__":
    unittest.main()
