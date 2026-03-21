#!/usr/bin/env python3
"""Test runner for stellar-powers hook scenarios."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent
SCENARIOS_DIR = Path(__file__).parent / "skill-scenarios"
HOOKS_DIR = REPO_ROOT / "hooks"


def setup_temp_dir(scenario: dict) -> Path:
    """Create a temp dir with .stellar-powers/ structure from scenario setup."""
    tmp = Path(tempfile.mkdtemp(prefix="sp-test-"))
    sp_dir = tmp / ".stellar-powers"
    sp_dir.mkdir(parents=True)

    setup = scenario.get("setup", {})

    # Write .active-workflow
    aw = setup.get("active_workflow")
    if aw:
        with open(sp_dir / ".active-workflow", "w") as f:
            json.dump(aw, f)

    # Write config.json if present
    config = setup.get("config")
    if config:
        with open(sp_dir / "config.json", "w") as f:
            json.dump(config, f)

    # Write initial workflow events
    events = setup.get("workflow_events", [])
    if events:
        workflow_id = (aw or {}).get("workflow_id", "")
        with open(sp_dir / "workflow.jsonl", "w") as f:
            from datetime import datetime, timezone
            ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            for ev in events:
                envelope = {"ts": ts, "workflow_id": workflow_id, "session": "test", **ev}
                f.write(json.dumps(envelope) + "\n")

    return tmp


def run_hook(hook_name: str, hook_input: dict, cwd: Path) -> bool:
    """Run a hook script with the given input JSON piped to stdin."""
    hook_path = HOOKS_DIR / hook_name
    if not hook_path.exists():
        print(f"  ERROR: hook not found: {hook_path}")
        return False

    full_input = {"cwd": str(cwd), "session_id": "test", **hook_input}
    input_json = json.dumps(full_input)

    result = subprocess.run(
        [str(hook_path)],
        input=input_json,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def read_events(cwd: Path) -> list:
    """Read all events from workflow.jsonl."""
    wf_file = cwd / ".stellar-powers" / "workflow.jsonl"
    if not wf_file.exists():
        return []
    events = []
    for line in wf_file.read_text().splitlines():
        line = line.strip()
        if line:
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return events


def check_assertions(scenario: dict, cwd: Path) -> tuple[bool, list[str]]:
    """Check expected assertions. Returns (passed, failures)."""
    expected = scenario.get("expected", {})
    events = read_events(cwd)
    failures = []

    # no_events assertion
    if expected.get("no_events"):
        if events:
            failures.append(f"Expected no events but found {len(events)}: {[e.get('event') for e in events]}")
        return len(failures) == 0, failures

    # event_types_present
    present_types = {e.get("event") for e in events}
    for et in expected.get("event_types_present", []):
        if et not in present_types:
            failures.append(f"Expected event type '{et}' not found in {present_types}")

    # workflow_id_correct
    expected_wf_id = expected.get("workflow_id_correct")
    if expected_wf_id:
        for ev in events:
            if ev.get("workflow_id") != expected_wf_id:
                failures.append(f"Event {ev.get('event')} has workflow_id '{ev.get('workflow_id')}', expected '{expected_wf_id}'")

    # event_field_values: {"event_type": {"dot.path": "expected_value"}}
    for event_type, field_checks in expected.get("event_field_values", {}).items():
        matching = [e for e in events if e.get("event") == event_type]
        if not matching:
            failures.append(f"No events of type '{event_type}' to check field values")
            continue
        ev = matching[0]
        for dot_path, expected_val in field_checks.items():
            # Resolve dot path
            parts = dot_path.split(".")
            val = ev
            for part in parts:
                if isinstance(val, dict):
                    val = val.get(part)
                else:
                    val = None
                    break
            if val != expected_val:
                failures.append(f"Event '{event_type}' field '{dot_path}': expected '{expected_val}', got '{val}'")

    def resolve_dot_path(ev: dict, dot_path: str):
        parts = dot_path.split(".")
        val = ev
        for part in parts:
            if isinstance(val, dict):
                val = val.get(part)
            else:
                return None
        return val

    # strings_not_present: {"event_type": {"dot.path": ["forbidden1", "forbidden2"]}}
    for event_type, field_checks in expected.get("strings_not_present", {}).items():
        matching = [e for e in events if e.get("event") == event_type]
        if not matching:
            failures.append(f"No events of type '{event_type}' to check strings_not_present")
            continue
        ev = matching[0]
        for dot_path, forbidden_list in field_checks.items():
            val = resolve_dot_path(ev, dot_path)
            if val is None:
                failures.append(f"Event '{event_type}' field '{dot_path}' is None, cannot check strings_not_present")
                continue
            val_str = str(val)
            for forbidden in forbidden_list:
                if forbidden in val_str:
                    failures.append(f"Event '{event_type}' field '{dot_path}' contains forbidden string: '{forbidden}'")

    # strings_present: {"event_type": {"dot.path": ["required1", "required2"]}}
    for event_type, field_checks in expected.get("strings_present", {}).items():
        matching = [e for e in events if e.get("event") == event_type]
        if not matching:
            failures.append(f"No events of type '{event_type}' to check strings_present")
            continue
        ev = matching[0]
        for dot_path, required_list in field_checks.items():
            val = resolve_dot_path(ev, dot_path)
            if val is None:
                failures.append(f"Event '{event_type}' field '{dot_path}' is None, cannot check strings_present")
                continue
            val_str = str(val)
            for required in required_list:
                if required not in val_str:
                    failures.append(f"Event '{event_type}' field '{dot_path}' missing required string: '{required}'")

    # field_max_length: {"event_type": {"dot.path": max_length}}
    for event_type, field_checks in expected.get("field_max_length", {}).items():
        matching = [e for e in events if e.get("event") == event_type]
        if not matching:
            failures.append(f"No events of type '{event_type}' to check field_max_length")
            continue
        ev = matching[0]
        for dot_path, max_len in field_checks.items():
            val = resolve_dot_path(ev, dot_path)
            if val is None:
                failures.append(f"Event '{event_type}' field '{dot_path}' is None, cannot check field_max_length")
                continue
            actual_len = len(str(val))
            if actual_len > max_len:
                failures.append(f"Event '{event_type}' field '{dot_path}': length {actual_len} exceeds max {max_len}")

    # metrics_package_exists: bool — check that at least one .json file exists in .stellar-powers/metrics/
    if expected.get("metrics_package_exists"):
        metrics_dir = cwd / ".stellar-powers" / "metrics"
        pkg_files = list(metrics_dir.glob("*.json")) if metrics_dir.exists() else []
        if not pkg_files:
            failures.append("metrics_package_exists: no .json files found in .stellar-powers/metrics/")

    # metrics_package_valid_json: bool — all .json files in metrics/ parse as valid JSON
    if expected.get("metrics_package_valid_json"):
        metrics_dir = cwd / ".stellar-powers" / "metrics"
        pkg_files = list(metrics_dir.glob("*.json")) if metrics_dir.exists() else []
        for pf in pkg_files:
            try:
                json.loads(pf.read_text())
            except json.JSONDecodeError as e:
                failures.append(f"metrics_package_valid_json: {pf.name} is not valid JSON: {e}")

    # metrics_fields_not_unknown: [field_name, ...] — in context object of first metrics package
    not_unknown_fields = expected.get("metrics_fields_not_unknown", [])
    if not_unknown_fields:
        metrics_dir = cwd / ".stellar-powers" / "metrics"
        pkg_files = list(metrics_dir.glob("*.json")) if metrics_dir.exists() else []
        if not pkg_files:
            failures.append("metrics_fields_not_unknown: no metrics package found to check")
        else:
            pkg = json.loads(pkg_files[0].read_text())
            field_map = {
                "repo": pkg.get("context", {}).get("repo"),
                "sp_version": pkg.get("stellar_powers_version"),
                "task_type": pkg.get("context", {}).get("task_type"),
            }
            for field in not_unknown_fields:
                val = field_map.get(field)
                if val is None or val == "unknown":
                    failures.append(f"metrics_fields_not_unknown: field '{field}' is '{val}'")

    # duration_minutes_gt_zero: bool — timeline.duration_minutes > 0 in first metrics package
    if expected.get("duration_minutes_gt_zero"):
        metrics_dir = cwd / ".stellar-powers" / "metrics"
        pkg_files = list(metrics_dir.glob("*.json")) if metrics_dir.exists() else []
        if not pkg_files:
            failures.append("duration_minutes_gt_zero: no metrics package found to check")
        else:
            pkg = json.loads(pkg_files[0].read_text())
            duration = pkg.get("timeline", {}).get("duration_minutes", 0)
            if not (isinstance(duration, (int, float)) and duration > 0):
                failures.append(f"duration_minutes_gt_zero: duration_minutes is {duration!r}")

    return len(failures) == 0, failures


TESTS_DIR = Path(__file__).parent


def run_scripts(scenario: dict, cwd: Path) -> list[str]:
    """Run scripts_to_run entries. Returns list of error messages."""
    errors = []
    for entry in scenario.get("scripts_to_run", []):
        raw_cmd = entry.get("command", "")
        # Substitute {TESTS_DIR} placeholder
        command = raw_cmd.replace("{TESTS_DIR}", str(TESTS_DIR))
        env = {**os.environ, **entry.get("env", {})}
        result = subprocess.run(
            command,
            shell=True,
            cwd=str(cwd),
            env=env,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            errors.append(f"Script '{command}' failed (exit {result.returncode}): {result.stderr.strip()}")
    return errors


def run_scenario(scenario_path: Path) -> bool:
    """Run a single scenario. Returns True if passed."""
    with open(scenario_path) as f:
        scenario = json.load(f)

    name = scenario.get("name", scenario_path.stem)
    description = scenario.get("description", "")
    print(f"\nScenario: {name}")
    print(f"  {description}")

    cwd = setup_temp_dir(scenario)
    try:
        # Run each hook
        for hook_entry in scenario.get("hooks_to_test", []):
            hook_name = hook_entry["hook"]
            hook_input = hook_entry.get("input", {})
            success = run_hook(hook_name, hook_input, cwd)
            if not success:
                print(f"  WARN: hook '{hook_name}' returned non-zero (hooks should always exit 0)")

        # Run scripts
        script_errors = run_scripts(scenario, cwd)
        for err in script_errors:
            print(f"  SCRIPT ERROR: {err}")

        # Check assertions
        passed, failures = check_assertions(scenario, cwd)
        if script_errors:
            passed = False
            failures = script_errors + failures
        if passed:
            print(f"  PASS")
        else:
            print(f"  FAIL")
            for f in failures:
                print(f"    - {f}")
        return passed
    finally:
        import shutil
        shutil.rmtree(cwd, ignore_errors=True)


def main():
    scenario_files = sorted(SCENARIOS_DIR.glob("*.json"))
    if not scenario_files:
        print(f"No scenario files found in {SCENARIOS_DIR}")
        sys.exit(1)

    total = 0
    passed = 0
    for sf in scenario_files:
        total += 1
        if run_scenario(sf):
            passed += 1

    score = int(passed / total * 100) if total else 0
    print(f"\n{total} scenarios, {passed} passed, score: {score}%")

    if passed < total:
        sys.exit(1)


if __name__ == "__main__":
    main()
