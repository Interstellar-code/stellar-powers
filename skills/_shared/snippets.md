# Shared Snippets for Self-Improving Capabilities

Reference file — not executed directly. Skills copy these snippets inline.

## Redaction Filter

Used by hooks and skills before writing previews to workflow.jsonl.

```bash
# Redact sensitive data from a string. Usage: echo "$text" | redact_preview
redact_preview() {
  python3 -c "
import sys, re
text = sys.stdin.read()
# API keys and tokens
text = re.sub(r'(sk-[a-zA-Z0-9]{20,})', '[REDACTED_KEY]', text)
text = re.sub(r'(ghp_[a-zA-Z0-9]{36,})', '[REDACTED_TOKEN]', text)
text = re.sub(r'(Bearer\s+[a-zA-Z0-9._-]{20,})', 'Bearer [REDACTED]', text)
text = re.sub(r'ctx7sk-[a-zA-Z0-9-]+', '[REDACTED_KEY]', text)
text = re.sub(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', '[REDACTED_EMAIL]', text)
text = re.sub(r'/Users/[^/\s\"]+', '/Users/[user]', text)
text = re.sub(r'~/[^\s\"]+', '~/[path]', text)
print(text, end='')
" 2>/dev/null || cat
}
```

## Feedback Enabled Check

Used by hooks to check if feedback capture is active.

```bash
# Check if feedback is enabled. Returns 0 if enabled, 1 if disabled.
is_feedback_enabled() {
  local config_file="${cwd}/.stellar-powers/config.json"
  if [ -f "$config_file" ]; then
    local enabled=$(python3 -c "import json; print(json.load(open('$config_file')).get('feedback_enabled', True))" 2>/dev/null)
    if [ "$enabled" = "False" ]; then
      return 1
    fi
  fi
  return 0
}
```

## Read Active Workflow

Used by hooks to get current workflow context. Uses a temp file instead of eval to avoid shell injection.

```bash
# Read .active-workflow fields into AW_* variables. Returns 1 if no active workflow.
read_active_workflow() {
  local aw_file="${cwd}/.stellar-powers/.active-workflow"
  if [ ! -f "$aw_file" ]; then
    return 1
  fi
  # Parse JSON safely — write to temp file, source it
  local tmp_vars=$(mktemp)
  python3 -c "
import json, sys, re
try:
    d = json.load(open('${aw_file}'))
    for k, v in d.items():
        # Sanitize: only allow alphanumeric, dash, underscore, dot, colon, space
        safe_v = re.sub(r'[^a-zA-Z0-9._: /-]', '', str(v))
        print(f'AW_{k.upper()}=\"{safe_v}\"')
except:
    sys.exit(1)
" > "$tmp_vars" 2>/dev/null || { rm -f "$tmp_vars"; return 1; }
  source "$tmp_vars"
  rm -f "$tmp_vars"
  return 0
}
```

## Write Workflow Event

Used by hooks and skills to append events to workflow.jsonl.

```bash
# Append a workflow event. Usage: write_wf_event "$cwd" "$event" "$workflow_id" "$data_json"
write_wf_event() {
  local target_cwd="$1" event="$2" wf_id="$3" data="$4"
  local wf_file="${target_cwd}/.stellar-powers/workflow.jsonl"
  mkdir -p "${target_cwd}/.stellar-powers"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"${event}\",\"workflow_id\":\"${wf_id}\",\"session\":\"${CLAUDE_SESSION_ID:-}\",\"data\":${data}}" >> "$wf_file"
}
```

## Workflow Gate (for skills)

Skills paste this at the start of their checklist. It reads .active-workflow and handles the invocation gate logic.

```bash
# Workflow gate — check for existing active workflow
AW_FILE=".stellar-powers/.active-workflow"
if [ -f "$AW_FILE" ]; then
  # Parse existing workflow
  AW_JSON=$(cat "$AW_FILE" 2>/dev/null)
  AW_VALID=$(echo "$AW_JSON" | python3 -c "import json,sys; json.load(sys.stdin); print('yes')" 2>/dev/null)
  if [ "$AW_VALID" != "yes" ]; then
    echo "Corrupted workflow state detected and cleared. Starting fresh."
    rm -f "$AW_FILE"
  else
    AW_WF_ID=$(echo "$AW_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('workflow_id',''))")
    AW_TOPIC=$(echo "$AW_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('topic',''))")
    AW_SKILL=$(echo "$AW_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('skill',''))")
    AW_STARTED=$(echo "$AW_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('started',''))")
    # Check if already completed in workflow.jsonl
    ALREADY_DONE=$(grep -c "\"workflow_completed\".*${AW_WF_ID}\|\"workflow_abandoned\".*${AW_WF_ID}" .stellar-powers/workflow.jsonl 2>/dev/null || echo 0)
    if [ "$ALREADY_DONE" -gt 0 ]; then
      rm -f "$AW_FILE"
    fi
  fi
fi

# Check for held workflows
HELD_COUNT=$(ls .stellar-powers/.active-workflow.held.* 2>/dev/null | wc -l | tr -d ' ')
if [ "$HELD_COUNT" -gt 0 ]; then
  echo "Note: ${HELD_COUNT} workflow(s) on hold."
fi
```

## Step Logging (for skills)

```bash
# Log step start. Usage in skill: run this bash before each step
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"step_started\",\"workflow_id\":\"${WF_ID}\",\"session\":\"${CLAUDE_SESSION_ID:-}\",\"data\":{\"skill\":\"SKILL_NAME\",\"step\":\"STEP_NAME\",\"step_number\":N}}" >> .stellar-powers/workflow.jsonl

# Log step complete. Usage in skill: run this bash after each step
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"step_completed\",\"workflow_id\":\"${WF_ID}\",\"session\":\"${CLAUDE_SESSION_ID:-}\",\"data\":{\"skill\":\"SKILL_NAME\",\"step\":\"STEP_NAME\",\"step_number\":N}}" >> .stellar-powers/workflow.jsonl
```

## Completion Checkpoint (for terminal skills)

```bash
# Ask user if workflow is complete, then package metrics
# This is a prompt template — the skill presents this to the user and acts on the response

# On user confirming complete:
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"workflow_completed\",\"workflow_id\":\"${WF_ID}\",\"session\":\"${CLAUDE_SESSION_ID:-}\",\"data\":{\"skill\":\"SKILL_NAME\",\"duration_minutes\":DURATION,\"steps_completed\":N,\"steps_total\":TOTAL,\"outcome\":\"success\",\"completion_feedback\":\"USER_FEEDBACK\"}}" >> .stellar-powers/workflow.jsonl

# Package metrics (use the Metrics Packaging snippet below)
# Prune workflow.jsonl
# Delete .active-workflow
```

## Metrics Packaging

**Use the standalone script** — do NOT use inline Python heredocs (agents skip them).

```bash
# Partial snapshot (at handoff points):
SP_WF_ID="${WF_ID}" python3 "${CLAUDE_PLUGIN_ROOT}/scripts/metrics-packager.py" --partial --stage brainstorming

# Full package + prune (at completion checkpoint):
export SP_WF_ID="${WF_ID}"
export SP_REPO=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('repo') or 'unknown')" 2>/dev/null || echo "unknown")
export SP_TASK_TYPE=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('task_type') or 'unknown')" 2>/dev/null || echo "unknown")
export SP_VERSION=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('sp_version') or 'unknown')" 2>/dev/null || echo "unknown")
export SP_TOPIC=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('topic') or 'unknown')" 2>/dev/null || echo "unknown")
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/metrics-packager.py" --prune
```

The script at `scripts/metrics-packager.py` handles everything: event extraction, rich package structure, null-field fallback, partial cleanup, and pruning.

<details><summary>Legacy inline packager (deprecated — do not use)</summary>

Skills previously used inline Python heredocs. These were skipped by agents in practice.

```bash
# Package workflow metrics into a structured JSON file
# Usage: SP_WF_ID="$WF_ID" python3 << 'PYEOF'
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

# Build structured package matching spec Component 4
aw_path = os.path.join(cwd, ".stellar-powers", ".active-workflow")
aw = {}
if os.path.exists(aw_path):
    try:
        aw = json.load(open(aw_path))
    except:
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
outcome = "unknown"
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
        start_dt = datetime.fromisoformat(started.replace('Z', '+00:00'))
        end_dt = datetime.fromisoformat(completed.replace('Z', '+00:00'))
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

# Extract per-skill metrics
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

# Extract tasks
tasks = [{"id": e["data"].get("task_id", ""), "subject": e["data"].get("task_subject", ""), "status": "completed"}
         for e in events if e.get("event") == "task_completed"]

# Extract user messages
user_messages = [{"timestamp": e.get("ts", ""), "context": f"{e['data'].get('active_skill', '')}/{e['data'].get('active_step', '')}",
                  "preview": e["data"].get("prompt_preview", "")}
                 for e in events if e.get("event") == "user_message"]

# Extract AI responses
ai_responses = [{"timestamp": e.get("ts", ""), "context": e["data"].get("active_skill", ""),
                 "preview": e["data"].get("response_preview", "")}
                for e in events if e.get("event") == "turn_completed"]

# Extract tool failures
tool_failures = [{"tool": e["data"].get("tool_name", ""), "error": e["data"].get("error_preview", "")}
                 for e in events if e.get("event") == "tool_failure"]

# Extract artifacts
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

# Write package
metrics_dir = os.path.join(cwd, ".stellar-powers", "metrics")
os.makedirs(metrics_dir, exist_ok=True)
date_str = datetime.utcnow().strftime("%Y-%m-%d")

pkg_path = os.path.join(metrics_dir, f"{date_str}-{topic}-{wf_id[:8]}.json")
with open(pkg_path, "w") as f:
    json.dump(package, f, indent=2)

# Verify
with open(pkg_path) as f:
    json.load(f)  # will raise if invalid

print(f"METRICS_PACKAGE={pkg_path}")
PYEOF
```

## Pruning

Skills pass the workflow_id as `SP_WF_ID` env var, same as packaging.

```bash
# Prune workflow.jsonl — replace detail lines with summary
# Usage: SP_WF_ID="$WF_ID" python3 << 'PYEOF'
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

# Build rich summary from pruned events (matches spec Component 2)
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

# Read .active-workflow for context
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
        "topic": aw.get("topic", "unknown"),
        "repo": aw.get("repo", "unknown"),
        "task_type": aw.get("task_type", "unknown"),
        "sp_version": aw.get("sp_version", "unknown"),
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

# Atomic write
tmp_path = wf_file + ".tmp"
with open(tmp_path, "w") as f:
    f.write("\n".join(kept) + "\n")
os.rename(tmp_path, wf_file)
PYEOF
```

</details>

## Hold/Park Workflow

Used when the user chooses to park a workflow at the invocation gate.

```bash
# Park the current workflow — rename .active-workflow to .held
AW_FILE=".stellar-powers/.active-workflow"
AW_WF_ID=$(python3 -c "import json; print(json.load(open('$AW_FILE')).get('workflow_id',''))" 2>/dev/null)
mv "$AW_FILE" ".stellar-powers/.active-workflow.held.${AW_WF_ID}"
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"workflow_on_hold\",\"workflow_id\":\"${AW_WF_ID}\",\"session\":\"${CLAUDE_SESSION_ID:-}\",\"data\":{\"held_reason\":\"USER_REASON\"}}" >> .stellar-powers/workflow.jsonl

# Resume a held workflow
# mv ".stellar-powers/.active-workflow.held.${SELECTED_WF_ID}" ".stellar-powers/.active-workflow"
```

## Active Workflow Step Update

Used by skills to update the current step in `.active-workflow`.

```bash
# Update .active-workflow step field
python3 -c "
import json
aw = json.load(open('.stellar-powers/.active-workflow'))
aw['step'] = 'STEP_NAME'
aw['step_number'] = N
json.dump(aw, open('.stellar-powers/.active-workflow.tmp', 'w'))
" && mv .stellar-powers/.active-workflow.tmp .stellar-powers/.active-workflow
```

Also create `.stellar-powers/.gitignore` with:
```
# Metrics contain user message previews — don't commit
metrics/
*.json.sent

# Active workflow state is transient
.active-workflow
.active-workflow.tmp
.active-workflow.held.*
```
