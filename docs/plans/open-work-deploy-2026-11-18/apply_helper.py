#!/usr/bin/env python3
"""Atomic hosted migration apply helper for Kuro open-work deploy (2026-11-18).

Matches the 2026-11-10 latency deploy pattern:
  - execute the migration body and insert the exact file text into
    supabase_migrations.schema_migrations.statements[1] in ONE transaction
  - md5(statements[1]) must equal md5 of the on-disk file afterwards

Usage (from repo root):
  python3 docs/plans/open-work-deploy-2026-11-18/apply_helper.py apply \\
    supabase/prepared-migrations/20261118110000_guest_anon_allowlist_v1.sql
  python3 docs/plans/open-work-deploy-2026-11-18/apply_helper.py verify \\
    supabase/prepared-migrations/20261118110000_guest_anon_allowlist_v1.sql
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import pathlib
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

PROJECT = "bkdifromsqxkndnllmdj"
ROOT = pathlib.Path(__file__).resolve().parents[3]


def token() -> str:
    raw = subprocess.check_output(
        ["security", "find-generic-password", "-s", "Supabase CLI", "-w"], text=True
    ).strip()
    if raw.startswith("go-keyring-base64:"):
        return base64.b64decode(raw.split(":", 1)[1]).decode()
    return raw


def headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {token()}",
        "Content-Type": "application/json",
        "User-Agent": "kuro-open-work-apply/2026-11-18",
    }


def api(method: str, path: str, body: dict | None = None, timeout: int = 180):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT}{path}",
        data=data,
        headers=headers(),
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        raise SystemExit(f"HTTP {e.code} {path}: {err}") from e


def ro(query: str):
    return api("POST", "/database/query/read-only", {"query": query})


def rw(query: str):
    # Management API write endpoint used by the 2026-11-10 latency deploy.
    return api("POST", "/database/query", {"query": query})


def parse_migration(path: pathlib.Path) -> tuple[str, str, str, str]:
    text = path.read_text()
    stem = path.name[:-4] if path.name.endswith(".sql") else path.name
    version, name = stem.split("_", 1)
    if not version.isdigit() or len(version) < 14:
        raise SystemExit(f"bad version in {path.name}")
    stripped = text.lstrip()
    # Skip leading comment block to find begin;
    body_start = text
    lower = text.lower()
    begin_at = lower.find("\nbegin;")
    if begin_at < 0 and lower.startswith("begin;"):
        begin_at = 0
        begin_token = "begin;"
    elif begin_at >= 0:
        begin_at += 1  # skip the newline
        begin_token = text[begin_at : begin_at + 6]
        if begin_token.lower() != "begin;":
            raise SystemExit(f"{path.name}: could not locate begin;")
    else:
        raise SystemExit(f"{path.name}: missing begin;")
    if not text.rstrip().endswith("commit;"):
        raise SystemExit(f"{path.name}: must end with commit;")
    # Body between begin; and final commit;
    after_begin = text[begin_at + len("begin;") :]
    # Find the last commit;
    commit_at = after_begin.rstrip().rfind("commit;")
    if commit_at < 0:
        raise SystemExit(f"{path.name}: missing commit;")
    inner = after_begin[:commit_at]
    return version, name, text, inner


def dollar_quote(tag: str, text: str) -> str:
    if tag in text:
        raise SystemExit(f"dollar-quote tag {tag} appears in migration text")
    return f"${tag}${text}${tag}$"


def apply(path: pathlib.Path) -> dict:
    path = path if path.is_absolute() else ROOT / path
    version, name, exact, inner = parse_migration(path)
    existing = ro(
        "select version, name, md5(statements[1]) as s1_md5 "
        f"from supabase_migrations.schema_migrations where version = '{version}';"
    )
    if existing:
        raise SystemExit(f"version {version} already in history: {existing}")
    md5 = hashlib.md5(exact.encode()).hexdigest()
    sha = hashlib.sha256(exact.encode()).hexdigest()
    tag = f"kuro_mig_{version}"
    quoted = dollar_quote(tag, exact)
    # One transaction: migration body + exact history insert.
    sql = (
        "begin;\n"
        "set local lock_timeout = '5s';\n"
        "set local statement_timeout = '120s';\n"
        f"{inner}\n"
        "insert into supabase_migrations.schema_migrations (version, name, statements)\n"
        f"values ('{version}', '{name}', array[{quoted}]::text[]);\n"
        "commit;\n"
    )
    started = datetime.now(timezone.utc).isoformat()
    result = rw(sql)
    finished = datetime.now(timezone.utc).isoformat()
    verify = ro(
        "select version, name, cardinality(statements) as n, "
        "md5(statements[1]) as s1_md5, length(statements[1]) as s1_len "
        f"from supabase_migrations.schema_migrations where version = '{version}';"
    )
    if not verify or verify[0]["s1_md5"] != md5:
        raise SystemExit(f"post-apply md5 mismatch: expected {md5}, got {verify}")
    receipt = {
        "migration": {
            "version": version,
            "name": name,
            "file": str(path.relative_to(ROOT)),
            "md5": md5,
            "sha256": sha,
            "bytes": len(exact.encode()),
        },
        "started_at": started,
        "finished_at": finished,
        "api_result": result,
        "verify": verify,
    }
    out = path.parent.parent.parent / "docs/plans/open-work-deploy-2026-11-18" / f"applied-{version}.json"
    # path is .../supabase/prepared-migrations/file -> parents wrong.
    out = ROOT / "docs/plans/open-work-deploy-2026-11-18" / f"applied-{version}.json"
    out.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))
    return receipt


def verify(path: pathlib.Path) -> dict:
    path = path if path.is_absolute() else ROOT / path
    version, name, exact, _ = parse_migration(path)
    md5 = hashlib.md5(exact.encode()).hexdigest()
    row = ro(
        "select version, name, md5(statements[1]) as s1_md5, length(statements[1]) as s1_len "
        f"from supabase_migrations.schema_migrations where version = '{version}';"
    )
    ok = bool(row) and row[0]["s1_md5"] == md5
    out = {"ok": ok, "expected_md5": md5, "row": row, "file": str(path)}
    print(json.dumps(out, indent=2))
    if not ok:
        raise SystemExit(1)
    return out


def main(argv: list[str]) -> None:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("apply")
    a.add_argument("path")
    v = sub.add_parser("verify")
    v.add_argument("path")
    r = sub.add_parser("ro")
    r.add_argument("query")
    args = p.parse_args(argv)
    if args.cmd == "apply":
        apply(pathlib.Path(args.path))
    elif args.cmd == "verify":
        verify(pathlib.Path(args.path))
    elif args.cmd == "ro":
        print(json.dumps(ro(args.query), indent=2))


if __name__ == "__main__":
    main(sys.argv[1:])
