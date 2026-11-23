from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import series_candidates_enrichment_review as review  # noqa: E402


class SeriesCandidatesReviewTests(unittest.TestCase):
    def test_approves_only_unambiguous_pending_rows_and_emits_escaped_sql(self) -> None:
        sample = [
            {
                "root_media_type": "anime",
                "root_media_id": 100,
                "member_media_type": "anime",
                "member_media_id": 101,
                "section_kind": "main",
                "ordinal": 1,
                "source_start_unit": None,
                "source_end_unit": None,
                "source_volume": None,
                "raw_note": "O'Neill's linear sequel",
                "status": "pending",
                "auto_approvable": True,
            },
            {
                "root_media_type": "anime",
                "root_media_id": 100,
                "member_media_type": "manga",
                "member_media_id": 500,
                "section_kind": "adaptation",
                "ordinal": 1,
                "source_start_unit": 1,
                "source_end_unit": 63,
                "source_volume": 8,
                "raw_note": None,
                "status": "pending",
                "auto_approvable": False,
            },
        ]
        reviewed, counts = review.review_candidates(sample, approve_unambiguous=True)
        self.assertEqual(counts["total"], 2)
        self.assertEqual(counts["approved"], 1)
        self.assertEqual(counts["pending"], 1)
        self.assertEqual(counts["auto_approved"], 1)
        self.assertEqual(reviewed[0]["status"], "approved")
        self.assertEqual(reviewed[1]["status"], "pending")

        sql = review.emit_upsert_sql(reviewed)
        self.assertIn("insert into public.series_candidates", sql)
        self.assertIn("'O''Neill''s linear sequel'", sql)
        self.assertIn("on conflict (root_media_type, root_media_id, member_media_type, member_media_id)", sql)

    def test_rejects_negative_units_and_invalid_section_kind(self) -> None:
        with self.assertRaises(ValueError):
            review.validate_candidate(
                {
                    "root_media_type": "anime",
                    "root_media_id": 1,
                    "member_media_type": "manga",
                    "member_media_id": 2,
                    "section_kind": "adaptation",
                    "source_end_unit": -1,
                },
                0,
            )

        with self.assertRaises(ValueError):
            review.validate_candidate(
                {
                    "root_media_type": "anime",
                    "root_media_id": 1,
                    "member_media_type": "anime",
                    "member_media_id": 2,
                    "section_kind": "invalid_kind",
                },
                0,
            )

    def test_cli_dry_run_and_emit_sql(self) -> None:
        payload = [
            {
                "root_media_type": "anime",
                "root_media_id": 42,
                "member_media_type": "manga",
                "member_media_id": 84,
                "section_kind": "adaptation",
                "ordinal": 1,
                "source_start_unit": 1,
                "source_end_unit": 28,
                "source_volume": 4,
                "status": "pending",
                "auto_approvable": True,
            }
        ]
        fd, raw_path = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        path = Path(raw_path)
        try:
            path.write_text(json.dumps(payload), encoding="utf-8")
            dry = subprocess.run(
                [sys.executable, str(ROOT / "scripts" / "series_candidates_enrichment_review.py"), "--input", str(path), "--approve-unambiguous", "--dry-run"],
                capture_output=True,
                text=True,
                check=True,
            )
            parsed = json.loads(dry.stdout)
            self.assertTrue(parsed["dry_run"])
            self.assertEqual(parsed["summary"]["approved"], 1)

            sql_proc = subprocess.run(
                [sys.executable, str(ROOT / "scripts" / "series_candidates_enrichment_review.py"), "--input", str(path), "--approve-unambiguous", "--emit-sql"],
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertIn("'approved'", sql_proc.stdout)
        finally:
            path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
