# Kuro routing adapter

Follow root `AGENTS.md` and `agents/routes.yaml`. The shared single-agent default
explicitly overrides personal always-multiple-personas instructions for Kuro.
Resolve current owners/callers and verification before model/worker selection.
Use `python3 scripts/agents/policy.py --paths <paths>` or `--route <id>`.
Workers are optional; comparisons and nontrivial changes do not automatically
require fan-out. Sensitive independent review follows the shared policy.
