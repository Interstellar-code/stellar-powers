---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** This should be run in a dedicated worktree (created by brainstorming skill).

**Save plans to:** `.stellar-powers/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

## Workflow Logging

On invocation, generate a workflow ID and log:

```bash
WF_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
mkdir -p .stellar-powers/specs .stellar-powers/plans
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"skill_invocation\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"writing-plans\",\"args\":\"\"}}" >> .stellar-powers/workflow.jsonl
```

**Chain detection** — Before using the generated WF_ID, check if this skill was invoked from brainstorming (i.e., .active-workflow exists with skill=brainstorming). If so, inherit the existing workflow_id:
```bash
if [ -f ".stellar-powers/.active-workflow" ]; then
  EXISTING_SKILL=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('skill',''))" 2>/dev/null)
  if [ "$EXISTING_SKILL" = "brainstorming" ]; then
    WF_ID=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('workflow_id',''))" 2>/dev/null)
  fi
fi
```

**Update .active-workflow** — After chain detection, update (or create) .active-workflow with skill="writing-plans":
```bash
REPO=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('repo',''))" 2>/dev/null || basename $(pwd))
ORIGINAL_START=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('started',''))" 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
TASK_TYPE=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('task_type',''))" 2>/dev/null || echo "unknown")
SP_VERSION=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('sp_version',''))" 2>/dev/null || echo "unknown")
cat > .stellar-powers/.active-workflow.tmp << AWEOF
{"workflow_id":"${WF_ID}","skill":"writing-plans","topic":"TOPIC","step":"workflow_setup","step_number":0,"started":"${ORIGINAL_START}","repo":"${REPO}","task_type":"${TASK_TYPE}","sp_version":"${SP_VERSION}"}
AWEOF
mv .stellar-powers/.active-workflow.tmp .stellar-powers/.active-workflow
```
Replace `TOPIC` with the actual topic being planned.

**Step logging** — At the start and end of each major step (scope check, file structure, task writing, plan review, execution handoff), log step_started and step_completed events:
```bash
# Log at step start (replace STEP_NAME and N with actual values)
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"step_started\",\"workflow_id\":\"${WF_ID}\",\"session\":\"${CLAUDE_SESSION_ID:-}\",\"data\":{\"skill\":\"writing-plans\",\"step\":\"STEP_NAME\",\"step_number\":N}}" >> .stellar-powers/workflow.jsonl

# Log at step end
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"step_completed\",\"workflow_id\":\"${WF_ID}\",\"session\":\"${CLAUDE_SESSION_ID:-}\",\"data\":{\"skill\":\"writing-plans\",\"step\":\"STEP_NAME\",\"step_number\":N}}" >> .stellar-powers/workflow.jsonl
```

Check `.stellar-powers/workflow.jsonl` for incomplete writing-plans workflows. If found, load the most recent workflow's context to inform your work. Do not re-prompt the user.

**Step tracking** — After each major phase, update .active-workflow with the current step:

After reading and understanding the spec:
```bash
python3 -c "
import json
aw = json.load(open('.stellar-powers/.active-workflow'))
aw['step'] = 'reading_spec'
aw['step_number'] = 1
json.dump(aw, open('.stellar-powers/.active-workflow.tmp', 'w'))
" && mv .stellar-powers/.active-workflow.tmp .stellar-powers/.active-workflow
```

After library verification (Context7):
```bash
python3 -c "
import json
aw = json.load(open('.stellar-powers/.active-workflow'))
aw['step'] = 'library_verification'
aw['step_number'] = 2
json.dump(aw, open('.stellar-powers/.active-workflow.tmp', 'w'))
" && mv .stellar-powers/.active-workflow.tmp .stellar-powers/.active-workflow
```

After writing all tasks:
```bash
python3 -c "
import json
aw = json.load(open('.stellar-powers/.active-workflow'))
aw['step'] = 'writing_tasks'
aw['step_number'] = 3
json.dump(aw, open('.stellar-powers/.active-workflow.tmp', 'w'))
" && mv .stellar-powers/.active-workflow.tmp .stellar-powers/.active-workflow
```

After plan review loop completes:
```bash
python3 -c "
import json
aw = json.load(open('.stellar-powers/.active-workflow'))
aw['step'] = 'plan_review'
aw['step_number'] = 4
json.dump(aw, open('.stellar-powers/.active-workflow.tmp', 'w'))
" && mv .stellar-powers/.active-workflow.tmp .stellar-powers/.active-workflow
```

Before execution handoff:
```bash
python3 -c "
import json
aw = json.load(open('.stellar-powers/.active-workflow'))
aw['step'] = 'execution_handoff'
aw['step_number'] = 5
json.dump(aw, open('.stellar-powers/.active-workflow.tmp', 'w'))
" && mv .stellar-powers/.active-workflow.tmp .stellar-powers/.active-workflow
```

After saving the plan, log plan creation:

```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"plan_created\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"path\":\"PLAN_PATH\",\"skill\":\"writing-plans\",\"topic\":\"TOPIC\"}}" >> .stellar-powers/workflow.jsonl
```

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use stellar-powers:subagent-driven-development (recommended) or stellar-powers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

## Library Doc Verification (Context7)

After writing the plan header (Goal, Architecture, Tech Stack), verify library APIs before writing task code blocks.

For the top 3-5 libraries in the Tech Stack header (skip utility libs like lodash/zod and private `@org/` scoped packages), fetch current documentation. Set `QUERY` to the specific API topic relevant to the task (e.g., `"app router"` for Next.js routing, `"webhooks"` for Stripe — never just the library name):

```bash
# For each key library (e.g., LIBRARY="nextjs", QUERY="app router")
LIB_ID=$(curl -s --max-time 10 "https://context7.com/api/v2/libs/search?libraryName=${LIBRARY}" \
  -H "Authorization: Bearer $CONTEXT7_API_KEY" \
  | python3 -c "import sys,json; r=json.load(sys.stdin).get('results',[]); print(max(r, key=lambda x: x.get('trustScore',0))['id'] if r else '')" 2>/dev/null)

if [ -n "$LIB_ID" ]; then
  curl -s --max-time 10 "https://context7.com/api/v2/context?libraryId=${LIB_ID}&query=${QUERY}&tokens=5000&type=txt" \
    -H "Authorization: Bearer $CONTEXT7_API_KEY" 2>/dev/null
fi
```

**Version awareness:** Check if the project's pinned version (from `package.json` or lock file) matches the docs version. If there's a major version mismatch, note it and use docs conservatively — don't "correct" patterns to a version the project doesn't use.

Use the fetched docs to verify API patterns before writing inline code examples in tasks. If a pattern differs from the current docs, use the current version.

Add a `## Library References` appendix at the bottom of every plan:

```markdown
## Library References

> Verified via Context7 on {date}. Use these as authoritative API reference.

### {Library} (resolved: {libraryId}, project version: {version})
- {key pattern 1}
- {key pattern 2}
- {key pattern 3}
```

Max ~200 tokens per library entry. Summarize 3-5 key API patterns relevant to the task.

**If `CONTEXT7_API_KEY` is not set:** Note "Context7 API key not configured — proceeding without library doc verification." and continue. Never block on API errors.

## Task Structure

````markdown
### Task N: [Component Name] [batch|solo]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## Task Annotations: [batch] / [solo]

Every task heading MUST include a `[batch]` or `[solo]` annotation. Assess each task against these complexity signals:

**[batch] — ALL must be true:**
- Touches 1-2 files
- Steps are mechanical (write file, run command, commit)
- No integration concerns across other tasks
- No "judgment", "architecture", or "design decision" language in description
- Task is independent (no dependencies on other tasks)

**[solo] — ANY one triggers solo:**
- Touches 3+ files
- Requires multi-file coordination or integration
- Contains judgment/design language
- Has dependencies on other tasks (references another task by number, uses files created by prior tasks, or references output from prior tasks)
- Modifies shared interfaces or schemas

These annotations tell `subagent-driven-development` whether to batch consecutive `[batch]` tasks into a single sub-agent dispatch (2-4 per agent) or dispatch each `[solo]` task individually. The user can change annotations during plan review.

## Remember
- Exact file paths always
- Complete code in plan (not "add validation")
- Exact commands with expected output
- Reference relevant skills with @ syntax
- DRY, YAGNI, TDD, frequent commits

## Plan Review Loop

After writing the complete plan:

1. **MANDATORY:** Read the prompt template at `./plan-document-reviewer-prompt.md` using the Read tool, then dispatch a subagent using the Agent tool with `model=sonnet` and that template's contents as the prompt. Do NOT construct your own review prompt — the template contains the multi-persona catalog that ensures domain-expert review quality. Replace `[PLAN_FILE_PATH]` and `[SPEC_FILE_PATH]` with actual paths. Never pass your session history — only the crafted prompt. Never use opus for subagents.
2. If ❌ Issues Found: fix the issues, re-dispatch reviewer for the whole plan
3. If ✅ Approved: proceed to execution handoff

**Review loop guidance:**
- Same agent that wrote the plan fixes it (preserves context)
- If loop exceeds 3 iterations, surface to human for guidance
- Reviewers are advisory — explain disagreements if you believe feedback is incorrect

**Correction capture at plan review gates:** If at any review gate (plan review loop, execution choice) the user's response is NOT a simple approval, log a user_correction event before acting on their feedback:
```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"user_correction\",\"workflow_id\":\"${WF_ID}\",\"session\":\"${CLAUDE_SESSION_ID:-}\",\"data\":{\"skill\":\"writing-plans\",\"context\":\"GATE_NAME\",\"correction\":\"FIRST_200_CHARS_OF_FEEDBACK\",\"category\":\"correction\"}}" >> .stellar-powers/workflow.jsonl
```
Replace `GATE_NAME` with e.g. `plan_review` or `execution_choice`, and `FIRST_200_CHARS_OF_FEEDBACK` with the first 200 characters of the user's feedback.

**Verbal corrections:** If the user provides corrective feedback outside a formal review gate (e.g., "no that's wrong", "you missed X", "don't do Y"), also log a user_correction event. Use your judgment — a simple "yes" or "continue" is not a correction. A redirect, disagreement, or gap identification is.

## Execution Handoff

Before offering execution choice, create a partial metrics snapshot:
```bash
# Create partial metrics snapshot at writing-plans stage
SP_WF_ID="${WF_ID}" SP_REPO="${REPO}" SP_TOPIC="TOPIC" SP_VERSION="${SP_VERSION}" SP_TASK_TYPE="${TASK_TYPE:-unknown}" python3 << 'PYEOF'
import json, os, sys
from datetime import datetime

cwd = os.getcwd()
wf_file = os.path.join(cwd, ".stellar-powers", "workflow.jsonl")
wf_id = os.environ.get("SP_WF_ID", "")
if not wf_id:
    sys.exit(0)

events = []
with open(wf_file) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            evt = json.loads(line)
            if evt.get("workflow_id") == wf_id:
                events.append(evt)
        except: continue

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
for e in events:
    if e.get("event") == "skill_invocation" and not started:
        started = e.get("ts", "")

# Per-skill metrics
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

pkg = {
    "package_version": "1.0",
    "workflow_id": wf_id,
    "stage": "writing-plans",
    "stellar_powers_version": sp_version,
    "context": {
        "repo": repo,
        "task_type": task_type,
        "skills_chain": ["brainstorming", "writing-plans"],
    },
    "timeline": {
        "started": started,
        "completed": "",
        "duration_minutes": duration,
        "user_confirmed_complete": False,
    },
    "skills": skills_data,
    "tasks": tasks,
    "user_messages": user_messages,
    "ai_responses": ai_responses,
    "tool_failures": tool_failures,
    "artifacts": artifacts,
    "completion_feedback": "",
    "outcome": "partial",
}

metrics_dir = os.path.join(cwd, ".stellar-powers", "metrics")
os.makedirs(metrics_dir, exist_ok=True)
pkg_path = os.path.join(metrics_dir, f"{datetime.utcnow().strftime('%Y-%m-%d')}-{topic}-{wf_id[:8]}-partial.json")
# Remove old partials for this workflow
for f_name in os.listdir(metrics_dir):
    if wf_id[:8] in f_name and f_name.endswith("-partial.json"):
        os.remove(os.path.join(metrics_dir, f_name))
with open(pkg_path, "w") as f:
    json.dump(pkg, f, indent=2)
PYEOF
```
Replace `TOPIC` with the actual topic.

After saving the plan, offer execution choice:

**"Plan complete and saved to `.stellar-powers/plans/<filename>.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?"**

**If Subagent-Driven chosen:**
- **REQUIRED SUB-SKILL:** Use stellar-powers:subagent-driven-development
- Fresh subagent per task + two-stage review
- Before invoking, update .active-workflow for handoff:
  ```bash
  ORIGINAL_START=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('started',''))" 2>/dev/null)
  REPO=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('repo',''))" 2>/dev/null)
  TASK_TYPE=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('task_type',''))" 2>/dev/null)
  SP_VERSION=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('sp_version',''))" 2>/dev/null)
  cat > .stellar-powers/.active-workflow.tmp << AWEOF
  {"workflow_id":"${WF_ID}","skill":"subagent-driven-development","topic":"TOPIC","step":"handoff","step_number":0,"started":"${ORIGINAL_START}","repo":"${REPO}","task_type":"${TASK_TYPE}","sp_version":"${SP_VERSION}"}
  AWEOF
  mv .stellar-powers/.active-workflow.tmp .stellar-powers/.active-workflow
  ```

**If Inline Execution chosen:**
- **REQUIRED SUB-SKILL:** Use stellar-powers:executing-plans
- Batch execution with checkpoints for review
- Before invoking, update .active-workflow for handoff:
  ```bash
  ORIGINAL_START=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('started',''))" 2>/dev/null)
  REPO=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('repo',''))" 2>/dev/null)
  TASK_TYPE=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('task_type',''))" 2>/dev/null)
  SP_VERSION=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('sp_version',''))" 2>/dev/null)
  cat > .stellar-powers/.active-workflow.tmp << AWEOF
  {"workflow_id":"${WF_ID}","skill":"executing-plans","topic":"TOPIC","step":"handoff","step_number":0,"started":"${ORIGINAL_START}","repo":"${REPO}","task_type":"${TASK_TYPE}","sp_version":"${SP_VERSION}"}
  AWEOF
  mv .stellar-powers/.active-workflow.tmp .stellar-powers/.active-workflow
  ```
