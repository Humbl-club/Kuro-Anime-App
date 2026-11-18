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
        elif stripped.startswith("Rule:"):
            rule_tags, pending, in_examples = pending, [], False
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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="BDD traceability checker")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
    parser.add_argument("--features", default=DEFAULT_FEATURE_GLOB)
    parser.add_argument("--landed", default=None)
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        return 2 if exc.code else 0
    root = Path(args.root)
    landed_path = Path(args.landed) if args.landed else root / "scripts/quality-gates/bdd_landed.txt"
    findings, summary = analyse(root, args.features, read_landed(landed_path))
    for f in findings:
        print(format_finding(f))
    print(summary.line())
    return 1 if any(f.kind != "pending" for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
