#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
APP_SWIFT_COUNT = len(list((ROOT / "Kuro").rglob("*.swift")))
# Local Swift package(s) (Packages/*/Sources and Packages/*/Tests). Absent until the first package target lands.
PACKAGES_DIR = ROOT / "Packages"
PACKAGE_SWIFT_COUNT = (
    len([p for p in PACKAGES_DIR.rglob("*.swift") if ".build" not in p.parts])
    if PACKAGES_DIR.exists()
    else 0
)
PACKAGE_STATE_CLAUSE = (
    f"; {PACKAGE_SWIFT_COUNT} package Swift files in `/Packages`" if PACKAGE_SWIFT_COUNT else ""
)
PACKAGE_PLAIN_CLAUSE = (
    f", {PACKAGE_SWIFT_COUNT} package Swift files" if PACKAGE_SWIFT_COUNT else ""
)
MIGRATION_COUNT = len(list((ROOT / "supabase" / "migrations").glob("*.sql")))

CURRENT_APP_STATE = (ROOT / "CURRENT_APP_STATE.md").read_text()
CURRENT_APP_STATE_PLAIN = (ROOT / "CURRENT_APP_STATE_PLAIN.md").read_text()
AGENTS = (ROOT / "AGENTS.md").read_text()
SQL_REPORT = (ROOT / "archive" / "SQL_COMPATIBILITY_REPORT.md").read_text()
KNOWLEDGE_INDEX = (ROOT / "KNOWLEDGE" / "INDEX.md").read_text()
DOC_MAP = ROOT / "docs" / "documentation-surface-map.md"
ARCHIVE_README = ROOT / "archive" / "README.md"

checks = [
    (
        "CURRENT_APP_STATE inventory",
        f"**Current repo inventory:** {APP_SWIFT_COUNT} app Swift files in `/Kuro`{PACKAGE_STATE_CLAUSE}; {MIGRATION_COUNT} SQL migrations in `/supabase/migrations`.",
        CURRENT_APP_STATE,
    ),
    (
        "CURRENT_APP_STATE historical note",
        "Historical change-log entries below may include point-in-time counts.",
        CURRENT_APP_STATE,
    ),
    (
        "CURRENT_APP_STATE_PLAIN inventory",
        f"**Current inventory:** {APP_SWIFT_COUNT} app Swift files{PACKAGE_PLAIN_CLAUSE} and {MIGRATION_COUNT} SQL migrations are in the repo today.",
        CURRENT_APP_STATE_PLAIN,
    ),
    (
        "AGENTS shared routing entry point",
        "python3 scripts/agents/policy.py --paths",
        AGENTS,
    ),
    (
        "SQL report historical disclaimer",
        "**Status:** Historical point-in-time report, not a current whole-repo compatibility guarantee.",
        SQL_REPORT,
    ),
    (
        "KNOWLEDGE intentional overlap note",
        "> **Design note:** This directory is intentionally self-contained for LLM",
        KNOWLEDGE_INDEX,
    ),
]

failures = []
for label, needle, haystack in checks:
    if needle not in haystack:
        failures.append(f"{label} missing expected text: {needle}")

if not DOC_MAP.exists():
    failures.append("docs/documentation-surface-map.md is missing")

if not ARCHIVE_README.exists():
    failures.append("archive/README.md is missing")

if failures:
    print("FAIL")
    for failure in failures:
        print(f"- {failure}")
    sys.exit(1)

policy_result = subprocess.run(
    [sys.executable, str(ROOT / "scripts" / "agents" / "policy.py"), "--check"],
    check=False,
)
if policy_result.returncode != 0:
    sys.exit(policy_result.returncode)

# The complete Kuro checkout checks its optional adapter explicitly. A portable
# shared-policy export with neither Claude entry point does not depend on Claude.
if (ROOT / "CLAUDE.md").exists() or (ROOT / ".claude" / "adapter.json").exists():
    adapter_result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "agents" / "policy.py"), "--check-claude"],
        check=False,
    )
    if adapter_result.returncode != 0:
        sys.exit(adapter_result.returncode)

print("PASS")
print(f"- app_swift={APP_SWIFT_COUNT}")
print(f"- package_swift={PACKAGE_SWIFT_COUNT}")
print(f"- migrations={MIGRATION_COUNT}")
