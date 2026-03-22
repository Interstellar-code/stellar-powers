#!/usr/bin/env python3
"""Stellar Powers metrics packager.

Shipped with the plugin. Called by skills to package workflow metrics.

Usage:
  SP_WF_ID="xxx" python3 "${CLAUDE_PLUGIN_ROOT}/scripts/metrics-packager.py"
  SP_WF_ID="xxx" python3 "${CLAUDE_PLUGIN_ROOT}/scripts/metrics-packager.py" --partial --stage brainstorming
  SP_WF_ID="xxx" python3 "${CLAUDE_PLUGIN_ROOT}/scripts/metrics-packager.py" --prune

Env vars (all optional except SP_WF_ID):
  SP_WF_ID     - workflow ID (required)
  SP_REPO      - repo name
  SP_TASK_TYPE - feature/bugfix/refactoring/porting
  SP_VERSION   - stellar-powers version
  SP_TOPIC     - workflow topic

Flags:
  --partial          Create a partial package (-partial.json suffix)
  --stage NAME       Stage name for partial packages (e.g., brainstorming)
  --prune            After packaging, prune workflow.jsonl (replace details with summary)
"""
import json
import os
import sys
from datetime import datetime, timezone

# Parse args
partial = "--partial" in sys.argv
prune = "--prune" in sys.argv
stage = None
if "--stage" in sys.argv:
    idx = sys.argv.index("--stage")
    if idx + 1 < len(sys.argv):
        stage = sys.argv[idx + 1]

cwd = os.getcwd()
wf_file = os.path.join(cwd, ".stellar-powers", "workflow.jsonl")
wf_id = os.environ.get("SP_WF_ID", "")
if not wf_id:
    print("ERROR: SP_WF_ID not set", file=sys.stderr)
    sys.exit(1)

if not os.path.exists(wf_file):
    print(f"ERROR: workflow.jsonl not found at {wf_file}", file=sys.stderr)
    sys.exit(1)

# Read events for this workflow
events = []
with open(wf_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            evt = json.loads(line)
            if evt.get("workflow_id") == wf_id:
                events.append(evt)
        except Exception:
            continue

# Load .active-workflow if present
aw_path = os.path.join(cwd, ".stellar-powers", ".active-workflow")
aw = {}
if os.path.exists(aw_path):
    try:
        aw = json.load(open(aw_path))
    except Exception:
        pass

repo = os.environ.get("SP_REPO") or aw.get("repo") or "unknown"
task_type = os.environ.get("SP_TASK_TYPE") or aw.get("task_type") or "unknown"
sp_version = os.environ.get("SP_VERSION") or aw.get("sp_version") or "unknown"
topic = os.environ.get("SP_TOPIC") or aw.get("topic") or "unknown"

# Extract timeline
started = ""
completed = ""
duration = 0
completion_feedback = ""
outcome = "partial" if partial else "unknown"
for e in events:
    if e.get("event") == "skill_invocation" and not started:
        started = e.get("ts", "")
    if e.get("event") == "workflow_completed":
        completed = e.get("ts", "")
        d = e.get("data", {})
        duration = d.get("duration_minutes") or 0
        completion_feedback = d.get("completion_feedback") or ""
        outcome = d.get("outcome") or "success"

if started and completed:
    try:
        start_dt = datetime.fromisoformat(started.replace("Z", "+00:00"))
        end_dt = datetime.fromisoformat(completed.replace("Z", "+00:00"))
        duration = int((end_dt - start_dt).total_seconds() / 60)
    except Exception:
        duration = 0

# Extract skills chain
skills_seen = []
for e in events:
    if e.get("event") == "skill_invocation":
        s = e.get("data", {}).get("skill", "")
        if s and s not in skills_seen:
            skills_seen.append(s)

# Per-skill metrics
skills_data = {}
for skill in skills_seen:
    skill_events = [e for e in events if e.get("data", {}).get("skill") == skill]
    steps_completed = sum(1 for e in skill_events if e.get("event") == "step_completed")
    steps_total = max(
        [e.get("data", {}).get("step_number", 0) for e in skill_events
         if e.get("event") in ("step_started", "step_completed")] or [0]
    )
    corrections = [
        {"step": e["data"].get("context", ""), "feedback": e["data"].get("correction", "")}
        for e in skill_events if e.get("event") == "user_correction"
    ]
    review_verdicts = [
        e["data"].get("verdict", "") for e in events
        if e.get("event") == "review_verdict" and e.get("workflow_id") == wf_id
    ]
    violations = {}
    for e in events:
        if e.get("event") == "hook_violation" and e.get("workflow_id") == wf_id:
            vtype = e.get("data", {}).get("type", "unknown")
            violations[vtype] = violations.get(vtype, 0) + 1
    skills_data[skill] = {
        "steps_completed": steps_completed,
        "steps_total": steps_total,
        "corrections": corrections,
        "review_iterations": len(review_verdicts),
        "review_verdicts": review_verdicts,
        "violations": [{"type": k, "count": v} for k, v in violations.items()],
    }

tasks = [
    {"id": e["data"].get("task_id", ""), "subject": e["data"].get("task_subject", ""), "status": "completed"}
    for e in events if e.get("event") == "task_completed"
]

user_messages = [
    {
        "timestamp": e.get("ts", ""),
        "context": f"{e['data'].get('active_skill', '')}/{e['data'].get('active_step', '')}",
        "preview": e["data"].get("prompt_preview", ""),
    }
    for e in events if e.get("event") == "user_message"
]

ai_responses = [
    {
        "timestamp": e.get("ts", ""),
        "context": e["data"].get("active_skill", ""),
        "preview": e["data"].get("response_preview", ""),
    }
    for e in events if e.get("event") == "turn_completed"
]

tool_failures = [
    {"tool": e["data"].get("tool_name", ""), "error": e["data"].get("error_preview", "")}
    for e in events if e.get("event") == "tool_failure"
]

artifacts = []
for e in events:
    if e.get("event") in ("spec_created", "plan_created"):
        p = e.get("data", {}).get("path", "")
        if p:
            artifacts.append(p)

package = {
    "package_version": "1.0",
    "workflow_id": wf_id,
    "stellar_powers_version": sp_version,
    "context": {
        "repo": repo,
        "task_type": task_type,
        "skills_chain": skills_seen,
    },
    "timeline": {
        "started": started,
        "completed": completed,
        "duration_minutes": duration,
        "user_confirmed_complete": not partial,
    },
    "skills": skills_data,
    "tasks": tasks,
    "user_messages": user_messages,
    "ai_responses": ai_responses,
    "tool_failures": tool_failures,
    "artifacts": artifacts,
    "completion_feedback": completion_feedback,
    "outcome": outcome,
}

if stage:
    package["stage"] = stage

# Write package
metrics_dir = os.path.join(cwd, ".stellar-powers", "metrics")
os.makedirs(metrics_dir, exist_ok=True)
date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
suffix = "-partial" if partial else ""
pkg_path = os.path.join(metrics_dir, f"{date_str}-{topic}-{wf_id[:8]}{suffix}.json")

# Remove old partials for this workflow if creating a new one
if partial:
    for f_name in os.listdir(metrics_dir):
        if wf_id[:8] in f_name and f_name.endswith("-partial.json"):
            os.remove(os.path.join(metrics_dir, f_name))

# If full package, also remove partials (full supersedes)
if not partial:
    for f_name in os.listdir(metrics_dir):
        if wf_id[:8] in f_name and f_name.endswith("-partial.json"):
            os.remove(os.path.join(metrics_dir, f_name))

with open(pkg_path, "w") as f:
    json.dump(package, f, indent=2)

# Verify
with open(pkg_path) as f:
    json.load(f)

print(f"METRICS_PACKAGE={pkg_path}")

# Prune workflow.jsonl if requested
if prune:
    kept = []
    with open(wf_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                evt = json.loads(line)
                if evt.get("workflow_id") != wf_id:
                    kept.append(line)
            except Exception:
                kept.append(line)

    # Build summary
    completed_evt = next((e for e in events if e.get("event") == "workflow_completed"), {})
    started_evt = next((e for e in events if e.get("event") in ("skill_invocation", "workflow_started")), {})
    summary = {
        "ts": completed_evt.get("ts", started_evt.get("ts", "")),
        "event": "workflow_summary",
        "workflow_id": wf_id,
        "session": "",
        "data": {
            "skill_chain": skills_seen,
            "topic": topic,
            "repo": repo,
            "task_type": task_type,
            "sp_version": sp_version,
            "started": started_evt.get("ts", ""),
            "completed": completed_evt.get("ts", ""),
            "duration_minutes": duration,
            "outcome": outcome,
            "steps_completed": sum(1 for e in events if e.get("event") == "step_completed"),
            "steps_total": max([e.get("data", {}).get("step_number", 0) for e in events if e.get("event") == "step_started"] or [0]),
            "corrections": sum(1 for e in events if e.get("event") == "user_correction"),
            "review_iterations": sum(1 for e in events if e.get("event") == "review_verdict"),
            "violations": sum(1 for e in events if e.get("event") == "hook_violation"),
            "tasks_completed": len(tasks),
            "artifacts": artifacts,
        },
    }
    kept.append(json.dumps(summary))

    tmp_path = wf_file + ".tmp"
    with open(tmp_path, "w") as f:
        f.write("\n".join(kept) + "\n")
    os.rename(tmp_path, wf_file)
    print("PRUNED=true")
