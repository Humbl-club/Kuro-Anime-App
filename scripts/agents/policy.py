#!/usr/bin/env python3
"""Read-only Kuro source routing and policy validation (Python stdlib only)."""

import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = "agents/routes.yaml"
CLAUDE_MANIFEST = ".claude/adapter.json"


class PolicyError(ValueError):
    pass


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise PolicyError("Duplicate configuration key: " + key)
        result[key] = value
    return result


def read_json(path):
    try:
        return json.loads(path.read_text(), object_pairs_hook=unique_object)
    except (OSError, ValueError) as error:
        raise PolicyError("Cannot read {}: {}".format(path, error)) from error


def relative_path(root, value):
    if not isinstance(value, str) or not value or "\\" in value:
        raise PolicyError("Expected a nonempty repository-relative POSIX path")
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        raise PolicyError("Path must stay inside the repository: " + value)
    try:
        (root / path).resolve().relative_to(root.resolve())
    except ValueError as error:
        raise PolicyError("Path resolves outside the repository: " + value) from error
    return path.as_posix()


def string_list(value, label):
    if not isinstance(value, list) or not value or any(
        not isinstance(item, str) or not item.strip() for item in value
    ):
        raise PolicyError(label + " must be a nonempty string list")
    if len(value) != len(set(value)):
        raise PolicyError(label + " contains duplicates")
    return value


def matches(path, pattern):
    # Match path segments: '*' cannot accidentally route across directories.
    parts, globs = Path(path).parts, Path(pattern).parts

    def walk(i, j):
        if j == len(globs):
            return i == len(parts)
        if globs[j] == "**":
            return walk(i, j + 1) or (i < len(parts) and walk(i + 1, j))
        return i < len(parts) and fnmatch.fnmatchcase(parts[i], globs[j]) and walk(i + 1, j + 1)

    return walk(0, 0)


def historical(path):
    return path == "archive" or path.startswith("archive/")


def retired(path):
    return "SupabaseService" in Path(path).name


def references(root, values, label):
    for value in string_list(values, label):
        path = relative_path(root, value)
        target = (root / path).resolve().relative_to(root.resolve()).as_posix()
        if historical(path) or historical(target):
            raise PolicyError(label + " uses historical material as authority: " + path)
        if retired(path) or retired(target):
            raise PolicyError(label + " uses a retired owner: " + path)
        if not (root / path).exists():
            raise PolicyError(label + " references missing path: " + path)


def frontmatter(path):
    lines = path.read_text().splitlines()
    if not lines or lines[0] != "---":
        raise PolicyError("Missing agent frontmatter: " + str(path))
    result = {}
    for line in lines[1:]:
        if line == "---":
            return result
        if ":" not in line:
            raise PolicyError("Expected scalar agent frontmatter: " + str(path))
        key, value = line.split(":", 1)
        if key in result:
            raise PolicyError("Duplicate agent field: " + key)
        result[key] = value.strip()
    raise PolicyError("Unclosed agent frontmatter: " + str(path))


def validate(root, data):
    expected = {
        "schema_version", "format", "authority", "profiles",
        "checks", "routes", "unmapped", "handoff_required",
    }
    if not isinstance(data, dict) or set(data) != expected:
        raise PolicyError("Invalid manifest fields (unknown or missing key)")
    if type(data["schema_version"]) is not int or data["schema_version"] != 2:
        raise PolicyError("Unsupported policy schema_version")
    references(root, data["authority"], "authority")
    string_list(data["handoff_required"], "handoff_required")
    for key in ("format", "unmapped"):
        if not isinstance(data[key], str) or not data[key].strip():
            raise PolicyError("Missing " + key)
    for key in ("profiles", "checks"):
        if not isinstance(data[key], dict) or not data[key]:
            raise PolicyError("Invalid " + key)
    for name, profile in data["profiles"].items():
        if not isinstance(profile, dict) or set(profile) != {"require"} or not isinstance(profile["require"], str) or not profile["require"].strip():
            raise PolicyError("Invalid profile: " + name)
    for name, check in data["checks"].items():
        if not isinstance(check, dict) or set(check) != {"sources", "command_template", "proves"}:
            raise PolicyError("Invalid check: " + name)
        references(root, check["sources"], "check " + name)
        for field in ("command_template", "proves"):
            if not isinstance(check[field], str) or not check[field].strip():
                raise PolicyError("Missing check field: " + name + "." + field)
    if not isinstance(data["routes"], list) or not data["routes"]:
        raise PolicyError("No routes configured")
    seen = set()
    for route in data["routes"]:
        if not isinstance(route, dict) or set(route) != {"id", "paths", "sources", "checks", "profile", "contract"}:
            raise PolicyError("Invalid route fields")
        name = route["id"]
        if not isinstance(name, str) or not name or name in seen:
            raise PolicyError("Missing or duplicate route id")
        seen.add(name)
        if route["profile"] not in data["profiles"]:
            raise PolicyError("Unknown profile for route " + name)
        if not isinstance(route["contract"], str) or not route["contract"].strip():
            raise PolicyError("Missing verification contract for route " + name)
        for pattern in string_list(route["paths"], "route paths " + name):
            relative_path(root, pattern)
            if historical(pattern) or pattern in ("*", "**", "**/*"):
                raise PolicyError("Historical or catch-all route pattern: " + pattern)
        references(root, route["sources"], "route " + name)
        for check in string_list(route["checks"], "route checks " + name):
            if check not in data["checks"]:
                raise PolicyError("Unknown check: " + check)
    if len((root / "AGENTS.md").read_text().splitlines()) >= 200:
        raise PolicyError("AGENTS.md must remain under 200 lines")
    return data


def validate_claude(root, data, adapter):
    """Explicit optional adapter validation; never applies settings or runs hooks."""
    if not isinstance(adapter, dict) or set(adapter) != {"schema_version", "workers", "settings", "main_model"}:
        raise PolicyError("Invalid Claude adapter")
    if type(adapter["schema_version"]) is not int or adapter["schema_version"] != 1:
        raise PolicyError("Unsupported Claude adapter schema_version")
    if not isinstance(adapter["workers"], dict) or not adapter["workers"]:
        raise PolicyError("No Claude workers configured")
    for name, worker in adapter["workers"].items():
        if set(worker) != {"file", "profile", "model", "effort", "tools"}:
            raise PolicyError("Invalid worker fields: " + name)
        references(root, [worker["file"]], "worker " + name)
        if worker["profile"] not in data["profiles"]:
            raise PolicyError("Unknown worker profile: " + name)
        tools = string_list(worker["tools"], "worker tools " + name)
        if worker["profile"] in ("discovery", "review") and not set(tools) <= {"Read", "Grep", "Glob"}:
            raise PolicyError("Read-only worker has execution/mutation tools: " + name)
        fields = frontmatter(root / worker["file"])
        for field, value in (("name", name), ("model", worker["model"]), ("effort", worker["effort"])):
            if fields.get(field) != value:
                raise PolicyError("Worker drift: {}.{}".format(name, field))
        if fields.get("omitClaudeMd", "false") != "false":
            raise PolicyError("Worker omits shared policy: " + name)
        if [item.strip() for item in fields.get("tools", "").split(",")] != tools:
            raise PolicyError("Worker tool drift: " + name)
        if not fields.get("description"):
            raise PolicyError("Missing worker description: " + name)
        if "AGENTS.md" not in (root / worker["file"]).read_text():
            raise PolicyError("Worker does not reference shared policy: " + name)
    references(root, [adapter["settings"]], "Claude settings")
    settings = read_json(root / adapter["settings"])
    if settings.get("env", {}).get("CLAUDE_CODE_DISABLE_ADVISOR_TOOL") != "1":
        raise PolicyError("Claude adapter must disable implicit server-side advisor routing")
    hooks = settings.get("hooks", {}).get("SessionStart", [])
    if not any(
        hook.get("type") == "command" and "scripts/agents/policy.py" in hook.get("command", "")
        and "--claude-start" in hook["command"]
        for group in hooks for hook in group.get("hooks", [])
    ):
        raise PolicyError("Claude startup policy hook is missing")
    for filename in ("CLAUDE.md",):
        if len((root / filename).read_text().splitlines()) >= 200:
            raise PolicyError(filename + " must remain under 200 lines")
    if "\n@AGENTS.md\n" not in (root / "CLAUDE.md").read_text():
        raise PolicyError("Claude adapter must import shared AGENTS.md")
    return adapter


def load(root=ROOT):
    return validate(root, read_json(root / MANIFEST))


def load_claude(root=ROOT, data=None):
    return validate_claude(root, data if data is not None else load(root), read_json(root / CLAUDE_MANIFEST))


def discover(root, data):
    """Publish validated route IDs and existing owner paths, without guessing intent."""
    return {
        "status": "route_catalog",
        "instruction": "Copy exact route IDs from this catalog. Sources exist locally, but confirm mounted callers. For other filenames use --files '<glob>' or rg --files before reading/searching a path. No checks are executed.",
        "routes": [
            {key: route[key] for key in ("id", "profile", "sources")}
            for route in data["routes"]
        ],
    }


def find_files(root, data, patterns, limit=80):
    """Bounded active-tree filename discovery; no file contents/provider config read."""
    for pattern in patterns:
        relative_path(root, pattern)
    if not 1 <= limit <= 500:
        raise PolicyError("--limit must be between 1 and 500")
    ignored = {"archive", "node_modules", "vendor", "Pods", "build", "DerivedData", "__pycache__"}
    found = {pattern: [] for pattern in patterns}
    for folder, directories, filenames in os.walk(root, followlinks=False):
        directories[:] = sorted(name for name in directories if not name.startswith(".") and name not in ignored and not (Path(folder) / name).is_symlink())
        for name in sorted(filenames):
            path = Path(folder) / name
            if name.startswith(".") or path.is_symlink() or retired(name):
                continue
            relative = path.relative_to(root).as_posix()
            for pattern in patterns:
                matched = matches(relative, pattern) if "/" in pattern else fnmatch.fnmatchcase(name, pattern)
                if matched:
                    found[pattern].append(relative)
    paths = sorted(set(path for group in found.values() for path in group))
    missing = [pattern for pattern, group in found.items() if not group]
    return {
        "status": "discovery_required" if missing else "file_candidates",
        "files": paths[:limit],
        "routes_by_file": {path: [route["id"] for route in data["routes"] if any(matches(path, pattern) for pattern in route["paths"])] for path in paths[:limit]},
        "unmatched_patterns": missing,
        "total_matches": len(paths),
        "truncated": len(paths) > limit,
        "scope": "Active non-hidden tree; excludes archive, dependency/build/cache directories, symlinks and retired SupabaseService names. Filename lookup only, not content/ownership proof.",
        "instruction": "Use returned exact paths for reads/searches; narrow patterns if truncated. No matches means broaden discovery, never synthesize a directory or silently choose a substitute.",
    }


def resolve(root, data, paths=(), route_ids=()):
    by_id = {route["id"]: route for route in data["routes"]}
    unknown_ids = sorted(set(route_ids) - set(by_id))
    if unknown_ids:
        raise PolicyError("Unknown routes: {}. Run --discover first; valid IDs: {}".format(
            ", ".join(unknown_ids), ", ".join(by_id)))
    normalized = [relative_path(root, path) for path in paths]
    missing = [path for path in normalized if not (root / path).exists()]
    selected = set(route_ids)
    unmapped = []
    for path in normalized:
        target = (root / path).resolve().relative_to(root.resolve()).as_posix()
        usable = not any((historical(path), historical(target), retired(path), retired(target)))
        found = [route["id"] for route in data["routes"] if usable and any(matches(path, pattern) for pattern in route["paths"])]
        if not found:
            unmapped.append(path)
        selected.update(found)
    routes = [route for route in data["routes"] if route["id"] in selected]
    check_ids = list(dict.fromkeys(check for route in routes for check in route["checks"]))
    return {
        "status": "discovery_required" if unmapped or missing else "context_candidates",
        "paths": normalized,
        "missing_paths": missing,
        "unmapped": unmapped,
        "instruction": "Missing input paths are not verified sources. Run --discover and --files '<glob>' before reading/searching; planned new paths still require existing-owner discovery." if missing else data["unmapped"] if unmapped else "Confirm mounted owners/callers and applicable contracts before editing. Suggested checks are not executed or authorized by this command.",
        "authority": data["authority"],
        "routes": routes,
        "checks": {name: data["checks"][name] for name in check_ids},
        "handoff_required": data["handoff_required"],
        "model_policy": "Select by verified task capability; no automatic model switch or guarantee of correctness.",
    }


def rpc_definitions(root, name):
    """Lexical CREATE FUNCTION candidates, not an effective/deployed schema parser."""
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        raise PolicyError("RPC lookup needs one unqualified SQL identifier")
    pattern = re.compile(
        r'^[ \t]*create\s+(?:or\s+replace\s+)?function\s+'
        r'(?:(?:public|"public")\s*\.\s*)?"?' + re.escape(name) + r'"?\s*\(',
        re.IGNORECASE | re.MULTILINE,
    )
    candidates = []
    for folder in ("supabase/migrations", "supabase/prepared-migrations"):
        for path in (root / folder).glob("*.sql"):
            relative_path(root, path.relative_to(root).as_posix())
            raw = path.read_bytes()
            text = raw.decode("utf-8")
            for match in pattern.finditer(text):
                candidates.append({
                    "path": path.relative_to(root).as_posix(),
                    "line": text.count("\n", 0, match.start()) + 1,
                    "source_folder": folder,
                    "sha256": hashlib.sha256(raw).hexdigest(),
                })
    return sorted(candidates, key=lambda item: (Path(item["path"]).name, item["line"], item["path"]))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="Repository root (also supports isolated fixtures)")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--check-claude", action="store_true", help="Explicitly validate the optional Claude adapter as data")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--discover", action="store_true", help="First step: list valid route IDs and verified existing owner paths")
    parser.add_argument("--files", nargs="+", action="extend", default=[], help="Find exact existing active-tree filenames using quoted globs; repeatable")
    parser.add_argument("--limit", type=int, default=80, help="Maximum file candidates (1..500; default 80)")
    parser.add_argument("--claude-start", action="store_true")
    parser.add_argument("--paths", nargs="+", default=[])
    parser.add_argument("--route", action="append", default=[])
    parser.add_argument("--rpc", action="append", default=[], help="List local SQL definition candidates; repeat for internal callees")
    args = parser.parse_args(argv)
    if (args.discover or args.files) and (args.paths or args.route or args.rpc or args.check or args.check_claude or args.claude_start or args.list or (args.discover and args.files)):
        parser.error("Run --discover or --files separately before route selection/checks")
    root = args.root.resolve()
    try:
        if args.claude_start:
            # Worktree-aware: walk from hook cwd; never evaluate arbitrary commands.
            event = json.load(sys.stdin)
            if not isinstance(event, dict):
                raise PolicyError("Invalid Claude hook input")
            cwd = Path(event.get("cwd", str(root))).resolve()
            candidates = [cwd] + list(cwd.parents)
            root = next((candidate for candidate in candidates if (candidate / MANIFEST).is_file()), root)
        data = load(root)
        if args.claude_start or args.check_claude:
            load_claude(root, data)
        if args.claude_start:
            context = (
                "Kuro shared policy validation PASS at {}. AGENTS.md overrides personal always-multiple-personas defaults for Kuro. "
                "First discovery command: python3 scripts/agents/policy.py --discover. Copy valid route IDs and owner paths; "
                "for other files use --files '<glob>' before reads/searches. Never invent a route or directory. Then use --route <copied-id> or --paths <discovered-paths>, "
                "confirm current owners/callers, and choose focused verification before model selection. "
                "No builds, hosted calls or model invocations were performed."
            ).format(root)
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": context}}))
        elif args.discover:
            print(json.dumps(discover(root, data), indent=2))
        elif args.files:
            result = find_files(root, data, args.files, args.limit)
            print(json.dumps(result, indent=2))
            return 2 if result["status"] == "discovery_required" else 0
        elif args.paths or args.route or args.rpc:
            route_ids = args.route or (["database"] if args.rpc and not args.paths else [])
            result = resolve(root, data, args.paths, route_ids)
            if args.rpc:
                result["rpc_definitions"] = {name: rpc_definitions(root, name) for name in args.rpc}
                result["unresolved_rpcs"] = [name for name, definitions in result["rpc_definitions"].items() if not definitions]
                result["sql_evidence_limit"] = "Lexical candidates ordered by filename/line, not a SQL parser or execution order. Inspect every later definition and relevant callee. Neither folder proves applied/unapplied or hosted parity; use exact dated receipts or fresh owning-service evidence."
                if result["unresolved_rpcs"]:
                    result["status"] = "discovery_required"
            print(json.dumps(result, indent=2))
            return 2 if result["status"] == "discovery_required" else 0
        elif args.list:
            for route in data["routes"]:
                print("{} [{}]".format(route["id"], route["profile"]))
        elif args.check_claude:
            print("PASS: shared policy and explicit Claude adapter validation")
        elif args.check:
            print("PASS: shared policy, {} routes and references (provider-neutral)".format(len(data["routes"])))
        else:
            parser.error("Start with --discover; use --files for filenames, then --paths/--route/--rpc. Validation: --check or --check-claude")
    except (PolicyError, OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        if args.claude_start:
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "Kuro policy validation FAILED; resolve configuration before editing: " + str(error)}}))
        else:
            print("FAIL: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
