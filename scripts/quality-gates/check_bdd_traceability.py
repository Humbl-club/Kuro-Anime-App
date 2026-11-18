#!/usr/bin/env python3
"""BDD traceability checker for the tracker-gaps Gherkin features.

Every scenario in docs/superpowers/specs/*/features/*.feature must carry exactly one test tag.

Tag grammar (pinned):
  - A tag line is a line whose first non-blank character is `@`.
  - Tokens are split on whitespace, with one exception: a token starting with `@deno:`
    consumes the rest of the line (the name after `::` may contain spaces).
  - Test-tag prefixes: @pkg: @swift: @sql: @deno: @ui: @load: @manual:
    Any other `@word:` token is a finding (`unknown test layer`).
  - Plain tags (@gated, @owner-gate, @workstream-<ID>) carry no layer.
  - Pending tags attach to the next Feature:, Rule:, Scenario:, Scenario Outline: or Example:
    line. Examples: tags are ignored.
  - A scenario inherits the plain tags of its Rule and its Feature. A Rule scope ends at the
    next Rule: or at end of file.
  - @gated on the Feature or the Rule: the scenario is skipped for counting and resolution
    (counted as gated, never a missing/unresolved finding). The tag-shape checks
    (unknown test layer, @manual needs @owner-gate) still apply to gated scenarios.
  - Exactly one test tag per non-gated scenario. Zero -> `missing test tag`; two or more ->
    `2 test tags (...)`.
  - @manual: without @owner-gate on the scenario, its Rule or its Feature ->
    `@manual needs @owner-gate`.
  - Workstream: the nearest plain tag @workstream-<ID> (Scenario, then Rule, then Feature)
    wins; otherwise the feature file basename up to its first `-` (W9-lists.feature -> W9).
  - Two scenarios with the same name in one feature file -> `duplicate scenario name`.

Exit codes: 0 clean, 1 findings, 2 usage error.
"""
from __future__ import annotations

import argparse
import datetime
import json
import shutil
import subprocess
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_FEATURE_GLOB = "docs/superpowers/specs/*/features/*.feature"
LAYERS = ("pkg", "swift", "sql", "deno", "ui", "load", "manual")
LAYER_TAG = re.compile(r"^@([A-Za-z][A-Za-z0-9_-]*):")
SCENARIO_KEYWORDS = ("Scenario Outline:", "Scenario:", "Example:")


@dataclass
class Scenario:
    file: Path
    line: int
    name: str
    test_tags: list[str] = field(default_factory=list)
    all_tags: set[str] = field(default_factory=set)
    gated: bool = False
    workstream: str = ""
    rule: str = ""


@dataclass
class Finding:
    file: str
    line: int
    scenario: str
    problem: str
    kind: str = "shape"


def split_tags(line: str) -> list[str]:
    """Split a tag line into tokens; `@deno:` consumes the rest of the line."""
    tokens: list[str] = []
    rest = line.strip()
    while rest:
        if rest.startswith("@deno:"):
            tokens.append(rest.strip())
            break
        parts = rest.split(None, 1)
        tokens.append(parts[0])
        rest = parts[1].strip() if len(parts) > 1 else ""
    return tokens


def is_test_tag(token: str) -> bool:
    return LAYER_TAG.match(token) is not None


def _workstream(tags: list[str]) -> str | None:
    for token in tags:
        if token.startswith("@workstream-"):
            return token[len("@workstream-"):]
    return None


def parse_feature(path: Path) -> list[Scenario]:
    default_ws = path.name.split("-", 1)[0]
    scenarios: list[Scenario] = []
    pending: list[str] = []
    feature_tags: list[str] = []
    rule_tags: list[str] = []
    in_examples = False
    rule_name = ""
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = raw.strip()
        if stripped.startswith("@"):
            if not in_examples:
                pending.extend(split_tags(stripped))
            continue
        if stripped.startswith("Examples:") or stripped.startswith("Scenarios:"):
            pending = []
            in_examples = True
            continue
        if stripped.startswith("Feature:"):
            feature_tags, pending, rule_tags, in_examples = pending, [], [], False
            rule_name = ""
        elif stripped.startswith("Rule:"):
            rule_tags, pending, in_examples = pending, [], False
            rule_name = stripped.split(":", 1)[1].strip()
        elif stripped.startswith(SCENARIO_KEYWORDS):
            in_examples = False
            name = stripped.split(":", 1)[1].strip()
            own = pending
            pending = []
            plain_scope = [t for t in feature_tags + rule_tags + own if not is_test_tag(t)]
            ws = _workstream(own) or _workstream(rule_tags) or _workstream(feature_tags) or default_ws
            scenarios.append(
                Scenario(
                    file=path,
                    line=number,
                    name=name,
                    test_tags=[t for t in own if is_test_tag(t)],
                    all_tags=set(plain_scope) | set(own),
                    gated="@gated" in plain_scope,
                    workstream=ws,
                    rule=rule_name,
                )
            )
        elif stripped and not stripped.startswith("#"):
            # A step, description or table line: any dangling tags were not for a keyword.
            pending = [] if pending and not stripped.startswith("|") else pending
    return scenarios


def feature_files(root: Path, feature_glob: str) -> list[Path]:
    return sorted(p for p in root.glob(feature_glob) if p.is_file())


# ---------------------------------------------------------------------------
# Tag resolution
# ---------------------------------------------------------------------------

SWIFT_SCOPES = {
    "pkg": "Packages/KuroModules/Tests",
    "swift": "KuroTests",
    "ui": "KuroUITests",
}


def strip_swift(text: str) -> str:
    """Blank comments and string literals (keeping offsets and newlines)."""
    out = list(text)
    n = len(text)
    i = 0

    def blank(a: int, b: int) -> None:
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif text.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if text.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif text.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            blank(i, j)
            i = j
        elif c == "#" or c == '"':
            hashes = 0
            j = i
            while j < n and text[j] == "#":
                hashes, j = hashes + 1, j + 1
            if j < n and text[j] == '"':
                closer_hashes = "#" * hashes
                if text.startswith('"""', j):
                    closer = '"""' + closer_hashes
                    k = text.find(closer, j + 3)
                    end = n if k < 0 else k + len(closer)
                else:
                    k = j + 1
                    while k < n and text[k] != "\n":
                        if hashes == 0 and text[k] == "\\":
                            k += 2
                            continue
                        if text[k] == '"' and text.startswith(closer_hashes, k + 1):
                            break
                        k += 1
                    end = min(n, k + 1 + hashes)
                blank(i, end)
                i = max(end, i + 1)
            else:
                i = j if j > i else i + 1
        else:
            i += 1
    return "".join(out)


def _match_brace(text: str, open_at: int) -> int:
    depth = 0
    for k in range(open_at, len(text)):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                return k
    return len(text)


def suite_bodies(root: Path, scope: str, suite: str) -> list[str]:
    """Stripped bodies of every `struct|class|enum|actor|extension <suite>` under scope."""
    base = root / scope
    decl = re.compile(r"\b(?:struct|class|enum|actor|extension)\s+" + re.escape(suite) + r"\b")
    bodies: list[str] = []
    if not base.is_dir():
        return bodies
    for path in sorted(base.rglob("*.swift")):
        stripped = strip_swift(path.read_text(encoding="utf-8", errors="replace"))
        for match in decl.finditer(stripped):
            open_at = stripped.find("{", match.end())
            if open_at < 0:
                continue
            bodies.append(stripped[open_at + 1 : _match_brace(stripped, open_at)])
    return bodies


def _has_func(body: str, name: str, needs_test: bool) -> bool:
    for match in re.finditer(r"\bfunc\s+" + re.escape(name) + r"\s*[(<]", body):
        if not needs_test:
            return True
        before = body[: match.start()]
        cut = max(before.rfind("{"), before.rfind("}"))
        for earlier in re.finditer(r"\bfunc\b", before):
            cut = max(cut, earlier.start())
        if "@Test" in before[cut + 1 :]:
            return True
    return False


def _resolve_swift(root: Path, layer: str, rest: str) -> str | None:
    suite, _, name = rest.partition("/")
    scope = SWIFT_SCOPES[layer]
    bodies = suite_bodies(root, scope, suite)
    if not bodies:
        return f"suite {suite} not found in {scope}"
    needs_test = layer != "ui"
    if any(_has_func(b, name, needs_test) for b in bodies):
        return None
    return f"no @Test func {name} in {suite}" if needs_test else f"no func {name} in {suite}"


def _resolve_deno(root: Path, rest: str) -> str | None:
    file_part, _, name = rest.partition("::")
    path = root / file_part
    if not path.is_file():
        return f"file {file_part} not found"
    text = path.read_text(encoding="utf-8", errors="replace")
    quoted = re.escape(name)
    patterns = [
        r"Deno\.test\(\s*\"" + quoted + r"\"",
        r"Deno\.test\(\s*'" + quoted + r"'",
        r"Deno\.test\(\s*\{[^}]*?name:\s*[\"']" + quoted + r"[\"']",
    ]
    if any(re.search(p, text, re.S) for p in patterns):
        return None
    return f'no Deno.test "{name}" in {file_part}'


def _resolve_load(root: Path, profile: str) -> str | None:
    if shutil.which("node") is None:
        return "node not available"
    workload = root / "scripts/load/backend_workload.js"
    if not workload.is_file():
        return "no TRACKER_GAP_PROFILES (F3)"
    script = (
        "const m=require(process.argv[1]);"
        "console.log(JSON.stringify(m.TRACKER_GAP_PROFILES?Object.keys(m.TRACKER_GAP_PROFILES):null))"
    )
    run = subprocess.run(
        ["node", "-e", script, str(workload)], capture_output=True, text=True, check=False, timeout=60
    )
    try:
        keys = json.loads(run.stdout.strip() or "null")
    except ValueError:
        keys = None
    if keys is None:
        return "no TRACKER_GAP_PROFILES (F3)"
    return None if profile in keys else f"unknown load profile {profile}"


def resolve(root: Path, tag: str) -> str | None:
    """None when the tag resolves to an existing test, otherwise the reason."""
    root = Path(root)
    match = LAYER_TAG.match(tag)
    if not match:
        return f"not a test tag {tag}"
    layer = match.group(1)
    rest = tag[match.end():]
    if layer in SWIFT_SCOPES:
        return _resolve_swift(root, layer, rest)
    if layer == "sql":
        rel = f"supabase/tests/{rest}"
        return None if (root / rel).is_file() else f"file {rel} not found"
    if layer == "deno":
        return _resolve_deno(root, rest)
    if layer == "load":
        return _resolve_load(root, rest)
    if layer == "manual":
        return None
    return f"unknown test layer {tag}"


# ---------------------------------------------------------------------------
# Checking
# ---------------------------------------------------------------------------


def _rel(root: Path, path: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def shape_findings(root: Path, scenario: Scenario, seen: set[str]) -> list[Finding]:
    rel = _rel(root, scenario.file)
    out: list[Finding] = []

    def add(problem: str) -> None:
        out.append(Finding(rel, scenario.line, scenario.name, problem))

    if scenario.name in seen:
        add("duplicate scenario name")
    seen.add(scenario.name)
    for tag in scenario.test_tags:
        match = LAYER_TAG.match(tag)
        if not match:
            continue
        layer = match.group(1)
        if layer not in LAYERS:
            add(f"unknown test layer {tag}")
        elif layer == "ui" and not tag[match.end():].partition("/")[2].startswith("test"):
            add("@ui name must be the XCTest method (test…)")
    if any(t.startswith("@manual:") for t in scenario.test_tags) and "@owner-gate" not in scenario.all_tags:
        add("@manual needs @owner-gate")
    if not scenario.gated:
        count = len(scenario.test_tags)
        if count == 0:
            add("missing test tag")
        elif count > 1:
            add(f"{count} test tags ({', '.join(scenario.test_tags)})")
    return out


@dataclass
class Summary:
    scenarios: int = 0
    gated: int = 0
    manual: int = 0
    resolved: int = 0
    unresolved: int = 0
    pending: int = 0
    tag_errors: int = 0

    def line(self) -> str:
        return (
            f"Summary: {self.scenarios} scenarios, {self.gated} gated, {self.manual} manual, "
            f"{self.resolved} resolved, {self.unresolved} unresolved, "
            f"{self.pending} pending (not landed), {self.tag_errors} tag errors"
        )


def read_landed(path: Path) -> set[str]:
    if not path.is_file():
        return set()
    names = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            names.add(line)
    return names


def analyse(
    root: Path, feature_glob: str = DEFAULT_FEATURE_GLOB, landed: set[str] | None = None
) -> tuple[list[Finding], Summary]:
    """All findings (kinds: shape, unresolved, pending) and the summary counts."""
    root = Path(root)
    landed = landed or set()
    findings: list[Finding] = []
    summary = Summary()
    for path in feature_files(root, feature_glob):
        seen: set[str] = set()
        for scenario in parse_feature(path):
            summary.scenarios += 1
            shape = shape_findings(root, scenario, seen)
            findings.extend(shape)
            summary.tag_errors += len(shape)
            if scenario.gated:
                summary.gated += 1
                continue
            if len(scenario.test_tags) != 1:
                continue
            tag = scenario.test_tags[0]
            if tag.startswith("@manual:"):
                if "@owner-gate" in scenario.all_tags:
                    summary.manual += 1
                continue
            if LAYER_TAG.match(tag) and LAYER_TAG.match(tag).group(1) not in LAYERS:
                continue
            reason = resolve(root, tag)
            if reason is None:
                summary.resolved += 1
            elif path.name in landed:
                summary.unresolved += 1
                findings.append(Finding(_rel(root, path), scenario.line, scenario.name, reason, "unresolved"))
            else:
                summary.pending += 1
                findings.append(
                    Finding(
                        _rel(root, path), scenario.line, scenario.name, f"pending (not landed): {reason}", "pending"
                    )
                )
    return findings, summary


def check(
    root: Path, feature_glob: str = DEFAULT_FEATURE_GLOB, landed: set[str] | None = None
) -> list[Finding]:
    """Findings that change the exit code (tag shape, and unresolved tags of landed features)."""
    findings, _ = analyse(root, feature_glob, landed)
    return [f for f in findings if f.kind != "pending"]


def format_finding(f: Finding) -> str:
    return f"{f.file}:{f.line}: {f.scenario}: {f.problem}"


# ---------------------------------------------------------------------------
# Acceptance (--accepted <WS>): a workstream is accepted from an execution record
# ---------------------------------------------------------------------------
#
# Record: docs/tracker-gaps-2026-11/acceptance/<WS>.json (schemaVersion 1):
#   workstream, testedCommit (40 hex), recordedAt, unresolvedGates [str],
#   runs: [{id, layer (pkg|swift|sql|deno|ui|load|manual), command, exitCode, log,
#           context: {kind (local|simulator|local-db|live-read-only|load-qualification|owner),
#                     simulator (swift/ui), loadReport/loadRunKey/cleanupReport (load),
#                     owner/evidence (manual)}}],
#   scenarios: [{feature, scenario, tag, result (pass|fail|blocked|insufficient), run, note?}]
# Rules: (1) record parses, schemaVersion 1, workstream matches, 40-hex testedCommit.
# (2) testedCommit == HEAD, or an ancestor of HEAD with only acceptance-folder changes since; the
#     working tree has nothing outside the acceptance folder. (3) every non-gated scenario of the
#     workstream needs exactly one entry keyed by (feature, scenario), with the current tag and
#     result "pass"; gated scenarios are excluded and need a named unresolved gate.
# (4) evidence per pass: run exists, layer == tag layer, exitCode 0, log exists, and per layer a
#     passed line (pkg/swift/ui/deno), a harness PASS line with 0 blocked markers (sql), a passing
#     qualification report plus cleanup proof (load), or an owner record (manual).

ACCEPTANCE_DIR = "docs/tracker-gaps-2026-11/acceptance/"
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
SHA40 = re.compile(r"^[0-9a-f]{40}$")
RESULTS = ("pass", "fail", "blocked", "insufficient")


@dataclass
class AcceptanceSummary:
    workstream: str
    total: int = 0
    passed: int = 0
    findings: int = 0
    sha: str = ""
    gated: list[str] = field(default_factory=list)
    unresolved_gates: list[str] = field(default_factory=list)

    def lines(self) -> list[str]:
        if self.findings == 0:
            head = f"Accepted {self.workstream}: {self.passed}/{self.total} scenarios pass at {self.sha[:12]}"
        else:
            head = f"NOT accepted {self.workstream}: {self.passed}/{self.total} pass, {self.findings} findings"
        out = [head]
        out += [f"gated (excluded): {g}" for g in self.gated]
        out += [f"unresolved gate: {g}" for g in self.unresolved_gates]
        return out


def _git(root: Path, *args: str) -> tuple[int, str]:
    run = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, check=False)
    return run.returncode, run.stdout.rstrip("\n")  # keep leading spaces: porcelain lines start with them


def git_head(root: Path) -> str:
    code, out = _git(Path(root), "rev-parse", "HEAD")
    return out if code == 0 else ""


def _test_labels(root: Path, layer: str, suite: str, name: str) -> list[str]:
    """Swift Testing display labels (`@Test("label")`) of the func, as the runner prints them."""
    base = root / SWIFT_SCOPES[layer]
    labels: list[str] = []
    if not base.is_dir():
        return labels
    decl = re.compile(r"\b(?:struct|class|enum|actor|extension)\s+" + re.escape(suite) + r"\b")
    for path in sorted(base.rglob("*.swift")):
        raw = path.read_text(encoding="utf-8", errors="replace")
        stripped = strip_swift(raw)
        for match in decl.finditer(stripped):
            open_at = stripped.find("{", match.end())
            if open_at < 0:
                continue
            close = _match_brace(stripped, open_at)
            body = stripped[open_at + 1 : close]
            for fn in re.finditer(r"\bfunc\s+" + re.escape(name) + r"\s*[(<]", body):
                at = open_at + 1 + fn.start()
                before = stripped[:at]
                cut = max(before.rfind("{"), before.rfind("}"))
                for earlier in re.finditer(r"\bfunc\b", before[open_at:]):
                    cut = max(cut, open_at + earlier.start())
                window = raw[cut + 1 : at]
                label = re.search(r'@Test\(\s*"((?:[^"\\]|\\.)*)"', window)
                if label:
                    labels.append(label.group(1))
    return labels


def _test_passed(root: Path, layer: str, tag: str, log: str) -> bool:
    rest = tag[LAYER_TAG.match(tag).end():]  # type: ignore[union-attr]
    text = ANSI.sub("", log)
    if layer == "deno":
        name = rest.partition("::")[2]
        return re.search(r"^" + re.escape(name) + r" \.\.\. ok\b", text, re.M) is not None
    suite, _, name = rest.partition("/")
    if layer == "ui":
        pattern = r"Test Case '-\[(?:\S+\.)?" + re.escape(suite) + " " + re.escape(name) + r"\]' passed"
        return re.search(pattern, text) is not None
    patterns = [r"Test " + re.escape(name) + r"\([^)]*\)(?: with \d+ test cases)? passed"]
    for label in _test_labels(root, layer, suite, name):
        patterns.append(r'Test "' + re.escape(label) + r'"(?: with \d+ test cases)? passed')
    if layer == "swift":
        patterns.append(r"Test case '" + re.escape(suite) + "/" + re.escape(name) + r"\([^)]*\)' passed")
    return any(re.search(p, text) for p in patterns)


def _sql_passed(basename: str, log: str) -> bool:
    pattern = (
        r"^PASS\s+" + re.escape(basename) + r"\s+\d+ assertions, 0 blocked markers, \d+ findings$"
    )
    return re.search(pattern, ANSI.sub("", log), re.M) is not None


def _load_json(path: Path) -> dict | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def _load_ok(root: Path, profile: str, context: dict) -> bool:
    if context.get("kind") != "load-qualification":
        return False
    report = _load_json(root / str(context.get("loadReport", "")))
    cleanup = _load_json(root / str(context.get("cleanupReport", "")))
    if report is None or cleanup is None:
        return False
    if report.get("mode") != "qualify" or report.get("runKey") != context.get("loadRunKey"):
        return False
    if (report.get("preflight") or {}).get("passed") is not True:
        return False
    profiles = ((report.get("lanes") or {}).get("profiles") or {}).get("profiles") or {}
    if (profiles.get(profile) or {}).get("verdict") != "pass":
        return False
    states = [
        (entry.get("profileData") or {}).get(profile)
        for entry in cleanup.get("cleanup") or []
        if isinstance(entry, dict) and profile in (entry.get("profileData") or {})
    ]
    return bool(states) and all(s == "absent" for s in states)


def _evidence_problem(root: Path, scenario: Scenario, entry: dict, runs: dict) -> str | None:
    tag = scenario.test_tags[0]
    layer = LAYER_TAG.match(tag).group(1)  # type: ignore[union-attr]
    run = runs.get(entry.get("run"))
    if run is None:
        return f"run {entry.get('run')} not in record"
    if run.get("layer") != layer:
        return f"run layer {run.get('layer')} is not {layer}"
    if run.get("exitCode") != 0:
        return f"run exit code {run.get('exitCode')}"
    log_path = root / str(run.get("log", ""))
    if not run.get("log") or not log_path.is_file():
        return "run log missing"
    log = log_path.read_text(encoding="utf-8", errors="replace")
    context = run.get("context") or {}
    rest = tag[LAYER_TAG.match(tag).end():]  # type: ignore[union-attr]
    if layer in ("pkg", "swift", "ui", "deno"):
        if layer in ("swift", "ui") and not context.get("simulator"):
            return "context.simulator missing"
        if not _test_passed(root, layer, tag, log):
            return "test did not pass in log"
    elif layer == "sql":
        basename = rest.rsplit("/", 1)[-1]
        command = str(run.get("command", ""))
        local = context.get("kind") == "local-db" and "run_local_db_tests.sh" in command
        if not (local or context.get("kind") == "live-read-only") or not _sql_passed(basename, log):
            return "SQL test did not run and pass"
    elif layer == "load":
        if not _load_ok(root, rest, context):
            return "load evidence is not a passing qualification run"
    elif layer == "manual":
        evidence = str(context.get("evidence", ""))
        if context.get("kind") != "owner" or not context.get("owner") or not evidence or not (root / evidence).exists():
            return "manual evidence needs an owner context, an owner and an existing evidence path"
    return None


def _commit_problem(root: Path, tested: str) -> str | None:
    head = git_head(root)
    short = lambda s: s[:12]  # noqa: E731
    if tested != head:
        anc, _ = _git(root, "merge-base", "--is-ancestor", tested, "HEAD")
        diff_code, diff = _git(root, "diff", "--name-only", tested, "HEAD")
        if anc != 0 or diff_code != 0 or any(not p.startswith(ACCEPTANCE_DIR) for p in diff.splitlines() if p):
            return f"record is for {short(tested)}; HEAD {short(head)} changed outside acceptance records"
    _, status = _git(root, "status", "--porcelain", "-uall")
    for line in status.splitlines():
        paths = line[3:].split(" -> ")
        if any(not p.strip('"').startswith(ACCEPTANCE_DIR) for p in paths):
            return "uncommitted changes outside acceptance records"
    return None


def _all_scenarios(root: Path, feature_glob: str) -> list[Scenario]:
    return [s for path in feature_files(root, feature_glob) for s in parse_feature(path)]


def accepted(
    root: Path, workstream: str, feature_glob: str = DEFAULT_FEATURE_GLOB
) -> tuple[list[Finding], AcceptanceSummary]:
    root = Path(root)
    summary = AcceptanceSummary(workstream)
    findings: list[Finding] = []

    def record_problem(problem: str) -> None:
        findings.append(Finding("record", 0, "", problem, "acceptance"))

    scenarios = [s for s in _all_scenarios(root, feature_glob) if s.workstream == workstream]
    in_scope = [s for s in scenarios if not s.gated]
    gated = [s for s in scenarios if s.gated]
    summary.total = len(in_scope)
    summary.gated = [f"{s.file.name}: {s.name}" for s in gated]
    record = _load_json(root / ACCEPTANCE_DIR / f"{workstream}.json")
    if record is None:
        record_problem(f"record {ACCEPTANCE_DIR}{workstream}.json missing or not valid JSON")
        summary.findings = len(findings)
        return findings, summary
    summary.sha = str(record.get("testedCommit", ""))
    if record.get("schemaVersion") != 1:
        record_problem("schemaVersion must be 1")
    if record.get("workstream") != workstream:
        record_problem(f"workstream is {record.get('workstream')}, expected {workstream}")
    tested = str(record.get("testedCommit", ""))
    if not SHA40.match(tested):
        record_problem("testedCommit must be 40 hex characters")
    else:
        problem = _commit_problem(root, tested)
        if problem:
            record_problem(problem)
    summary.unresolved_gates = [str(g) for g in record.get("unresolvedGates") or []]
    if gated and not summary.unresolved_gates:
        record_problem("gated scenarios but no unresolved gate named")
    runs = {r.get("id"): r for r in record.get("runs") or [] if isinstance(r, dict)}
    entries: dict[tuple[str, str], list[dict]] = {}
    for entry in record.get("scenarios") or []:
        if isinstance(entry, dict):
            entries.setdefault((str(entry.get("feature")), str(entry.get("scenario"))), []).append(entry)
    known = {(s.file.name, s.name) for s in scenarios}
    for key in entries:
        if key not in known:
            findings.append(Finding(key[0], 0, key[1], "stale record entry", "acceptance"))
    for scenario in in_scope:
        before = len(findings)

        def add(problem: str, s: Scenario = scenario) -> None:
            findings.append(Finding(s.file.name, s.line, s.name, problem, "acceptance"))

        found = entries.get((scenario.file.name, scenario.name), [])
        if len(scenario.test_tags) != 1:
            add("no single test tag")
        elif not found:
            add("no result")
        elif len(found) > 1:
            add(f"{len(found)} results")
        else:
            entry = found[0]
            result = entry.get("result")
            if entry.get("tag") != scenario.test_tags[0]:
                add("tag changed since record")
            elif result not in RESULTS:
                add(f"invalid result {result}")
            elif result != "pass":
                add(f"not accepted: {result}")
            else:
                problem = _evidence_problem(root, scenario, entry, runs)
                if problem:
                    add(problem)
        if len(findings) == before:
            summary.passed += 1
    summary.findings = len(findings)
    return findings, summary


def record_template(root: Path, workstream: str, feature_glob: str = DEFAULT_FEATURE_GLOB) -> dict:
    root = Path(root)
    scenarios = [s for s in _all_scenarios(root, feature_glob) if s.workstream == workstream]
    gates = sorted({(s.file.name, s.rule) for s in scenarios if s.gated})
    return {
        "schemaVersion": 1,
        "workstream": workstream,
        "testedCommit": git_head(root),
        "recordedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "runs": [],
        "scenarios": [
            {
                "feature": s.file.name,
                "scenario": s.name,
                "tag": s.test_tags[0] if s.test_tags else "",
                "result": "blocked",
                "run": None,
            }
            for s in scenarios
            if not s.gated
        ],
        "unresolvedGates": [f"{f}: {rule or 'whole feature'}: name the owner decision or pending run" for f, rule in gates],
    }


def _accepted_main(root: Path, workstream: str, feature_glob: str) -> int:
    findings, summary = accepted(root, workstream, feature_glob)
    for f in findings:
        if f.file == "record":
            print(f"{workstream}: record: {f.problem}")
        else:
            print(f"{workstream}: {f.file}: {f.scenario}: {f.problem}")
    for line in summary.lines():
        print(line)
    return 1 if findings else 0


class _Parser(argparse.ArgumentParser):
    def error(self, message: str):  # usage errors are exit 2, never an exception trace
        raise ValueError(message)


def main(argv: list[str] | None = None) -> int:
    parser = _Parser(description="BDD traceability checker")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
    parser.add_argument("--features", default=DEFAULT_FEATURE_GLOB)
    parser.add_argument("--landed", default=None)
    parser.add_argument("--accepted", default=None, metavar="WS")
    parser.add_argument("--record-template", default=None, metavar="WS")
    try:
        args = parser.parse_args(argv)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except SystemExit as exc:
        return 2 if exc.code else 0
    root = Path(args.root)
    if args.accepted is not None or args.record_template is not None:
        if args.accepted is not None and args.record_template is not None:
            print("error: --accepted and --record-template are mutually exclusive", file=sys.stderr)
            return 2
        workstream = args.accepted if args.accepted is not None else args.record_template
        if not workstream.strip():
            print("error: empty workstream", file=sys.stderr)
            return 2
        if args.accepted is not None:
            return _accepted_main(root, workstream, args.features)
        print(json.dumps(record_template(root, workstream, args.features), indent=2))
        return 0
    landed_path = Path(args.landed) if args.landed else root / "scripts/quality-gates/bdd_landed.txt"
    findings, summary = analyse(root, args.features, read_landed(landed_path))
    for f in findings:
        print(format_finding(f))
    print(summary.line())
    return 1 if any(f.kind != "pending" for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
