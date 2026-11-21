#!/usr/bin/env python3
"""Offline review & SQL emitter for prepared public.series_candidates staging rows.

Usage:
  python3 scripts/series_candidates_enrichment_review.py --input candidates.json [--approve-unambiguous] [--dry-run | --emit-sql]

Defaults to --dry-run (prints JSON review summary, never connects to a live database).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

VALID_MEDIA_TYPES = {"anime", "manga"}
VALID_SECTION_KINDS = {"main", "side", "adaptation"}
VALID_STATUSES = {"pending", "approved", "rejected"}


def _sql_text(value: str | None) -> str:
    if value is None:
        return "NULL"
    escaped = value.replace("'", "''")
    return f"'{escaped}'"


def _sql_int(value: int | None) -> str:
    if value is None:
        return "NULL"
    return str(value)


def validate_candidate(raw: dict[str, Any], index: int) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise ValueError(f"row {index}: candidate must be an object")

    root_type = str(raw.get("root_media_type", "")).strip().lower()
    member_type = str(raw.get("member_media_type", "")).strip().lower()
    section_kind = str(raw.get("section_kind", "")).strip().lower()
    status = str(raw.get("status", "pending")).strip().lower()

    if root_type not in VALID_MEDIA_TYPES:
        raise ValueError(f"row {index}: invalid root_media_type {root_type!r}")
    if member_type not in VALID_MEDIA_TYPES:
        raise ValueError(f"row {index}: invalid member_media_type {member_type!r}")
    if section_kind not in VALID_SECTION_KINDS:
        raise ValueError(f"row {index}: invalid section_kind {section_kind!r}")
    if status not in VALID_STATUSES:
        raise ValueError(f"row {index}: invalid status {status!r}")

    root_id = raw.get("root_media_id")
    member_id = raw.get("member_media_id")
    if not isinstance(root_id, int) or isinstance(root_id, bool) or root_id < 1:
        raise ValueError(f"row {index}: root_media_id must be a positive integer")
    if not isinstance(member_id, int) or isinstance(member_id, bool) or member_id < 1:
        raise ValueError(f"row {index}: member_media_id must be a positive integer")

    ordinal = raw.get("ordinal", 0)
    if not isinstance(ordinal, int) or isinstance(ordinal, bool):
        raise ValueError(f"row {index}: ordinal must be an integer")

    units: dict[str, int | None] = {}
    for field in ("source_start_unit", "source_end_unit", "source_volume"):
        val = raw.get(field)
        if val is not None:
            if not isinstance(val, int) or isinstance(val, bool) or val < 0:
                raise ValueError(f"row {index}: {field} must be a non-negative integer or null")
        units[field] = val

    raw_note = raw.get("raw_note")
    if raw_note is not None and not isinstance(raw_note, str):
        raise ValueError(f"row {index}: raw_note must be a string or null")

    return {
        "root_media_type": root_type,
        "root_media_id": root_id,
        "member_media_type": member_type,
        "member_media_id": member_id,
        "section_kind": section_kind,
        "ordinal": ordinal,
        **units,
        "raw_note": raw_note,
        "status": status,
        "auto_approvable": bool(raw.get("auto_approvable", False)),
    }


def review_candidates(rows: list[dict[str, Any]], approve_unambiguous: bool = False) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    normalized = [validate_candidate(row, idx) for idx, row in enumerate(rows)]
    auto_approved_count = 0
    for row in normalized:
        if approve_unambiguous and row["status"] == "pending" and row["auto_approvable"]:
            row["status"] = "approved"
            auto_approved_count += 1

    counts = {
        "total": len(normalized),
        "pending": sum(1 for r in normalized if r["status"] == "pending"),
        "approved": sum(1 for r in normalized if r["status"] == "approved"),
        "rejected": sum(1 for r in normalized if r["status"] == "rejected"),
        "auto_approved": auto_approved_count,
    }
    return normalized, counts


def emit_upsert_sql(rows: list[dict[str, Any]]) -> str:
    if not rows:
        return "-- No series_candidates rows to upsert.\n"
    values_sql = []
    for row in rows:
        values_sql.append(
            "  ("
            + ", ".join([
                _sql_text(row["root_media_type"]),
                _sql_int(row["root_media_id"]),
                _sql_text(row["member_media_type"]),
                _sql_int(row["member_media_id"]),
                _sql_text(row["section_kind"]),
                _sql_int(row["ordinal"]),
                _sql_int(row["source_start_unit"]),
                _sql_int(row["source_end_unit"]),
                _sql_int(row["source_volume"]),
                _sql_text(row["raw_note"]),
                _sql_text(row["status"]),
            ])
            + ")"
        )

    return "\n".join([
        "begin;",
        "insert into public.series_candidates (",
        "  root_media_type, root_media_id, member_media_type, member_media_id,",
        "  section_kind, ordinal, source_start_unit, source_end_unit, source_volume,",
        "  raw_note, status",
        ") values",
        ",\n".join(values_sql),
        "on conflict (root_media_type, root_media_id, member_media_type, member_media_id) do update set",
        "  section_kind = excluded.section_kind,",
        "  ordinal = excluded.ordinal,",
        "  source_start_unit = excluded.source_start_unit,",
        "  source_end_unit = excluded.source_end_unit,",
        "  source_volume = excluded.source_volume,",
        "  raw_note = excluded.raw_note,",
        "  status = excluded.status,",
        "  updated_at = now();",
        "commit;",
        "",
    ])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Review and emit SQL for series_candidates staging rows.")
    parser.add_argument("--input", required=True, help="Path to JSON file containing an array of candidate rows.")
    parser.add_argument(
        "--approve-unambiguous",
        action="store_true",
        help="Promote pending candidates marked auto_approvable=true to status='approved'.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print JSON summary without SQL output (default).")
    parser.add_argument("--emit-sql", action="store_true", help="Emit idempotent INSERT/ON CONFLICT SQL to stdout.")
    args = parser.parse_args(argv)

    raw_text = Path(args.input).read_text(encoding="utf-8")
    payload = json.loads(raw_text)
    if not isinstance(payload, list):
        raise ValueError("input JSON must be an array of candidate objects")

    reviewed, counts = review_candidates(payload, approve_unambiguous=args.approve_unambiguous)
    if args.emit_sql and not args.dry_run:
        sys.stdout.write(emit_upsert_sql(reviewed))
    else:
        sys.stdout.write(json.dumps({"dry_run": True, "summary": counts, "rows": reviewed}, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
