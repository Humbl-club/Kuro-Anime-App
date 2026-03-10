#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path("/Applications/Kuro")
APP_SWIFT_COUNT = len(list((ROOT / "Kuro").rglob("*.swift")))
MIGRATION_COUNT = len(list((ROOT / "supabase" / "migrations").glob("*.sql")))

CURRENT_APP_STATE = (ROOT / "CURRENT_APP_STATE.md").read_text()
CURRENT_APP_STATE_PLAIN = (ROOT / "CURRENT_APP_STATE_PLAIN.md").read_text()
CLAUDE = (ROOT / "CLAUDE.md").read_text()
SQL_REPORT = (ROOT / "archive" / "SQL_COMPATIBILITY_REPORT.md").read_text()
KNOWLEDGE_INDEX = (ROOT / "KNOWLEDGE" / "INDEX.md").read_text()
DOC_MAP = ROOT / "docs" / "documentation-surface-map.md"
ARCHIVE_README = ROOT / "archive" / "README.md"

checks = [
    (
        "CURRENT_APP_STATE inventory",
        f"**Current repo inventory:** {APP_SWIFT_COUNT} app Swift files in `/Kuro`; {MIGRATION_COUNT} SQL migrations in `/supabase/migrations`.",
        CURRENT_APP_STATE,
    ),
    (
        "CURRENT_APP_STATE historical note",
        "Historical change-log entries below may include point-in-time counts.",
        CURRENT_APP_STATE,
    ),
    (
        "CURRENT_APP_STATE_PLAIN inventory",
        f"**Current inventory:** {APP_SWIFT_COUNT} app Swift files and {MIGRATION_COUNT} SQL migrations are in the repo today.",
        CURRENT_APP_STATE_PLAIN,
    ),
    (
        "CLAUDE file map count",
        f"### iOS app — {APP_SWIFT_COUNT} Swift files in `Kuro/`",
        CLAUDE,
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

if re.search(r"### iOS app — 67 Swift files in `Kuro/`", CLAUDE):
    failures.append("CLAUDE still contains stale 67-file count")

if not DOC_MAP.exists():
    failures.append("docs/documentation-surface-map.md is missing")

if not ARCHIVE_README.exists():
    failures.append("archive/README.md is missing")

if failures:
    print("FAIL")
    for failure in failures:
        print(f"- {failure}")
    sys.exit(1)

print("PASS")
print(f"- app_swift={APP_SWIFT_COUNT}")
print(f"- migrations={MIGRATION_COUNT}")
