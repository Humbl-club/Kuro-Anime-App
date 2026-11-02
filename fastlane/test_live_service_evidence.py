"""Offline validator/partition tests. These files never exercise real services."""
import copy
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
spec = importlib.util.spec_from_file_location("live_evidence", HERE / "check_live_service_evidence.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class LiveEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kuro-live-evidence-")
        self.path = Path(self.temporary.name)
        self.now = datetime.now(timezone.utc) - timedelta(seconds=1)
        self.uid = "11111111-1111-4111-8111-111111111111"
        self.outsider = "33333333-3333-4333-8333-333333333333"
        self.club = "22222222-2222-4222-8222-222222222222"
        self.common = {"target": gate.ORIGIN, "status": "PASS", "exitCode": 0,
                       "runId": self.now.strftime("%Y%m%dT%H%M%SZ") + "-abcdef12",
                       "resources": {"accounts": [{"userId": self.uid}]},
                       "cleanup": [{"type": "account", "userId": self.uid, "status": "PASS"}]}
        self.candidate = {"schema": 1, "stage": "prepared", "snapshot": {"sha256": "a" * 64},
                          "prepared_at": (self.now - timedelta(minutes=1)).isoformat(), "root": str(self.path)}
        self.deployment = {"project_ref": gate.PROJECT, "candidate_sha256": "a" * 64,
                           "observed_at": self.now.isoformat(), "migrations": ["20261005180000"],
                           "functions": {"delete-account": {"version": 9}},
                           "effective_user_lists": {"reloptions": ["security_invoker=true"],
                                                   "authenticated_grants": ["SELECT"], "anon_grants": ["SELECT"]}}
        self.reports = {name: copy.deepcopy(self.common) for name in gate.REPORTS}
        self.reports["journal"].update({"apply": "PASS", "undo": "PASS", "tables": {
            name: {"ownerSelect": "PASS", "outsiderSelect": "PASS", "unchanged": True,
                   "insert": "42501", "update": "42501", "delete": "42501"}
            for name in ("import_sessions", "import_session_items")}})
        realtime = self.reports["realtime"]
        realtime.update({"memberEvents": 1, "outsiderEvents": 0, "delivery": "PASS",
                         "membershipDelivery": "PASS", "revocation": "PASS", "negativeObservationMs": 100})
        realtime["resources"]["clubs"] = [self.club]
        realtime["cleanup"].append({"type": "club", "clubId": self.club, "status": "PASS"})
        self.reports["auth_api"].update({
            "authResponses": {key: {"status": 200, "user": {"id": self.uid}} for key in ("signup", "passwordSignin", "refresh", "restoredUser")},
            "apiResponses": {"ownerProfile": {"status": 200, "rows": [{"id": self.uid}]},
                             "anonymousProfile": {"status": 200, "rows": []}, "outsiderUpdate": {"status": 200, "actorUserId": self.outsider, "rows": []},
                             "ownerBefore": {"status": 200, "rows": [{"id": self.uid}]}, "ownerAfter": {"status": 200, "rows": [{"id": self.uid}]},
                             "structuredError": {"status": 403, "body": {"code": "42501", "details": "DENIED"}}}})
        self.reports["auth_api"]["authResponses"]["outsiderSession"] = {"status": 200, "user": {"id": self.outsider}}
        self.reports["auth_api"]["resources"]["accounts"].append({"userId": self.outsider})
        self.reports["auth_api"]["cleanup"].append({"type": "account", "userId": self.outsider, "status": "PASS"})
        stamp = lambda seconds: (self.now + timedelta(seconds=seconds)).isoformat()
        obj = self.uid + "/created.jpg"
        self.reports["account_storage"]["resources"]["objects"] = [obj]
        self.reports["account_storage"]["storageResponses"] = {
            "deleteAccount": {"status": 200, "userId": self.uid, "body": {"success": True}, "startedAt": stamp(-8), "endedAt": stamp(-6), "startedNs": "20", "endedNs": "40", "tokenSha256": "b" * 64},
            "overlappingUpload": {"status": 200, "startedAt": stamp(-9), "endedAt": stamp(-7), "startedNs": "10", "endedNs": "30", "tokenSha256": "b" * 64},
            "oldTokenUpload": {"status": 403, "startedAt": stamp(-5), "startedNs": "50", "tokenSha256": "b" * 64},
            "deletedUserRead": {"status": 401}, "adminAuthRead": {"status": 404, "userId": self.uid},
            "adminObjects": {"status": 200, "bucket": "media", "prefix": self.uid + "/", "rows": []}, "originReads": {obj: {"status": 404}}}
        self.prepare_backend()
        self.prepare_protocol()

    def tearDown(self):
        self.temporary.cleanup()

    def reference(self, name, value):
        path = self.path / name
        path.write_text(json.dumps(value))
        return {"path": name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

    def bundle(self):
        (self.path / "candidate.json").write_text(json.dumps(self.candidate))
        self.bundle_value = {"schema": 1, "candidate_sha256": self.candidate["snapshot"]["sha256"],
                             "deployment": self.reference("deployment.json", self.deployment),
                             "reports": {name: self.reference(name + ".json", report) for name, report in self.reports.items()}}
        (self.path / "bundle.json").write_text(json.dumps(self.bundle_value))

    def prepare_backend(self):
        files = []
        inventory = {"schema": 1, "project_ref": gate.PROJECT, "migrations": [], "functions": {}}
        def source(relative, content):
            path = self.path / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
            sha = hashlib.sha256(path.read_bytes()).hexdigest()
            files.append([relative, 0o644, sha])
            return {"path": relative, "sha256": sha}
        migration = source("supabase/prepared-migrations/20261005180000_fixture.sql", "select 1;")
        migration["id"] = "20261005180000"
        inventory["migrations"] = [migration]
        self.deployment["migrations"] = [{"id": migration["id"], "sha256": migration["sha256"]}]
        self.deployment["functions"] = {}
        for slug in ("concierge-apply", "concierge-undo", "delete-account"):
            item = source(f"supabase/functions/{slug}/index.ts", "export const handler = 1;")
            inventory["functions"][slug] = {"files": [item]}
            self.deployment["functions"][slug] = {"version": 9, "files": [item]}
        source("fastlane/backend_release_manifest.json", json.dumps(inventory))
        self.candidate["snapshot"]["files"] = files

    def prepare_protocol(self):
        def add(report, path, method, response, actor=None, request=None, status=200):
            report.setdefault("protocol", []).append({"path": path, "method": method, "actorUserId": actor,
                "requestBody": request, "responseBody": response, "status": status, "credentialSha256": "b" * 64})
        journal = self.reports["journal"]
        session = "44444444-4444-4444-8444-444444444444"
        journal["sessionId"] = session
        add(journal, "/functions/v1/concierge-apply", "POST", {"sessionId": session, "undoable": True}, self.uid)
        for table in ("import_sessions", "import_session_items"):
            row = {"id": session, "session_id": session}
            add(journal, "/rest/v1/" + table, "GET", [row], self.uid)
            add(journal, "/rest/v1/" + table, "GET", [], self.outsider)
            for method in ("POST", "PATCH", "DELETE"):
                add(journal, "/rest/v1/" + table, method, {"code": "42501"}, self.uid, status=403)
            add(journal, "/rest/v1/" + table, "GET", [row], self.uid)
        add(journal, "/functions/v1/concierge-undo", "POST", {"status": "undone"}, self.uid, {"sessionId": session})
        rt = self.reports["realtime"]
        rt["subscriberIdentities"] = {"owner": self.uid, "member": self.outsider, "outsider": "55555555-5555-4555-8555-555555555555"}
        for role in ("member", "outsider"):
            identity = rt["subscriberIdentities"][role]
            rt["resources"]["accounts"].append({"userId": identity})
            rt["cleanup"].append({"type": "account", "userId": identity, "status": "PASS"})
        rt["rls"] = {"afterRevision": 2}
        rt["clubId"] = self.club
        rt["finalRevision"] = 3
        def event(role, rev, table="club_activity_signals", state=None):
            row = {"club_id": self.club, "revision": rev}
            if state: row.update({"state": state, "user_id": rt["subscriberIdentities"][role]})
            return {"observedTable": table, "subscriberUserId": rt["subscriberIdentities"][role], "observedFilter": "user_id=eq." + rt["subscriberIdentities"][role], "new": row}
        rt["signalEvents"] = {"member": [event("member", 2)], "owner": [event("owner", 2), event("owner", 3)],
                             "outsider": [], "membership": [event("member", 3, "club_membership_signals", "removed")]}
        for role in ("member", "outsider"):
            add(rt, "/rest/v1/club_activity_signals", "GET", [], rt["subscriberIdentities"][role])
        api = self.reports["auth_api"]
        add(api, "/auth/v1/signup", "POST", {"user": {"id": self.uid}})
        add(api, "/auth/v1/user", "GET", {"id": self.uid})
        add(api, "/auth/v1/user", "GET", {"id": self.outsider}, self.outsider)
        for grant in ("password", "refresh_token"):
            add(api, "/auth/v1/token?grant_type=" + grant, "POST", {"user": {"id": self.uid}})
        add(api, "/rest/v1/profiles", "GET", [{"id": self.uid}], self.uid)
        add(api, "/rest/v1/profiles", "GET", [])
        add(api, "/rest/v1/profiles", "PATCH", [], self.outsider)
        add(api, "/rest/v1/profiles", "GET", [{"id": self.uid}], self.uid)
        add(api, "/rest/v1/profiles", "GET", {"code": "42501", "details": "DENIED"}, self.uid, status=403)
        storage = self.reports["account_storage"]
        rows = storage["storageResponses"]
        seed = self.uid + "/created.jpg"
        rows["initialUpload"] = {"status": 200, "path": seed, "bucket": "media", "userId": self.uid}
        rows["originBefore"] = {"status": 200, "path": seed}
        for key, path in (("overlappingUpload", self.uid + "/race.png"), ("oldTokenUpload", self.uid + "/after.png")):
            rows[key].update({"path": path, "bucket": "media", "userId": self.uid})
            storage["resources"]["objects"].append(path)
            rows["originReads"][path] = {"status": 404}
        for upload in (rows["initialUpload"], rows["overlappingUpload"], rows["oldTokenUpload"]):
            add(storage, "/storage/v1/object/media/" + upload["path"], "POST", {}, self.uid, status=upload["status"])
        add(storage, "/functions/v1/delete-account", "POST", {"success": True}, self.uid)
        add(storage, "/storage/v1/object/public/media/" + seed, "GET", None)
        add(storage, "/auth/v1/user", "GET", {}, self.uid, status=401)
        add(storage, "/auth/v1/admin/users/" + self.uid, "GET", {}, status=404)
        storage["protocol"][-1]["administrative"] = True
        add(storage, "/storage/v1/object/list/media", "POST", [], request={"prefix": self.uid + "/"})
        storage["protocol"][-1]["administrative"] = True
        for path in storage["resources"]["objects"]:
            add(storage, "/storage/v1/object/public/media/" + path, "GET", None, status=404)
        for report in self.reports.values():
            report["requestCount"] = len(report["protocol"])

    def validate(self):
        return gate.validate(self.path / "candidate.json", self.path / "bundle.json")

    def test_complete_concrete_protocol_evidence_is_accepted(self):
        self.bundle()
        self.validate()

    def test_metadata_only_pass_and_missing_probe_do_not_qualify(self):
        self.reports["account_storage"] = copy.deepcopy(self.common)
        self.bundle()
        with self.assertRaises((KeyError, ValueError)):
            self.validate()
        del self.reports["account_storage"]
        self.bundle()
        with self.assertRaises(gate.Blocked):
            self.validate()

    def test_stale_candidate_or_wrong_project_is_rejected(self):
        self.bundle()
        self.candidate["snapshot"]["sha256"] = "f" * 64
        (self.path / "candidate.json").write_text(json.dumps(self.candidate))
        with self.assertRaises(ValueError):
            self.validate()
        self.deployment["project_ref"] = "other"
        self.bundle()
        with self.assertRaises(ValueError):
            self.validate()

    def test_old_backend_source_and_missing_critical_protocol_cannot_qualify(self):
        self.deployment["functions"]["delete-account"]["files"] = []
        self.bundle()
        with self.assertRaises(ValueError):
            self.validate()
        self.prepare_backend()
        report = self.reports["account_storage"]
        report["protocol"] = [row for row in report["protocol"] if row["path"] != "/functions/v1/delete-account"]
        report["requestCount"] = len(report["protocol"])
        self.bundle()
        with self.assertRaises(ValueError):
            self.validate()

    def test_fixture_identity_and_changed_artifact_are_rejected(self):
        self.reports["journal"]["runId"] = "offline"
        self.bundle()
        with self.assertRaises(ValueError):
            self.validate()
        self.reports["journal"]["runId"] = self.common["runId"]
        self.bundle()
        (self.path / "journal.json").write_text("{}")
        with self.assertRaises(ValueError):
            self.validate()

    def test_revision_only_realtime_and_public_storage_cannot_pass(self):
        self.reports["realtime"]["memberEvents"] = 0
        self.bundle()
        with self.assertRaises(ValueError):
            self.validate()
        self.reports["realtime"]["memberEvents"] = 1
        obj = self.uid + "/created.jpg"
        self.reports["account_storage"]["storageResponses"]["originReads"][obj]["status"] = 200
        self.bundle()
        with self.assertRaises(ValueError):
            self.validate()

    def test_same_token_post_deletion_upload_and_physical_cleanup_are_mandatory(self):
        self.reports["account_storage"]["storageResponses"]["oldTokenUpload"]["status"] = 200
        self.bundle()
        with self.assertRaises(ValueError):
            self.validate()
        self.reports["account_storage"]["storageResponses"]["oldTokenUpload"]["status"] = 403
        self.reports["account_storage"]["storageResponses"]["adminObjects"]["rows"] = [{"name": "leftover"}]
        self.bundle()
        with self.assertRaises(ValueError):
            self.validate()


class LocalSQLPartitionTests(unittest.TestCase):
    def run_summary(self, **values):
        script = (ROOT / "scripts/db/run_local_db_tests.sh").read_text()
        actual_summary = script[script.index("total_blocked=$(("):]
        defaults = {"run_tests": 1, "n_files": 1, "n_ok": 5, "n_find": 0, "n_live_required": 4,
                    "n_blocked": 0, "n_scopes_blocked": 0, "n_files_blocked": 0,
                    "bf_pass": 1, "bf_fail": 0, "st_pass": 1, "st_fail": 0, "fail": 0}
        defaults.update(values)
        prefix = "prepared_failed=''\n" + "\n".join(f"{key}={value}" for key, value in defaults.items()) + "\n"
        return subprocess.run(["bash", "-c", prefix + actual_summary], capture_output=True, text=True)

    def test_live_requirement_is_not_a_local_sql_pass_claim(self):
        result = self.run_summary()
        self.assertEqual(result.returncode, 0)
        self.assertIn("4 requirement(s), NOT PROVEN", result.stdout)
        self.assertIn("PASS (local SQL only; no live-service acceptance)", result.stdout)

    def test_missing_sql_scope_dblink_failure_and_no_assertions_stay_nonpassing(self):
        self.assertEqual(self.run_summary(n_scopes_blocked=1).returncode, 4)
        self.assertEqual(self.run_summary(n_blocked=1).returncode, 4)
        self.assertEqual(self.run_summary(fail=1).returncode, 1)
        self.assertEqual(self.run_summary(n_ok=0).returncode, 1)


if __name__ == "__main__":
    unittest.main()
