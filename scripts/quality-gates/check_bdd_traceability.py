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


def shape_findings(root: Path, scenario: Scenario, seen: set[str]) -> list[Finding]:
    rel = str(scenario.file.relative_to(root)) if scenario.file.is_relative_to(root) else str(scenario.file)
    out: list[Finding] = []

    def add(problem: str) -> None:
        out.append(Finding(rel, scenario.line, scenario.name, problem))

    if scenario.name in seen:
        add("duplicate scenario name")
    seen.add(scenario.name)
    for tag in scenario.test_tags:
        match = LAYER_TAG.match(tag)
        if match and match.group(1) not in LAYERS:
            add(f"unknown test layer {tag}")
    if any(t.startswith("@manual:") for t in scenario.test_tags) and "@owner-gate" not in scenario.all_tags:
        add("@manual needs @owner-gate")
    if not scenario.gated:
        count = len(scenario.test_tags)
        if count == 0:
            add("missing test tag")
        elif count > 1:
            add(f"{count} test tags ({', '.join(scenario.test_tags)})")
    return out


def feature_files(root: Path, feature_glob: str) -> list[Path]:
    return sorted(p for p in root.glob(feature_glob) if p.is_file())


def check(root: Path, feature_glob: str = DEFAULT_FEATURE_GLOB) -> list[Finding]:
    root = Path(root)
    findings: list[Finding] = []
    for path in feature_files(root, feature_glob):
        seen: set[str] = set()
        for scenario in parse_feature(path):
            findings.extend(shape_findings(root, scenario, seen))
    return findings


def format_finding(f: Finding) -> str:
    return f"{f.file}:{f.line}: {f.scenario}: {f.problem}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="BDD traceability checker")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
    parser.add_argument("--features", default=DEFAULT_FEATURE_GLOB)
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        return 2 if exc.code else 0
    root = Path(args.root)
    findings = check(root, args.features)
    for f in findings:
        print(format_finding(f))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
