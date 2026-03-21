---
name: executing-plans
description: Use when you have a written implementation plan to execute in a separate session with review checkpoints
---

## Workflow Logging

On invocation, generate a workflow ID and log:

```bash
WF_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
mkdir -p .stellar-powers

# Chain detection — inherit workflow_id if writing-plans is the active skill
if [ -f ".stellar-powers/.active-workflow" ]; then
  EXISTING_SKILL=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('skill',''))" 2>/dev/null)
  if [ "$EXISTING_SKILL" = "writing-plans" ]; then
    WF_ID=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('workflow_id',''))" 2>/dev/null)
  fi
fi

echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"skill_invocation\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"executing-plans\",\"args\":\"\"}}" >> .stellar-powers/workflow.jsonl

# Update .active-workflow with current skill
python3 -c "
import json, os
aw_path = '.stellar-powers/.active-workflow'
aw = {}
if os.path.exists(aw_path):
    try: aw = json.load(open(aw_path))
    except: pass
aw['skill'] = 'executing-plans'
aw['workflow_id'] = '${WF_ID}'
json.dump(aw, open(aw_path, 'w'))
" 2>/dev/null
```

After each task completion, log:

```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"task_completed\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"task\":\"TASK_NAME\",\"status\":\"complete\"}}" >> .stellar-powers/workflow.jsonl
```

When all tasks are done:

```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"plan_executed\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"plan_path\":\"PLAN_PATH\",\"status\":\"complete\"}}" >> .stellar-powers/workflow.jsonl
```

Check `.stellar-powers/workflow.jsonl` for incomplete executing-plans workflows. If found, load the most recent workflow's context to inform your work. Do not re-prompt the user.

# Executing Plans

## Overview

Load plan, review critically, execute all tasks, report when complete.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Note:** Tell your human partner that Stellar Powers works much better with access to subagents. The quality of its work will be significantly higher if run on a platform with subagent support (such as Claude Code or Codex). If subagents are available, use stellar-powers:subagent-driven-development instead of this skill.

## The Process

### Step 1: Load and Review Plan
1. Read plan file
2. Review critically - identify any questions or concerns about the plan
3. If concerns: Raise them with your human partner before starting
4. If no concerns: Create TodoWrite and proceed

### Step 2: Execute Tasks

For each task:
1. Mark as in_progress
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. Mark as completed

### Step 3: Complete Development

After all tasks complete and verified:
- Announce: "I'm using the finishing-a-development-branch skill to complete this work."
- **REQUIRED SUB-SKILL:** Use stellar-powers:finishing-a-development-branch
- Follow that skill to verify tests, present options, execute choice

## When to Stop and Ask for Help

**STOP executing immediately when:**
- Hit a blocker (missing dependency, test fails, instruction unclear)
- Plan has critical gaps preventing starting
- You don't understand an instruction
- Verification fails repeatedly

**Ask for clarification rather than guessing.**

## When to Revisit Earlier Steps

**Return to Review (Step 1) when:**
- Partner updates the plan based on your feedback
- Fundamental approach needs rethinking

**Don't force through blockers** - stop and ask.

## Remember
- Review plan critically first
- Follow plan steps exactly
- Don't skip verifications
- Reference skills when plan says to
- Stop when blocked, don't guess
- Never start implementation on main/master branch without explicit user consent

## Completion Checkpoint

After all tasks complete and the finishing-a-development-branch skill is done, present the completion checkpoint:

"All tasks completed and reviewed. Is the workflow implementation now complete?

a) Yes, complete — I'll package the metrics and close this workflow
b) Not yet — what's remaining?
c) Complete, and here's my feedback: [user types feedback]"

**On user confirming complete (a or c):**

1. Log workflow_completed event:
```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"workflow_completed\",\"workflow_id\":\"${WF_ID}\",\"session\":\"${CLAUDE_SESSION_ID:-}\",\"data\":{\"skill\":\"executing-plans\",\"duration_minutes\":DURATION,\"steps_completed\":N,\"steps_total\":TOTAL,\"outcome\":\"success\",\"completion_feedback\":\"USER_FEEDBACK_OR_EMPTY\"}}" >> .stellar-powers/workflow.jsonl
```

2. Export env vars from .active-workflow:
```bash
export SP_WF_ID="${WF_ID}"
export SP_REPO=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('repo','unknown'))" 2>/dev/null || echo "unknown")
export SP_TASK_TYPE=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('task_type','unknown'))" 2>/dev/null || echo "unknown")
export SP_VERSION=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('sp_version','unknown'))" 2>/dev/null || echo "unknown")
export SP_TOPIC=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('topic','unknown'))" 2>/dev/null || echo "unknown")
```

3. Package metrics:
```bash
python3 << 'PYEOF'
import json, os, sys
from datetime import datetime

cwd = os.getcwd()
wf_file = os.path.join(cwd, ".stellar-powers", "workflow.jsonl")
wf_id = os.environ.get("SP_WF_ID", "")
if not wf_id:
    print("ERROR: SP_WF_ID not set", file=sys.stderr)
    sys.exit(1)

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
        except:
            continue

aw_path = os.path.join(cwd, ".stellar-powers", ".active-workflow")
aw = {}
if os.path.exists(aw_path):
    try:
        aw = json.load(open(aw_path))
    except:
        pass

repo = os.environ.get("SP_REPO") or aw.get("repo", "unknown")
task_type = os.environ.get("SP_TASK_TYPE") or aw.get("task_type", "unknown")
sp_version = os.environ.get("SP_VERSION") or aw.get("sp_version", "unknown")
topic = os.environ.get("SP_TOPIC") or aw.get("topic", "unknown")

started = ""
completed = ""
duration = 0
completion_feedback = ""
outcome = "unknown"
for e in events:
    if e.get("event") == "skill_invocation" and not started:
        started = e.get("ts", "")
    if e.get("event") == "workflow_completed":
        completed = e.get("ts", "")
        d = e.get("data", {})
        duration = d.get("duration_minutes", 0)
        completion_feedback = d.get("completion_feedback", "")
        outcome = d.get("outcome", "success")

if started and completed:
    try:
        start_dt = datetime.fromisoformat(started.replace('Z', '+00:00'))
        end_dt = datetime.fromisoformat(completed.replace('Z', '+00:00'))
        duration = int((end_dt - start_dt).total_seconds() / 60)
    except Exception:
        duration = 0

skills_seen = []
for e in events:
    if e.get("event") == "skill_invocation":
        s = e.get("data", {}).get("skill", "")
        if s and s not in skills_seen:
            skills_seen.append(s)

skills_data = {}
for skill in skills_seen:
    skill_events = [e for e in events if e.get("data", {}).get("skill") == skill]
    steps_completed = sum(1 for e in skill_events if e.get("event") == "step_completed")
    steps_total = max([e.get("data", {}).get("step_number", 0) for e in skill_events if e.get("event") in ("step_started", "step_completed")] or [0])
    corrections = [{"step": e["data"].get("context", ""), "feedback": e["data"].get("correction", "")}
                   for e in skill_events if e.get("event") == "user_correction"]
    review_verdicts = [e["data"].get("verdict", "") for e in events
                       if e.get("event") == "review_verdict" and e.get("workflow_id") == wf_id]
    review_iterations = len(review_verdicts)
    violations = {}
    for e in events:
        if e.get("event") == "hook_violation" and e.get("workflow_id") == wf_id:
            vtype = e.get("data", {}).get("type", "unknown")
            violations[vtype] = violations.get(vtype, 0) + 1
    skills_data[skill] = {
        "steps_completed": steps_completed,
        "steps_total": steps_total,
        "corrections": corrections,
        "review_iterations": review_iterations,
        "review_verdicts": review_verdicts,
        "violations": [{"type": k, "count": v} for k, v in violations.items()]
    }

tasks = [{"id": e["data"].get("task_id", ""), "subject": e["data"].get("task_subject", ""), "status": "completed"}
         for e in events if e.get("event") == "task_completed"]
user_messages = [{"timestamp": e.get("ts", ""), "context": f"{e['data'].get('active_skill', '')}/{e['data'].get('active_step', '')}",
                  "preview": e["data"].get("prompt_preview", "")}
                 for e in events if e.get("event") == "user_message"]
ai_responses = [{"timestamp": e.get("ts", ""), "context": e["data"].get("active_skill", ""),
                 "preview": e["data"].get("response_preview", "")}
                for e in events if e.get("event") == "turn_completed"]
tool_failures = [{"tool": e["data"].get("tool_name", ""), "error": e["data"].get("error_preview", "")}
                 for e in events if e.get("event") == "tool_failure"]
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
        "project_type": aw.get("project_type", "unknown"),
        "task_type": task_type,
        "skills_chain": skills_seen
    },
    "timeline": {
        "started": started,
        "completed": completed,
        "duration_minutes": duration,
        "user_confirmed_complete": True
    },
    "skills": skills_data,
    "tasks": tasks,
    "user_messages": user_messages,
    "ai_responses": ai_responses,
    "tool_failures": tool_failures,
    "artifacts": artifacts,
    "completion_feedback": completion_feedback
}

metrics_dir = os.path.join(cwd, ".stellar-powers", "metrics")
os.makedirs(metrics_dir, exist_ok=True)
date_str = datetime.utcnow().strftime("%Y-%m-%d")
pkg_path = os.path.join(metrics_dir, f"{date_str}-{topic}-{wf_id[:8]}.json")
with open(pkg_path, "w") as f:
    json.dump(package, f, indent=2)
with open(pkg_path) as f:
    json.load(f)
print(f"METRICS_PACKAGE={pkg_path}")
PYEOF
```

4. Prune workflow.jsonl:
```bash
python3 << 'PYEOF'
import json, os

cwd = os.getcwd()
wf_file = os.path.join(cwd, ".stellar-powers", "workflow.jsonl")
wf_id = os.environ.get("SP_WF_ID", "")
if not wf_id:
    import sys; print("ERROR: SP_WF_ID not set", file=sys.stderr); sys.exit(1)

kept = []
pruned_events = []

with open(wf_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            evt = json.loads(line)
            if evt.get("workflow_id") == wf_id:
                pruned_events.append(evt)
            else:
                kept.append(line)
        except:
            kept.append(line)

skills_seen = []
for e in pruned_events:
    if e.get("event") == "skill_invocation":
        s = e.get("data", {}).get("skill", "")
        if s and s not in skills_seen:
            skills_seen.append(s)

completed_evt = next((e for e in pruned_events if e.get("event") == "workflow_completed"), {})
started_evt = next((e for e in pruned_events if e.get("event") in ("skill_invocation", "workflow_started")), {})

corrections = sum(1 for e in pruned_events if e.get("event") == "user_correction")
review_iters = sum(1 for e in pruned_events if e.get("event") == "review_verdict")
violations = sum(1 for e in pruned_events if e.get("event") == "hook_violation")
tasks_done = sum(1 for e in pruned_events if e.get("event") == "task_completed")
steps_done = sum(1 for e in pruned_events if e.get("event") == "step_completed")
steps_total = max([e.get("data", {}).get("step_number", 0) for e in pruned_events if e.get("event") == "step_started"] or [steps_done])

artifacts = [e.get("data", {}).get("path", "") for e in pruned_events if e.get("event") in ("spec_created", "plan_created") and e.get("data", {}).get("path")]

aw = {}
aw_path = os.path.join(cwd, ".stellar-powers", ".active-workflow")
if os.path.exists(aw_path):
    try: aw = json.load(open(aw_path))
    except: pass

summary = {
    "ts": completed_evt.get("ts", started_evt.get("ts", "")),
    "event": "workflow_summary",
    "workflow_id": wf_id,
    "session": "",
    "data": {
        "skill_chain": skills_seen,
        "topic": os.environ.get("SP_TOPIC") or aw.get("topic", "unknown"),
        "repo": os.environ.get("SP_REPO") or aw.get("repo", "unknown"),
        "task_type": os.environ.get("SP_TASK_TYPE") or aw.get("task_type", "unknown"),
        "sp_version": os.environ.get("SP_VERSION") or aw.get("sp_version", "unknown"),
        "started": started_evt.get("ts", ""),
        "completed": completed_evt.get("ts", ""),
        "duration_minutes": completed_evt.get("data", {}).get("duration_minutes", 0),
        "outcome": completed_evt.get("data", {}).get("outcome", "unknown"),
        "steps_completed": steps_done,
        "steps_total": steps_total,
        "corrections": corrections,
        "review_iterations": review_iters,
        "violations": violations,
        "tasks_completed": tasks_done,
        "artifacts": artifacts
    }
}

kept.append(json.dumps(summary))

tmp_path = wf_file + ".tmp"
with open(tmp_path, "w") as f:
    f.write("\n".join(kept) + "\n")
os.rename(tmp_path, wf_file)
PYEOF
```

5. Cleanup:
```bash
rm -f .stellar-powers/.active-workflow
```

6. Report: "Workflow complete. Metrics packaged to .stellar-powers/metrics/. Run /stellar-powers:send-feedback to submit."

**On user saying "not yet" (b):**
Ask what's remaining and continue working. Do not close the workflow.

## Integration

**Required workflow skills:**
- **stellar-powers:using-git-worktrees** - REQUIRED: Set up isolated workspace before starting
- **stellar-powers:writing-plans** - Creates the plan this skill executes
- **stellar-powers:finishing-a-development-branch** - Complete development after all tasks
