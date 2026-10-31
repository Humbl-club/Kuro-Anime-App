"""Read-only release evidence gate. Missing real proof is BLOCKED, never a waiver."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys

PROJECT = "bkdifromsqxkndnllmdj"
ORIGIN = f"https://{PROJECT}.supabase.co"
REPORTS = ("journal", "realtime", "auth_api", "account_storage")


class Blocked(Exception):
    pass


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def load(path):
    file = Path(path)
    if not file.is_file():
        raise Blocked(f"Missing evidence: {file}")
    require(file.stat().st_size <= 2_000_000, "Evidence must be sanitized and bounded")
    return json.loads(file.read_text())


def referenced(reference, base):
    path = (base / reference["path"]).resolve()
    data = load(path)
    require(hashlib.sha256(path.read_bytes()).hexdigest() == reference["sha256"], "Referenced evidence changed")
    return data


def instant(value):
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(parsed.tzinfo is not None, "Evidence timestamps must have a timezone")
    return parsed


def denied(response):
    status = response["status"]
    body = response.get("body") or response.get("responseBody") or {}
    return status in (401, 403) or (status == 400 and
        (str(body.get("statusCode")) in ("401", "403") or body.get("code") == "42501"))


def requests(report, path, method=None, actor=None):
    return [row for row in report["protocol"] if row.get("path", "").split("?")[0] == path
            and (method is None or row["method"] == method) and (actor is None or row.get("actorUserId") == actor)]


def validate_backend_inventory(candidate, deployment):
    root = Path(candidate["root"]).resolve()
    inventory_path = Path(os.environ.get("KURO_BACKEND_RELEASE_MANIFEST", root / "fastlane/backend_release_manifest.json")).resolve()
    inventory = load(inventory_path)
    relative = str(inventory_path.relative_to(root))
    pinned = {row[0]: row[2] for row in candidate["snapshot"]["files"] if len(row) == 3}
    require(pinned.get(relative) == hashlib.sha256(inventory_path.read_bytes()).hexdigest(), "Backend release inventory is not a frozen candidate input")
    require(inventory.get("schema") == 1 and inventory.get("project_ref") == PROJECT, "Unexpected backend release inventory")
    observed_migrations = {row["id"]: row["sha256"] for row in deployment["migrations"]}
    require(inventory.get("migrations"), "Intended forward migration inventory is missing")
    for migration in inventory["migrations"]:
        require(pinned.get(migration["path"]) == migration["sha256"] and observed_migrations.get(migration["id"]) == migration["sha256"], "Intended migration/source deployment receipt mismatch")
    require({"concierge-apply", "concierge-undo", "delete-account"}.issubset(inventory.get("functions", {})), "Critical backend function inventory is missing")
    for slug, required in inventory["functions"].items():
        expected = {row["path"]: row["sha256"] for row in required["files"]}
        require(expected and f"supabase/functions/{slug}/index.ts" in expected, "Function entrypoint is not inventoried")
        require(all(pinned.get(path) == digest for path, digest in expected.items()), "Intended function file differs from frozen source")
        closure = set()
        pending = [f"supabase/functions/{slug}/index.ts"]
        while pending:
            path = pending.pop()
            if path in closure:
                continue
            closure.add(path)
            content = (root / path).read_text()
            for specifier in re.findall(r'''(?:from\s*|import\s*\(\s*|import\s*)["'](\.[^"']+)["']''', content):
                dependency = str((root / path).parent.joinpath(specifier).resolve().relative_to(root))
                require(dependency in pinned, "Unpinned local backend dependency")
                pending.append(dependency)
        require(closure.issubset(expected), "Backend inventory omits a local production dependency")
        observed = deployment["functions"].get(slug, {})
        require(isinstance(observed.get("version"), int) and observed["version"] > 0, "Required deployed function version is unavailable")
        actual = {row["path"]: row["sha256"] for row in observed.get("files", [])}
        require(all(actual.get(path) == digest for path, digest in expected.items()), "Observed deployed function source differs from intended candidate")


def validate_report_common(report, prepared):
    require(report.get("target") == ORIGIN, "Probe used an unapproved target")
    if report.get("status") == "BLOCKED":
        raise Blocked("Probe or required cleanup evidence is unavailable")
    require(report.get("status") == "PASS" and report.get("exitCode") == 0, "Probe or cleanup did not pass")
    run = re.fullmatch(r"(\d{8}T\d{6}(?:\d{3})?Z)-[0-9a-f]{8}", report.get("runId", ""))
    require(run is not None, "Missing real timestamped probe run identity")
    stamp = run.group(1)
    observed = datetime.strptime(stamp, "%Y%m%dT%H%M%S%fZ" if len(stamp) > 16 else "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
    require(prepared <= observed <= datetime.now(timezone.utc), "Probe predates this candidate or has a future timestamp")
    accounts = report.get("resources", {}).get("accounts", [])
    require(0 < len(accounts) <= 5, "Disposable account inventory is required and bounded")
    identities = {row["userId"] for row in accounts}
    require(len(identities) == len(accounts) and all(re.fullmatch(r"[0-9a-f-]{36}", uid) for uid in identities), "Invalid disposable account identity")
    cleanup = report.get("cleanup", [])
    require(cleanup and all(row.get("status") == "PASS" for row in cleanup), "Cleanup failed or is unavailable")
    require({row.get("userId") for row in cleanup if row.get("type") == "account"} == identities, "Not every disposable account has cleanup evidence")
    serialized = json.dumps(report)
    require(not re.search(r'"(?:access_token|refresh_token|service_role_key|Authorization|password)"\s*:', serialized, re.I), "Do not store credentials in release evidence")
    protocol = report.get("protocol", [])
    require(0 < len(protocol) == report.get("requestCount") <= 1000, "Actual bounded protocol trace is required")


def validate_journal(report):
    require(report.get("apply") == report.get("undo") == "PASS", "Real Apply/Undo proof is missing")
    apply = requests(report, "/functions/v1/concierge-apply", "POST")
    undo = requests(report, "/functions/v1/concierge-undo", "POST")
    require(len(apply) == len(undo) == 1 and apply[0]["status"] == undo[0]["status"] == 200, "Actual Apply/Undo responses missing")
    session = apply[0]["responseBody"].get("sessionId")
    require(session == report.get("sessionId") == undo[0]["requestBody"].get("sessionId") and
            apply[0]["responseBody"].get("undoable") is True and undo[0]["responseBody"].get("status") == "undone", "Apply/Undo session correlation failed")
    owner = apply[0]["actorUserId"]
    for table in ("import_sessions", "import_session_items"):
        row = report.get("tables", {}).get(table, {})
        require(row.get("ownerSelect") == row.get("outsiderSelect") == "PASS" and row.get("unchanged") is True,
                f"Missing real owner/outsider/unchanged proof: {table}")
        require(all(row.get(action) == "42501" for action in ("insert", "update", "delete")), "A zero-row write is not a denied write")
        reads = requests(report, "/rest/v1/" + table, "GET", owner)
        other = [item for item in requests(report, "/rest/v1/" + table, "GET") if item.get("actorUserId") != owner]
        require(len(reads) >= 2 and reads[0]["responseBody"] == reads[-1]["responseBody"] and
                len(reads[0]["responseBody"]) == 1 and other and all(item["status"] == 200 and item["responseBody"] == [] for item in other), "Actual scoped journal read/unchanged rows missing")
        actual = reads[0]["responseBody"][0]
        require((actual["id"] == session if table == "import_sessions" else actual["session_id"] == session), "Journal rows do not belong to actual Apply session")
        for method in ("POST", "PATCH", "DELETE"):
            writes = requests(report, "/rest/v1/" + table, method, owner)
            require(len(writes) == 1 and writes[0]["status"] == 403 and writes[0]["responseBody"].get("code") == "42501", "Actual denied journal write response missing")


def validate_realtime(report):
    require(report.get("memberEvents", 0) > 0 and report.get("outsiderEvents") == 0, "Actual correlated Realtime delivery is required")
    require(all(report.get(key) == "PASS" for key in ("delivery", "membershipDelivery", "revocation")), "Membership delivery/revocation proof is missing")
    require(report.get("negativeObservationMs", 0) > 0, "A bounded negative observation interval is required")
    clubs = set(report.get("resources", {}).get("clubs", []))
    require(clubs and {row.get("clubId") for row in report["cleanup"] if row.get("type") == "club"} == clubs,
            "Physical club cleanup proof is required")
    roles = report["subscriberIdentities"]
    identities = {row["userId"] for row in report["resources"]["accounts"]}
    require(len(set(roles.values())) == 3 and set(roles.values()).issubset(identities), "Three distinct disposable Realtime identities are required")
    events = report["signalEvents"]
    club = report["clubId"]
    revision = report["rls"]["afterRevision"]
    final = report["finalRevision"]
    require(club in clubs and final > revision, "Actual signal revisions are missing")
    for role in ("member", "owner"):
        require(any(event.get("observedTable") == "club_activity_signals" and event.get("subscriberUserId") == roles[role]
                    and event.get("table", "club_activity_signals") == "club_activity_signals"
                    and event.get("new", {}).get("club_id") == club and int(event["new"].get("revision", 0)) >= revision
                    and set(event["new"]).issubset({"club_id", "revision", "changed_at"}) for event in events[role]), "Actual activity signal event correlation is missing")
    require(not events["outsider"] and not any(int(event.get("new", {}).get("revision", 0)) >= final for event in events["member"]), "Unauthorized signal delivery occurred")
    require(any(int(event.get("new", {}).get("revision", 0)) >= final for event in events["owner"]), "Post-revocation authorized positive control is missing")
    require(any(event.get("observedTable") == "club_membership_signals" and event.get("subscriberUserId") == roles["member"]
                and event.get("new", {}).get("club_id") == club and event["new"].get("state") == "removed"
                and event["new"].get("user_id") == roles["member"].lower() and event.get("observedFilter") == "user_id=eq." + roles["member"].lower() for event in events["membership"]), "Actual membership signal event missing")
    selects = requests(report, "/rest/v1/club_activity_signals", "GET")
    require(any(row.get("actorUserId") == roles["outsider"] and row["status"] == 200 and row["responseBody"] == [] for row in selects) and
            any(row.get("actorUserId") == roles["member"] and row["status"] == 200 and row["responseBody"] == [] for row in selects), "Actual outsider/revoked-member API denial is missing")


def validate_auth_api(report):
    # Sanitized protocol responses, not a collection of self-awarded PASS labels.
    auth = report["authResponses"]
    uid = auth["signup"]["user"]["id"]
    identities = {row["userId"] for row in report["resources"]["accounts"]}
    require(uid in identities and all(auth[key]["user"]["id"] == uid for key in ("passwordSignin", "refresh", "restoredUser")), "GoTrue sign-in/refresh/restore identities disagree")
    outsider = auth["outsiderSession"]["user"]["id"]
    require(outsider in identities and outsider != uid, "A real authenticated outsider is required")
    require(all(auth[key]["status"] == 200 for key in ("signup", "passwordSignin", "refresh", "restoredUser", "outsiderSession")), "GoTrue responses did not succeed")
    api = report["apiResponses"]
    require(api["ownerProfile"]["status"] == 200 and api["ownerProfile"]["rows"] == [{"id": uid}], "Owner profile read is missing")
    require((api["anonymousProfile"]["status"] == 200 or denied(api["anonymousProfile"])) and api["anonymousProfile"]["rows"] == [] and
            (api["outsiderUpdate"]["status"] == 200 or denied(api["outsiderUpdate"])) and api["outsiderUpdate"]["actorUserId"] == outsider and api["outsiderUpdate"]["rows"] == [],
            "Denied profile operation exposed or changed another account")
    require(api["ownerBefore"]["status"] == api["ownerAfter"]["status"] == 200 and
            api["ownerBefore"]["rows"] and api["ownerAfter"]["rows"] == api["ownerBefore"]["rows"], "Denied update changed owner data")
    error = api["structuredError"]
    require(400 <= error["status"] < 500 and "details" in error["body"] and
            (error["body"]["details"] is None or isinstance(error["body"]["details"], str)) and error["body"].get("code"), "Real PostgREST details/error code shape is missing")
    protocol = report["protocol"]
    signup = requests(report, "/auth/v1/signup", "POST")
    require(any(row["status"] == auth["signup"]["status"] and row["responseBody"].get("user", {}).get("id") == uid for row in signup), "Actual signup identity response missing")
    user_reads = requests(report, "/auth/v1/user", "GET")
    for key in ("restoredUser", "outsiderSession"):
        require(any(row["status"] == auth[key]["status"] and (row["responseBody"].get("id") or row["responseBody"].get("user", {}).get("id")) == auth[key]["user"]["id"] for row in user_reads if isinstance(row.get("responseBody"), dict)), "Actual restored/outsider identity response missing")
    for grant, key in (("password", "passwordSignin"), ("refresh_token", "refresh")):
        matching = [row for row in protocol if row.get("path") == "/auth/v1/token?grant_type=" + grant and row["method"] == "POST"]
        require(len(matching) == 1 and matching[0]["status"] == auth[key]["status"] and matching[0]["responseBody"].get("user", {}).get("id") == uid, "Actual sign-in/refresh protocol missing")
    profile_path = "/rest/v1/profiles"
    profile_reads = requests(report, profile_path, "GET")
    require(any(row.get("actorUserId") == uid and row["status"] == 200 and row["responseBody"] == api["ownerProfile"]["rows"] for row in profile_reads), "Actual owner profile protocol missing")
    require(any(row.get("actorUserId") is None and (row["status"] == 200 and row["responseBody"] == [] or denied(row)) for row in profile_reads), "Actual anonymous denial protocol missing")
    unchanged_reads = [row for row in profile_reads if row.get("actorUserId") == uid and row["status"] == 200 and row["responseBody"] == api["ownerBefore"]["rows"]]
    require(len(unchanged_reads) >= 2, "Actual before/after owner rows missing")
    updates = requests(report, profile_path, "PATCH", outsider)
    require(len(updates) == 1 and updates[0]["status"] == api["outsiderUpdate"]["status"] and
            (updates[0]["responseBody"] == [] or denied(updates[0])), "Actual outsider update denial missing")
    require(any(row["status"] == error["status"] and row["responseBody"] == error["body"] for row in profile_reads), "Actual PostgREST error body missing")


def validate_storage(report):
    rows = report["storageResponses"]
    require(rows["deleteAccount"]["status"] == 200 and rows["deleteAccount"]["body"].get("success") is True, "App deletion route did not succeed")
    race = rows["overlappingUpload"]
    delete = rows["deleteAccount"]
    require(race["status"] in (200, 201) or denied(race), "Concurrent upload had an unexpected failure")
    require(int(race["startedNs"]) < int(delete["startedNs"]) < int(race["endedNs"]), "Upload/deletion did not overlap")
    require(denied(rows["oldTokenUpload"]) and rows["deletedUserRead"]["status"] in (401, 403), "Old-token upload or deleted-account access was accepted")
    require(int(rows["oldTokenUpload"]["startedNs"]) > int(delete["endedNs"]), "Old-token upload was not attempted after deletion")
    require(race["tokenSha256"] == rows["oldTokenUpload"]["tokenSha256"] == delete["tokenSha256"] and re.fullmatch(r"[0-9a-f]{64}", race["tokenSha256"]), "The race must use the same original credential")
    require(rows["adminAuthRead"]["status"] == 404 and rows["adminObjects"]["status"] == 200 and rows["adminObjects"]["rows"] == [], "Administrative physical cleanup is missing")
    objects = report["resources"].get("objects", [])
    owners = {row["userId"] for row in report["resources"]["accounts"]}
    require(objects and all(path.split("/")[0] in owners for path in objects), "Only recorded disposable account objects may be probed")
    owner = delete["userId"]
    require(owner in owners and all(path.startswith(owner + "/") for path in objects), "Object/deletion identities disagree")
    seed = rows["initialUpload"]; before = rows["originBefore"]
    require(seed["status"] in (200, 201) and seed["path"] == before["path"] and before["status"] == 200 and seed["path"] in objects, "Actual readable seed object is required")
    for upload in (seed, race, rows["oldTokenUpload"]):
        require(upload["path"] in objects and upload["bucket"] == "media" and upload["userId"] == owner, "Upload object/account scope is inconsistent")
        raw = requests(report, "/storage/v1/object/media/" + upload["path"], "POST", owner)
        require(len(raw) == 1 and raw[0]["status"] == upload["status"], "Actual upload protocol response missing")
        require(raw[0].get("responseBody") == upload.get("body", {}), "Upload response body differs from actual protocol")
        if upload is not seed:
            require(raw[0]["credentialSha256"] == upload["tokenSha256"], "Actual old credential does not match upload")
    require(rows["adminObjects"]["bucket"] == "media" and rows["adminObjects"]["prefix"] == owner + "/" and rows["adminAuthRead"]["userId"] == owner,
            "Administrative cleanup must inspect the exact deleted identity and media prefix")
    deletion_calls = requests(report, "/functions/v1/delete-account", "POST", owner)
    require(len(deletion_calls) == 1 and deletion_calls[0]["status"] == delete["status"] and deletion_calls[0]["responseBody"] == delete["body"] and deletion_calls[0]["credentialSha256"] == delete["tokenSha256"], "Actual same-credential deletion response missing")
    require(any(row["status"] == before["status"] for row in requests(report, "/storage/v1/object/public/media/" + seed["path"], "GET")), "Actual readable seed origin response missing")
    require(any(row["status"] == rows["deletedUserRead"]["status"] and row["credentialSha256"] == delete["tokenSha256"] for row in requests(report, "/auth/v1/user", "GET", owner)), "Actual old-credential GoTrue rejection missing")
    require(any(row.get("administrative") is True and row["status"] == rows["adminAuthRead"]["status"] for row in requests(report, "/auth/v1/admin/users/" + owner, "GET")), "Actual exact administrative Auth absence response missing")
    require(any(row.get("administrative") is True and row["requestBody"].get("prefix") == owner + "/" and row["status"] == rows["adminObjects"]["status"] and row["responseBody"] == rows["adminObjects"]["rows"] for row in requests(report, "/storage/v1/object/list/media", "POST")), "Actual exact administrative media absence response missing")
    origins = rows["originReads"]
    for path, expected in origins.items():
        require(any(row["status"] == expected["status"] and row.get("responseBody") == expected.get("body") for row in requests(report, "/storage/v1/object/public/media/" + path, "GET")), "Actual public-origin absence response missing")
    require(set(origins) == set(objects) and all(row["status"] == 404 or
            (row["status"] == 400 and str(row.get("body", {}).get("statusCode")) == "404") for row in origins.values()),
            "A recorded origin object is still publicly readable or unverified")


def validate(candidate_path, evidence_path):
    candidate = load(candidate_path)
    bundle = load(evidence_path)
    require(candidate.get("stage") in ("prepared", "verified", "archived", "processed"), "No frozen candidate")
    require(bundle.get("schema") == 1 and bundle.get("candidate_sha256") == candidate["snapshot"]["sha256"], "Evidence belongs to a different candidate")
    prepared = instant(candidate["prepared_at"])
    base = Path(evidence_path).resolve().parent
    deployment = referenced(bundle["deployment"], base)
    require(deployment.get("project_ref") == PROJECT and deployment.get("candidate_sha256") == bundle["candidate_sha256"], "Deployment identity does not match candidate/project")
    require(prepared <= instant(deployment["observed_at"]) <= datetime.now(timezone.utc), "Deployment must be freshly observed for this candidate")
    require(deployment.get("migrations") and deployment.get("functions"), "Effective deployed migration/function identities are missing")
    validate_backend_inventory(candidate, deployment)
    view = deployment["effective_user_lists"]
    require("security_invoker=true" in view["reloptions"] and "SELECT" in view["authenticated_grants"] and "SELECT" in view["anon_grants"], "Effective user_lists security/grants differ from the reviewed contract")
    for name, checker in zip(REPORTS, (validate_journal, validate_realtime, validate_auth_api, validate_storage)):
        if name not in bundle.get("reports", {}):
            raise Blocked(f"Missing real {name} report; fixture/source proof is not accepted")
        report = referenced(bundle["reports"][name], base)
        validate_report_common(report, prepared)
        checker(report)
    return bundle


def main():
    candidate = os.environ.get("KURO_RELEASE_CANDIDATE_FILE")
    evidence = os.environ.get("KURO_LIVE_SERVICE_EVIDENCE")
    if not candidate or not evidence:
        print("live-services: BLOCKED — frozen candidate and real service evidence are required")
        return 4
    try:
        validate(candidate, evidence)
    except Blocked as error:
        print(f"live-services: BLOCKED — {error}")
        return 4
    except (ValueError, KeyError, TypeError, OSError) as error:
        print(f"live-services: FAIL — {error}")
        return 1
    print("live-services: PASS (pinned live protocol, deployment and cleanup evidence; installed-native proof remains separate)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
