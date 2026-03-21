# Self-Improving Capabilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use stellar-powers:subagent-driven-development (recommended) or stellar-powers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add feedback capture, workflow lifecycle management, metrics packaging, and a send-feedback skill so stellar-powers can collect usage data across repos and file it as GitHub issues for future analysis.

**Architecture:** New hooks (UserPromptSubmit, TaskCompleted, SubagentStop, Stop, PostToolUseFailure) capture structural events automatically. Existing skills are enhanced with step-level logging, correction capture at review gates, and a completion checkpoint. A `.active-workflow` state file bridges hooks and skills. Metrics are packaged on workflow completion and sent to GitHub via a new `send-feedback` skill.

**Tech Stack:** Bash (hooks), Python3 (inline in hooks for JSON processing), `gh` CLI (GitHub issue creation), JSONL (workflow event log)

**Spec:** `.stellar-powers/specs/2026-03-21-self-improving-capabilities-design.md`

---

## File Structure

```
hooks/
├── hooks.json                    # MODIFY — add new hook event entries
├── post-tool-use                 # MODIFY — add feedback_enabled check
├── session-start                 # MODIFY — add .active-workflow lifecycle check
├── user-prompt-submit            # CREATE — new hook script
├── task-completed                # CREATE — new hook script
├── subagent-stop                 # CREATE — new hook script
├── stop                          # CREATE — new hook script
├── post-tool-use-failure         # CREATE — new hook script

skills/
├── _shared/
│   └── snippets.md               # CREATE — reference snippets for lifecycle, step logging, packaging
├── send-feedback/
│   └── SKILL.md                  # CREATE — send-feedback skill
├── brainstorming/
│   └── SKILL.md                  # MODIFY — add lifecycle, step logging, correction capture
├── writing-plans/
│   └── SKILL.md                  # MODIFY — add lifecycle, step logging, correction capture
├── subagent-driven-development/
│   └── SKILL.md                  # MODIFY — add lifecycle, step logging, completion checkpoint
├── executing-plans/
│   └── SKILL.md                  # MODIFY — add lifecycle, step logging, completion checkpoint
├── test-driven-development/
│   └── SKILL.md                  # MODIFY — add lifecycle, step logging, completion checkpoint
├── finishing-a-development-branch/
│   └── SKILL.md                  # MODIFY — add lifecycle, completion checkpoint
├── using-stellarpowers/
│   └── SKILL.md                  # MODIFY — add send-feedback to available skills table

tests/
├── test-self-improving.sh        # CREATE — validation tests
```

---

### Task 1: Create shared snippets reference [solo]

**Files:**
- Create: `skills/_shared/snippets.md`

This is the foundation all other tasks reference. Contains the bash code blocks that skills will inline.

- [ ] **Step 1: Create the shared snippets file**

```markdown
# Shared Snippets for Self-Improving Capabilities

Reference file — not executed directly. Skills copy these snippets inline.

## Redaction Filter

Used by hooks and skills before writing previews to workflow.jsonl.

\`\`\`bash
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
\`\`\`

## Feedback Enabled Check

Used by hooks to check if feedback capture is active.

\`\`\`bash
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
\`\`\`

## Read Active Workflow

Used by hooks to get current workflow context.

\`\`\`bash
# Read .active-workflow and set variables. Returns 1 if no active workflow.
read_active_workflow() {
  local aw_file="${cwd}/.stellar-powers/.active-workflow"
  if [ ! -f "$aw_file" ]; then
    return 1
  fi
  # Parse JSON fields
  eval "$(python3 -c "
import json, sys
try:
    d = json.load(open('$aw_file'))
    for k, v in d.items():
        print(f'AW_{k.upper()}=\"{v}\"')
except:
    sys.exit(1)
" 2>/dev/null)" || return 1
  return 0
}
\`\`\`

## Write Workflow Event

Used by hooks and skills to append events to workflow.jsonl.

\`\`\`bash
# Append a workflow event. Usage: write_wf_event "$cwd" "$event" "$workflow_id" "$data_json"
write_wf_event() {
  local target_cwd="$1" event="$2" wf_id="$3" data="$4"
  local wf_file="${target_cwd}/.stellar-powers/workflow.jsonl"
  mkdir -p "${target_cwd}/.stellar-powers"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"${event}\",\"workflow_id\":\"${wf_id}\",\"session\":\"\",\"data\":${data}}" >> "$wf_file"
}
\`\`\`

## Workflow Gate (for skills)

Skills paste this at the start of their checklist. It reads .active-workflow and handles the invocation gate logic.

\`\`\`bash
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
\`\`\`

## Step Logging (for skills)

\`\`\`bash
# Log step start. Usage in skill: run this bash before each step
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"step_started\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"SKILL_NAME\",\"step\":\"STEP_NAME\",\"step_number\":N}}" >> .stellar-powers/workflow.jsonl

# Log step complete. Usage in skill: run this bash after each step
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"step_completed\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"SKILL_NAME\",\"step\":\"STEP_NAME\",\"step_number\":N}}" >> .stellar-powers/workflow.jsonl
\`\`\`

## Completion Checkpoint (for terminal skills)

\`\`\`bash
# Ask user if workflow is complete, then package metrics
# This is a prompt template — the skill presents this to the user and acts on the response

# On user confirming complete:
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"workflow_completed\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"SKILL_NAME\",\"duration_minutes\":DURATION,\"steps_completed\":N,\"steps_total\":TOTAL,\"outcome\":\"success\",\"completion_feedback\":\"USER_FEEDBACK\"}}" >> .stellar-powers/workflow.jsonl

# Package metrics (use the Metrics Packaging snippet below)
# Prune workflow.jsonl
# Delete .active-workflow
\`\`\`

## Metrics Packaging

\`\`\`bash
# Package workflow metrics into a JSON file
# Run after workflow_completed event is logged
python3 << 'PYEOF'
import json, os, sys
from datetime import datetime

cwd = os.getcwd()
wf_file = os.path.join(cwd, ".stellar-powers", "workflow.jsonl")
wf_id = "WORKFLOW_ID"  # replaced by skill

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

# Build package from events
package = {
    "package_version": "1.0",
    "workflow_id": wf_id,
    "events": events
}

# Write package
metrics_dir = os.path.join(cwd, ".stellar-powers", "metrics")
os.makedirs(metrics_dir, exist_ok=True)
date_str = datetime.utcnow().strftime("%Y-%m-%d")
topic = "unknown"

# Extract topic from workflow_started event
for e in events:
    if e.get("event") == "workflow_started":
        topic = e.get("data", {}).get("topic", "unknown")
        break
    if e.get("event") == "skill_invocation":
        topic = e.get("data", {}).get("args", "unknown").split()[0] if e.get("data", {}).get("args") else "unknown"

pkg_path = os.path.join(metrics_dir, f"{date_str}-{topic}-{wf_id[:8]}.json")
with open(pkg_path, "w") as f:
    json.dump(package, f, indent=2)

# Verify
with open(pkg_path) as f:
    json.load(f)  # will raise if invalid

print(f"METRICS_PACKAGE={pkg_path}")
PYEOF
\`\`\`

## Pruning

\`\`\`bash
# Prune workflow.jsonl — replace detail lines with summary
python3 << 'PYEOF'
import json, os, tempfile

cwd = os.getcwd()
wf_file = os.path.join(cwd, ".stellar-powers", "workflow.jsonl")
wf_id = "WORKFLOW_ID"  # replaced by skill

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

# Build summary from pruned events
summary = {"event": "workflow_summary", "workflow_id": wf_id, "data": {}}
# Extract summary fields from events...
for e in pruned_events:
    if e.get("event") == "workflow_completed":
        summary["data"] = e.get("data", {})
        summary["ts"] = e.get("ts", "")
        break

kept.append(json.dumps(summary))

# Atomic write
tmp_path = wf_file + ".tmp"
with open(tmp_path, "w") as f:
    f.write("\n".join(kept) + "\n")
os.rename(tmp_path, wf_file)
PYEOF
\`\`\`
```

- [ ] **Step 2: Commit**

```bash
git add skills/_shared/snippets.md
git commit -m "feat: add shared snippets reference for self-improving capabilities"
```

---

### Task 2: Add new hook entries to hooks.json [batch]

**Files:**
- Modify: `hooks/hooks.json`

Register the five new hook events in the hooks configuration.

- [ ] **Step 1: Update hooks.json with new event entries**

Add entries for UserPromptSubmit, TaskCompleted, SubagentStop, Stop, and PostToolUseFailure. All use the same `run-hook.cmd` wrapper pattern as existing hooks. All are async (non-blocking) since they're logging-only.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start",
            "async": false
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" post-tool-use",
            "async": true
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" user-prompt-submit",
            "async": true
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" task-completed",
            "async": true
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" subagent-stop",
            "async": true
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" stop",
            "async": true
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" post-tool-use-failure",
            "async": true
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: register five new hook events for self-improving feedback capture"
```

---

### Task 3: Create UserPromptSubmit hook script [batch]

**Files:**
- Create: `hooks/user-prompt-submit`

Captures user messages with workflow correlation. Silently skips if no active workflow or feedback disabled.

- [ ] **Step 1: Create the hook script**

```bash
#!/usr/bin/env bash
# UserPromptSubmit hook — captures user message previews for feedback metrics
# Receives JSON on stdin. MUST exit 0 in all cases.

trap 'exit 0' ERR

_SP_HOOK_INPUT=$(cat 2>/dev/null) || exit 0
export _SP_HOOK_INPUT

python3 -c '
import json, sys, os, re

try:
    data = json.loads(os.environ.get("_SP_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

cwd = data.get("cwd", "")
if not cwd:
    sys.exit(0)

# Check feedback enabled
config_path = os.path.join(cwd, ".stellar-powers", "config.json")
if os.path.exists(config_path):
    try:
        if not json.load(open(config_path)).get("feedback_enabled", True):
            sys.exit(0)
    except:
        pass

# Check active workflow
aw_path = os.path.join(cwd, ".stellar-powers", ".active-workflow")
if not os.path.exists(aw_path):
    sys.exit(0)

try:
    aw = json.load(open(aw_path))
except:
    sys.exit(0)

workflow_id = aw.get("workflow_id", "")
active_skill = aw.get("skill", "")
active_step = aw.get("step", "")

prompt = data.get("prompt", "")
if not prompt:
    sys.exit(0)

# Redact sensitive data
preview = prompt[:200]
preview = re.sub(r"sk-[a-zA-Z0-9]{20,}", "[REDACTED_KEY]", preview)
preview = re.sub(r"ghp_[a-zA-Z0-9]{36,}", "[REDACTED_TOKEN]", preview)
preview = re.sub(r"Bearer\s+[a-zA-Z0-9._-]{20,}", "Bearer [REDACTED]", preview)
preview = re.sub(r"ctx7sk-[a-zA-Z0-9-]+", "[REDACTED_KEY]", preview)
preview = re.sub(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}", "[REDACTED_EMAIL]", preview)
preview = re.sub(r"/Users/[^/\s\"]+", "/Users/[user]", preview)

# Escape for JSON
preview = preview.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", "")

from datetime import datetime, timezone
ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

session_id = data.get("session_id", "")

wf_file = os.path.join(cwd, ".stellar-powers", "workflow.jsonl")
os.makedirs(os.path.dirname(wf_file), exist_ok=True)

event = json.dumps({
    "ts": ts,
    "event": "user_message",
    "workflow_id": workflow_id,
    "session": session_id,
    "data": {
        "prompt_preview": preview,
        "active_skill": active_skill,
        "active_step": active_step
    }
})

with open(wf_file, "a") as f:
    f.write(event + "\n")
' 2>/dev/null

exit 0
```

Make executable: `chmod +x hooks/user-prompt-submit`

- [ ] **Step 2: Commit**

```bash
git add hooks/user-prompt-submit
git commit -m "feat: add UserPromptSubmit hook for user message capture"
```

---

### Task 4: Create TaskCompleted hook script [batch]

**Files:**
- Create: `hooks/task-completed`

Captures task completion events with workflow correlation.

- [ ] **Step 1: Create the hook script**

Same pattern as user-prompt-submit but reads `task_id`, `task_subject`, `task_description` from input data. Silently skips if no active workflow or feedback disabled.

```bash
#!/usr/bin/env bash
# TaskCompleted hook — logs task completions for feedback metrics
trap 'exit 0' ERR
_SP_HOOK_INPUT=$(cat 2>/dev/null) || exit 0
export _SP_HOOK_INPUT

python3 -c '
import json, sys, os

try:
    data = json.loads(os.environ.get("_SP_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

cwd = data.get("cwd", "")
if not cwd:
    sys.exit(0)

config_path = os.path.join(cwd, ".stellar-powers", "config.json")
if os.path.exists(config_path):
    try:
        if not json.load(open(config_path)).get("feedback_enabled", True):
            sys.exit(0)
    except:
        pass

aw_path = os.path.join(cwd, ".stellar-powers", ".active-workflow")
if not os.path.exists(aw_path):
    sys.exit(0)

try:
    aw = json.load(open(aw_path))
except:
    sys.exit(0)

from datetime import datetime, timezone
ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
session_id = data.get("session_id", "")

event = json.dumps({
    "ts": ts,
    "event": "task_completed",
    "workflow_id": aw.get("workflow_id", ""),
    "session": session_id,
    "data": {
        "task_id": str(data.get("task_id", "")),
        "task_subject": re.sub(r"sk-[a-zA-Z0-9]{20,}", "[REDACTED_KEY]", str(data.get("task_subject", ""))[:200]),
        "task_description": re.sub(r"sk-[a-zA-Z0-9]{20,}", "[REDACTED_KEY]", str(data.get("task_description", ""))[:300])
    }
})

wf_file = os.path.join(cwd, ".stellar-powers", "workflow.jsonl")
os.makedirs(os.path.dirname(wf_file), exist_ok=True)
with open(wf_file, "a") as f:
    f.write(event + "\n")
' 2>/dev/null

exit 0
```

Make executable: `chmod +x hooks/task-completed`

- [ ] **Step 2: Commit**

```bash
git add hooks/task-completed
git commit -m "feat: add TaskCompleted hook for task tracking"
```

---

### Task 5: Create SubagentStop, Stop, and PostToolUseFailure hook scripts [batch]

**Files:**
- Create: `hooks/subagent-stop`
- Create: `hooks/stop`
- Create: `hooks/post-tool-use-failure`

Three small hook scripts following the same pattern. Each reads `.active-workflow`, checks feedback_enabled, and appends an event to workflow.jsonl.

- [ ] **Step 1: Create subagent-stop hook**

Same pattern as user-prompt-submit (Task 3). Copy the full Task 3 script as template, then change:
- Event type: `subagent_completed`
- Data fields: `agent_id` from `data.get("agent_id")`, `agent_type` from `data.get("agent_type")`, `outcome_preview` from `data.get("last_assistant_message", "")[:300]`
- Apply the FULL redaction regex block (all 6 patterns from Task 3) to `outcome_preview`

- [ ] **Step 2: Create stop hook**

Same template. Changes:
- Event type: `turn_completed`
- Data fields: `response_preview` from `data.get("last_assistant_message", "")[:300]`, `active_skill` from active workflow
- Apply FULL redaction regex block to `response_preview`

- [ ] **Step 3: Create post-tool-use-failure hook**

Same template. Changes:
- Event type: `tool_failure`
- Data fields: `tool_name` from `data.get("tool_name")`, `error_preview` from `str(data.get("error", ""))[:300]`
- No redaction needed on tool_name; apply redaction to error_preview

- [ ] **Step 4: Make all executable and commit**

```bash
chmod +x hooks/subagent-stop hooks/stop hooks/post-tool-use-failure
git add hooks/subagent-stop hooks/stop hooks/post-tool-use-failure
git commit -m "feat: add SubagentStop, Stop, and PostToolUseFailure hooks"
```

---

### Task 6: Enhance session-start hook with .active-workflow lifecycle check [solo]

**Files:**
- Modify: `hooks/session-start`

The session-start hook already checks `workflow.jsonl` for incomplete workflows. Add: check for `.active-workflow` file and report its state. Check for held workflows. Check for stale/corrupted state.

- [ ] **Step 1: Read the current session-start hook**

Read `hooks/session-start` to understand the existing workflow summary logic.

- [ ] **Step 2: Add .active-workflow detection after the existing workflow summary block**

After the existing `workflow_summary` Python block, add a new block that:
- Checks if `.stellar-powers/.active-workflow` exists
- If corrupted JSON → delete and warn
- If workflow_id already has a completed/abandoned event → delete (orphaned)
- If started > 30 days ago → flag as stale
- Check for `.active-workflow.held.*` files → count and list topics
- Inject this info into the `additionalContext` output alongside existing workflow summary

- [ ] **Step 3: Commit**

```bash
git add hooks/session-start
git commit -m "feat: enhance session-start with .active-workflow lifecycle detection"
```

---

### Task 7: Add feedback_enabled check to existing post-tool-use hook [batch]

**Files:**
- Modify: `hooks/post-tool-use`

Add a feedback_enabled check at the top of the Python block so agent_dispatch and hook_violation events respect the kill switch.

- [ ] **Step 1: Read and modify post-tool-use**

After `cwd = data.get("cwd", "")`, add:

```python
# Check feedback enabled
config_path = os.path.join(cwd, ".stellar-powers", "config.json")
if os.path.exists(config_path):
    try:
        if not json.load(open(config_path)).get("feedback_enabled", True):
            sys.exit(0)
    except:
        pass
```

- [ ] **Step 2: Commit**

```bash
git add hooks/post-tool-use
git commit -m "feat: add feedback_enabled kill switch to post-tool-use hook"
```

---

### Task 8: Create the send-feedback skill [solo]

**Files:**
- Create: `skills/send-feedback/SKILL.md`

The skill that reads metrics packages and files GitHub issues on the stellar-powers repo.

- [ ] **Step 1: Create SKILL.md**

The skill must:
1. Check `gh auth status` first — fail immediately if not authenticated
2. Scan `.stellar-powers/metrics/` for `*.json` files (not `.sent`)
3. If empty, report "No pending feedback to send."
4. For each package:
   a. Read and parse the JSON
   b. Check for existing issue with same workflow_id via `gh search issues`
   c. Build issue title: `[skill-feedback] {skills_chain}: {topic} ({repo})`
   d. Build issue body with human-readable summary + raw metrics in `<details>` block
   e. Create issue via `gh issue create --repo Interstellar-code/stellar-powers --label skill-feedback --title "..." --body "..."`
   f. On success: rename to `.json.sent`
   g. On failure: log error, continue to next
5. Delete all `.sent` files
6. Log `feedback_sent` event to workflow.jsonl
7. Report summary with issue URLs

Labels should include `skill-feedback` plus one label per skill in the chain.

- [ ] **Step 2: Test with a mock metrics file**

Create a test metrics file in `.stellar-powers/metrics/`, run the skill logic manually to verify issue formatting. Delete the test file after.

- [ ] **Step 3: Commit**

```bash
git add skills/send-feedback/SKILL.md
git commit -m "feat: add send-feedback skill for filing GitHub issues from metrics"
```

---

### Task 9: Update using-stellarpowers skill table [batch]

**Files:**
- Modify: `skills/using-stellarpowers/SKILL.md`

Add send-feedback to the Available Skills table.

- [ ] **Step 1: Add entry to skills table**

Add row:
```
| `send-feedback` | Filing accumulated skill feedback as GitHub issues on the stellar-powers repo |
```

- [ ] **Step 2: Commit**

```bash
git add skills/using-stellarpowers/SKILL.md
git commit -m "feat: add send-feedback to available skills table"
```

---

### Task 10: Add workflow lifecycle to brainstorming skill [solo]

**Files:**
- Modify: `skills/brainstorming/SKILL.md`

Add the workflow gate, .active-workflow creation, step-level logging, and correction capture at review gates. This is the template for all other skill modifications.

- [ ] **Step 1: Read the current brainstorming SKILL.md**

Understand the existing checklist structure and workflow logging.

- [ ] **Step 2: Add workflow gate at step 0**

After the existing workflow ID generation, add the workflow gate snippet from `skills/_shared/snippets.md`. Also create `.active-workflow` with the current workflow context:

```bash
# Create .active-workflow (atomic write)
cat > .stellar-powers/.active-workflow.tmp << AWEOF
{"workflow_id":"${WF_ID}","skill":"brainstorming","topic":"TOPIC","step":"workflow_setup","step_number":0,"started":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","repo":"REPO","task_type":"TASK_TYPE","sp_version":"SP_VERSION"}
AWEOF
mv .stellar-powers/.active-workflow.tmp .stellar-powers/.active-workflow
```

The skill should detect repo name from the git remote and determine task_type from user's initial description (or ask).

- [ ] **Step 3: Add step logging to each checklist item**

At the start and end of each major step (explore context, clarifying questions, propose approaches, present design, write doc, spec review, user review), add step_started/step_completed events.

- [ ] **Step 4: Add correction capture at review gates**

At the spec review gate ("Does this design section look right?") and the user review gate, if the user's response is not a simple approval, log a `user_correction` event:

```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"user_correction\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"brainstorming\",\"context\":\"spec_review\",\"correction\":\"USER_FEEDBACK_PREVIEW\",\"category\":\"correction|partial_approval\"}}" >> .stellar-powers/workflow.jsonl
```

- [ ] **Step 5: Update .active-workflow on handoff to writing-plans**

Before invoking writing-plans, update `.active-workflow` to reflect the handoff but keep the same workflow_id.

- [ ] **Step 6: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "feat: add workflow lifecycle and step tracking to brainstorming skill"
```

---

### Task 11: Add workflow lifecycle to writing-plans skill [solo]

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

Same pattern as brainstorming: workflow gate, .active-workflow update (inherit workflow_id from brainstorming if chained), step logging, correction capture at plan review gates.

- [ ] **Step 1: Read current writing-plans SKILL.md**

- [ ] **Step 2: Add workflow gate — detect if chained from brainstorming**

If `.active-workflow` exists with same topic and skill=brainstorming, inherit the workflow_id and update skill to "writing-plans". If no `.active-workflow`, create a new one.

- [ ] **Step 3: Add step logging and correction capture**

Same pattern as brainstorming task.

- [ ] **Step 4: Update .active-workflow on handoff to SDD/executing-plans**

- [ ] **Step 5: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "feat: add workflow lifecycle and step tracking to writing-plans skill"
```

---

### Task 12: Add completion checkpoint to subagent-driven-development [solo]

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

This is a terminal skill — add the completion checkpoint, metrics packaging trigger, and workflow pruning.

- [ ] **Step 1: Read current SDD SKILL.md**

- [ ] **Step 2: Add workflow gate — detect if chained from writing-plans**

Same chain detection as writing-plans.

- [ ] **Step 3: Add step logging for major phases**

Steps: task dispatch, review, implementation batch.

- [ ] **Step 4: Add completion checkpoint after all tasks pass review**

After the final task is reviewed and approved, add:

```
All tasks completed. Is the workflow implementation now complete?

a) Yes, complete — I'll package the metrics and close this workflow
b) Not yet — what's remaining?
c) Complete, and here's my feedback: [user types feedback]
```

On (a) or (c):
1. Log `workflow_completed` event
2. Run metrics packaging (inline Python from snippets.md)
3. Run pruning (inline Python from snippets.md)
4. Delete `.active-workflow`
5. Report: "Workflow complete. Metrics packaged to .stellar-powers/metrics/. Run /stellar-powers:send-feedback to submit."

- [ ] **Step 5: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat: add completion checkpoint and metrics packaging to SDD skill"
```

---

### Task 13: Add completion checkpoint to remaining terminal skills [solo]

**Files:**
- Modify: `skills/executing-plans/SKILL.md`
- Modify: `skills/test-driven-development/SKILL.md`
- Modify: `skills/finishing-a-development-branch/SKILL.md`

Same completion checkpoint pattern as SDD — workflow gate, step logging, completion checkpoint with metrics packaging.

- [ ] **Step 1: Read all three SKILL.md files**

- [ ] **Step 2: Add workflow gate and step logging to each**

- [ ] **Step 3: Add completion checkpoint to each**

Same template as SDD task.

- [ ] **Step 4: Commit**

```bash
git add skills/executing-plans/SKILL.md skills/test-driven-development/SKILL.md skills/finishing-a-development-branch/SKILL.md
git commit -m "feat: add completion checkpoint to executing-plans, TDD, and finishing-branch skills"
```

---

### Task 14: Create validation tests [solo]

**Files:**
- Create: `tests/test-self-improving.sh`

Test the hooks and lifecycle logic.

- [ ] **Step 1: Create test script**

Tests to include:
1. **Hook scripts exit 0 with empty input** — each hook script receives empty stdin and exits cleanly
2. **Hook scripts skip when no .active-workflow** — verify no workflow.jsonl writes when no active workflow
3. **Hook scripts write events when .active-workflow exists** — create a mock .active-workflow, pipe mock hook input, verify event appears in workflow.jsonl
4. **Feedback disabled check** — create config.json with `feedback_enabled: false`, verify hooks skip
5. **Redaction filter** — test that API keys, emails, and absolute paths are redacted in event previews
6. **hooks.json is valid JSON** — parse hooks.json
7. **All hook scripts are executable** — check permissions
8. **send-feedback SKILL.md exists and has required sections** — verify the skill file has gh auth check, metrics scan, issue creation

- [ ] **Step 2: Run tests**

```bash
bash tests/test-self-improving.sh
```

- [ ] **Step 3: Commit**

```bash
git add tests/test-self-improving.sh
git commit -m "test: add validation tests for self-improving capabilities"
```

---

### Task 15: Update manifests and documentation [batch]

**Files:**
- Modify: `README.md`
- Modify: `RELEASE-NOTES.md`
- Modify: `package.json` (version bump)
- Modify: `skills/skills.json` (if exists, add send-feedback entry)

- [ ] **Step 1: Update README**

Add a brief section about the self-improving feedback loop — what it does, how to use `/stellar-powers:send-feedback`.

- [ ] **Step 2: Update RELEASE-NOTES**

Add version entry with feature summary.

- [ ] **Step 3: Bump version**

Bump to next minor version (e.g., 1.3.0).

- [ ] **Step 4: Commit**

```bash
git add README.md RELEASE-NOTES.md package.json
git commit -m "chore: bump version to 1.3.0 — self-improving capabilities release"
```
