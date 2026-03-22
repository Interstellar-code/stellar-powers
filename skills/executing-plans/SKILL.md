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

# MANDATORY: Create partial metrics snapshot at execution start
SP_WF_ID="${WF_ID}" python3 "${CLAUDE_PLUGIN_ROOT}/scripts/metrics-packager.py" --partial --stage execution
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

2. Package metrics and prune workflow.jsonl:
```bash
# MANDATORY: Package metrics and prune workflow.jsonl
export SP_WF_ID="${WF_ID}"
export SP_REPO=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('repo') or 'unknown')" 2>/dev/null || echo "unknown")
export SP_TASK_TYPE=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('task_type') or 'unknown')" 2>/dev/null || echo "unknown")
export SP_VERSION=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('sp_version') or 'unknown')" 2>/dev/null || echo "unknown")
export SP_TOPIC=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('topic') or 'unknown')" 2>/dev/null || echo "unknown")
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/metrics-packager.py" --prune
```

3. Cleanup:
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
