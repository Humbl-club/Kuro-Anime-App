#!/usr/bin/env bash
# Small shared helpers for the focused native runners: real destination and executed tests.
kuro_ios_destination() {
  xcrun simctl list devices available --json | python3 -c '
import json,sys
rows=[]
for runtime,devices in json.load(sys.stdin).get("devices",{}).items():
    for d in devices:
        if d.get("isAvailable") and d.get("name")=="iPhone 17 Pro":
            rows.append((d.get("state")=="Booted",runtime,d["udid"]))
if not rows:
    sys.exit("No available iPhone 17 Pro simulator")
print("platform=iOS Simulator,id="+sorted(rows,reverse=True)[0][2])
'
}

kuro_verify_selected_ios_tests() {
  python3 - "$@" <<'PYTHON'
from pathlib import Path
import re,sys
log=Path(sys.argv[1]).read_text(errors="replace")
suites=sys.argv[2:]
passed=set(re.findall(r"Test case '([^']+)' passed",log))
if suites==["--any"]:
    if not passed:
        sys.exit("No selected test executions recorded")
    print(f"  selected target: {len(passed)} distinct passing method paths (parameter runs not inferred)")
    sys.exit(0)
counts={s:sum(name.startswith(s+"/") for name in passed) for s in suites}
missing=[s for s,n in counts.items() if n==0]
for suite,count in counts.items():
    print(f"  {suite}: {count} distinct passing method paths (parameter runs not inferred)")
if missing:
    sys.exit("Selected suites had no passing executions: "+", ".join(missing))
if not suites or not passed:
    sys.exit("No selected test executions recorded")
PYTHON
}
