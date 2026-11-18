# Kuro routing adapter

Follow root `AGENTS.md` and `agents/routes.yaml`. The shared single-agent default
explicitly overrides personal always-multiple-personas instructions for Kuro.
Resolve current owners/callers and verification before model/worker selection.
Start with `python3 scripts/agents/policy.py --discover`; copy valid route IDs and
existing owner paths. Use `--files '<glob>'` or native Glob before scoped reads or
searches outside those paths. Never infer directories/route names. Shell-less
workers receive catalog output from the lead and use Glob for further discovery.
Workers are optional; comparisons and nontrivial changes do not automatically
require fan-out. Sensitive independent review follows the shared policy.
