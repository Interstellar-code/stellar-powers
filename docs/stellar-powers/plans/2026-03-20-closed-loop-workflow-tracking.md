# Closed-Loop Workflow Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use stellar-powers:subagent-driven-development (recommended) or stellar-powers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent workflow tracking to stellar-powers via JSONL event logging, PostToolUse hooks for compliance enforcement, and skill-level semantic logging for session continuity.

**Architecture:** Hybrid approach — a PostToolUse hook (bash script) logs Agent dispatches and checks persona template compliance. Skills log their own invocations and semantic milestones (spec created, plan created, review verdicts). A JSONL file in `.stellar-powers/workflow.jsonl` stores all events. The enhanced session-start hook parses this file to surface incomplete work.

**Tech Stack:** Bash (hooks), Markdown (skill templates), JSONL (event log)

**Spec:** `docs/stellar-powers/specs/2026-03-20-closed-loop-workflow-tracking-design.md`

---

### Task 1: Create the PostToolUse hook script

**Files:**
- Create: `hooks/post-tool-use`
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Write the post-tool-use hook script**

Create `hooks/post-tool-use` (extensionless, matching existing convention). This bash script:
1. Reads JSON from stdin
2. Extracts `cwd`, `tool_name`, `tool_input` using lightweight JSON parsing
3. Creates `.stellar-powers/` in `cwd` if missing
4. Appends an `agent_dispatch` event to `.stellar-powers/workflow.jsonl`
5. Checks for persona template markers in `tool_input.prompt`
6. If no markers and not exempt, appends `hook_violation` + prints warning to stderr

```bash
#!/usr/bin/env bash
# PostToolUse hook for stellar-powers plugin
# Logs Agent dispatches and checks persona template compliance.
# Receives JSON on stdin from Claude Code.
# MUST exit 0 in all cases (silent degradation).

# Read stdin into variable
INPUT=$(cat 2>/dev/null) || { exit 0; }

# Extract fields using python3 (available on macOS/Linux)
# Falls back to exit 0 if python3 unavailable
extract() {
    python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    # Navigate dotted path
    parts = sys.argv[2].split('.')
    val = data
    for p in parts:
        val = val[p]
    print(val if isinstance(val, str) else json.dumps(val))
except:
    print('')
" "$INPUT" "$1" 2>/dev/null || echo ""
}

CWD=$(extract "cwd")
TOOL_NAME=$(extract "tool_name")
SESSION_ID=$(extract "session_id")

# Only process Agent tool calls
if [ "$TOOL_NAME" != "Agent" ]; then
    exit 0
fi

# Ensure .stellar-powers directory exists
if [ -n "$CWD" ]; then
    mkdir -p "${CWD}/.stellar-powers" 2>/dev/null || exit 0
else
    exit 0
fi

WORKFLOW_FILE="${CWD}/.stellar-powers/workflow.jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

# Extract Agent tool input fields
PROMPT=$(extract "tool_input.prompt")
SUBAGENT_TYPE=$(extract "tool_input.subagent_type")
MODEL=$(extract "tool_input.model")
DESCRIPTION=$(extract "tool_input.description")

# Check for exempt dispatches
case "$SUBAGENT_TYPE" in
    Explore|Plan) exit 0 ;;
esac

# Check for built-in reviewer templates (also exempt)
case "$PROMPT" in
    *"spec document reviewer"*|*"code quality reviewer"*) exit 0 ;;
esac

# Detect persona template markers (case-insensitive via bash lowercasing)
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]' 2>/dev/null || echo "$PROMPT")
HAS_PERSONA="false"

MARKERS=(
    "you are a"
    "## agent persona catalog"
    "## persona summary"
    "### core:"
)

for marker in "${MARKERS[@]}"; do
    if [[ "$PROMPT_LOWER" == *"$marker"* ]]; then
        HAS_PERSONA="true"
        break
    fi
done

# Build agent_dispatch event
# Use python3 for safe JSON construction
python3 -c "
import json, sys
event = {
    'ts': sys.argv[1],
    'event': 'agent_dispatch',
    'workflow_id': '',
    'session': sys.argv[2],
    'data': {
        'persona': '',
        'task': sys.argv[3],
        'model': sys.argv[4],
        'has_persona_template': sys.argv[5] == 'true'
    }
}
print(json.dumps(event, ensure_ascii=False))
" "$TIMESTAMP" "$SESSION_ID" "$DESCRIPTION" "$MODEL" "$HAS_PERSONA" >> "$WORKFLOW_FILE" 2>/dev/null

# If no persona detected, log violation and warn
if [ "$HAS_PERSONA" = "false" ]; then
    # Truncate prompt for summary (first 100 chars)
    SUMMARY=$(echo "$PROMPT" | head -c 100 2>/dev/null || echo "(unknown)")

    python3 -c "
import json, sys
event = {
    'ts': sys.argv[1],
    'event': 'hook_violation',
    'workflow_id': '',
    'session': sys.argv[2],
    'data': {
        'type': 'missing_persona_template',
        'tool_input_summary': sys.argv[3],
        'reason': 'Agent dispatch missing persona template markers'
    }
}
print(json.dumps(event, ensure_ascii=False))
" "$TIMESTAMP" "$SESSION_ID" "$SUMMARY" >> "$WORKFLOW_FILE" 2>/dev/null

    echo "WARNING: Stellar Powers - Agent dispatch without persona template detected. Description: ${DESCRIPTION}" >&2
fi

exit 0
```

- [ ] **Step 2: Make the hook executable**

```bash
chmod +x hooks/post-tool-use
```

- [ ] **Step 3: Update hooks.json to add PostToolUse entry**

Read `hooks/hooks.json`. Add the `PostToolUse` key to the `hooks` object, after the existing `SessionStart` entry:

Current `hooks/hooks.json`:
```json
{
  "hooks": {
    "SessionStart": [...]
  }
}
```

Add after `SessionStart`:
```json
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
]
```

- [ ] **Step 4: Test the hook manually**

```bash
echo '{"session_id":"test-123","cwd":"/tmp/test-project","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"prompt":"You are a Software Architect. Review this code.","subagent_type":"general-purpose","model":"sonnet","description":"Review code"}}' | bash hooks/post-tool-use
```

Expected: exit 0, no stderr output (persona detected). Check `/tmp/test-project/.stellar-powers/workflow.jsonl` contains an `agent_dispatch` event with `has_persona_template: true`.

```bash
echo '{"session_id":"test-123","cwd":"/tmp/test-project","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"prompt":"Search the codebase for all test files","subagent_type":"general-purpose","model":"sonnet","description":"Search tests"}}' | bash hooks/post-tool-use
```

Expected: exit 0, stderr contains "WARNING: Stellar Powers - Agent dispatch without persona template detected". JSONL has both `agent_dispatch` (has_persona_template: false) and `hook_violation`.

```bash
echo '{"session_id":"test-123","cwd":"/tmp/test-project","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"prompt":"Find files","subagent_type":"Explore","model":"haiku","description":"Explore codebase"}}' | bash hooks/post-tool-use
```

Expected: exit 0, no new events in JSONL (Explore is exempt).

- [ ] **Step 5: Clean up test artifacts and commit**

```bash
rm -rf /tmp/test-project/.stellar-powers
git add hooks/post-tool-use hooks/hooks.json
git commit -m "feat: add PostToolUse hook for agent dispatch logging and persona enforcement"
```

---

### Task 2: Enhance session-start hook with workflow summary and migration notice

**Files:**
- Modify: `hooks/session-start:1-57`

- [ ] **Step 1: Read the current session-start hook**

Read `hooks/session-start` to understand the current structure. The hook currently:
1. Checks for legacy skills directory
2. Reads using-stellarpowers content
3. Escapes for JSON
4. Outputs context injection JSON

We need to add two features AFTER the existing `using_superpowers_escaped` and `warning_escaped` are computed but BEFORE the final `session_context` string is assembled:
1. Old-path migration notice
2. Workflow summary from `.stellar-powers/workflow.jsonl`

- [ ] **Step 2: Add migration notice logic**

After line 14 (the `warning_message` closing `fi`), add migration notice detection:

```bash
# Check for old-path specs/plans that need migration
migration_message=""
if [ -d "${PWD}/docs/stellar-powers/specs" ] || [ -d "${PWD}/docs/stellar-powers/plans" ]; then
    migration_message="\n\nStellar Powers: Specs/plans path changed from docs/stellar-powers/ to .stellar-powers/.\nFound existing files at old path. Run: mv docs/stellar-powers/specs/* .stellar-powers/specs/ && mv docs/stellar-powers/plans/* .stellar-powers/plans/"
fi
```

- [ ] **Step 3: Add workflow summary logic**

After the migration notice block, add workflow summary detection. This uses python3 to parse the JSONL and apply the completion rules from the spec:

```bash
# Check for incomplete workflows in .stellar-powers/workflow.jsonl
workflow_summary=""
WORKFLOW_FILE="${PWD}/.stellar-powers/workflow.jsonl"
if [ -f "$WORKFLOW_FILE" ]; then
    workflow_summary=$(python3 -c "
import json, sys
from datetime import datetime, timedelta, timezone

cutoff = datetime.now(timezone.utc) - timedelta(days=30)
events = []
try:
    with open(sys.argv[1]) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except:
                continue
except:
    sys.exit(0)

# Group by workflow_id
workflows = {}
for e in events:
    wid = e.get('workflow_id', '')
    if not wid:
        continue
    try:
        ts = datetime.fromisoformat(e['ts'].replace('Z', '+00:00'))
        if ts < cutoff:
            continue
    except:
        continue
    workflows.setdefault(wid, []).append(e)

# Check completion rules
incomplete = []
for wid, evts in workflows.items():
    event_types = [e['event'] for e in evts]

    # Abandoned workflows are terminal
    if 'workflow_abandoned' in event_types:
        continue

    for e in evts:
        if e['event'] != 'skill_invocation':
            continue
        skill = e.get('data', {}).get('skill', '')
        ts_str = e['ts'][:10]

        if skill == 'brainstorming':
            # Complete when review_verdict approved exists
            has_approval = any(
                ev['event'] == 'review_verdict' and ev.get('data', {}).get('verdict') == 'approved'
                for ev in evts
            )
            if not has_approval:
                spec_path = ''
                for ev in evts:
                    if ev['event'] == 'spec_created':
                        spec_path = ev.get('data', {}).get('path', '')
                status = f'spec written ({ts_str}) but review not approved' if any(ev['event'] == 'spec_created' for ev in evts) else f'started ({ts_str}) but no spec written'
                line = f'  - brainstorming [{wid[:8]}]: {status}'
                if spec_path:
                    line += f'\n    -> {spec_path}'
                incomplete.append(line)

        elif skill == 'writing-plans':
            has_plan = any(ev['event'] == 'plan_created' for ev in evts)
            if not has_plan:
                incomplete.append(f'  - writing-plans [{wid[:8]}]: plan not yet written ({ts_str})')

    # Check spec_created without approved review
    for e in evts:
        if e['event'] == 'spec_created':
            has_approval = any(
                ev['event'] == 'review_verdict' and ev.get('data', {}).get('verdict') == 'approved'
                for ev in evts
            )
            if not has_approval:
                path = e.get('data', {}).get('path', '')
                # Skip if already reported via brainstorming check
                if not any('brainstorming' in inc for inc in incomplete if wid[:8] in inc):
                    incomplete.append(f'  - spec [{wid[:8]}]: written but not approved\n    -> {path}')

    # Check plan_created without executing-plans
    for e in evts:
        if e['event'] == 'plan_created':
            has_execution = any(
                ev['event'] == 'skill_invocation' and ev.get('data', {}).get('skill') == 'executing-plans'
                for ev in evts
            )
            if not has_execution:
                path = e.get('data', {}).get('path', '')
                incomplete.append(f'  - plan [{wid[:8]}]: written but not started\n    -> {path}')

if incomplete:
    print('Stellar Powers — Incomplete work detected:')
    for line in incomplete:
        print(line)
    print()
    print('  To resume a workflow, invoke the relevant skill — it will pick up from workflow.jsonl.')
    print('  To abandon, tell Claude: \"abandon workflow [workflow_id]\"')
" "$WORKFLOW_FILE" 2>/dev/null) || workflow_summary=""
fi
```

- [ ] **Step 4: Integrate new messages into session_context**

Find the line that builds `session_context` (currently line 35). Update it to include migration and workflow messages:

Current:
```bash
session_context="<EXTREMELY_IMPORTANT>\nYou have stellar powers.\n\n**Below is the full content of your 'stellar-powers:using-stellar-powers' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${using_superpowers_escaped}\n\n${warning_escaped}\n</EXTREMELY_IMPORTANT>"
```

Change to:
```bash
migration_escaped=$(escape_for_json "$migration_message")
workflow_escaped=$(escape_for_json "$workflow_summary")
session_context="<EXTREMELY_IMPORTANT>\nYou have stellar powers.\n\n**Below is the full content of your 'stellar-powers:using-stellar-powers' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${using_superpowers_escaped}\n\n${warning_escaped}${migration_escaped}\n\n${workflow_escaped}\n</EXTREMELY_IMPORTANT>"
```

- [ ] **Step 5: Test the enhanced session-start hook**

Create a test workflow.jsonl:
```bash
mkdir -p /tmp/test-project/.stellar-powers
echo '{"ts":"2026-03-18T10:00:00Z","event":"skill_invocation","workflow_id":"abc-12345","session":"s1","data":{"skill":"brainstorming","args":"test feature"}}' > /tmp/test-project/.stellar-powers/workflow.jsonl
echo '{"ts":"2026-03-18T10:30:00Z","event":"spec_created","workflow_id":"abc-12345","session":"s1","data":{"path":".stellar-powers/specs/2026-03-18-test-design.md","skill":"brainstorming","topic":"test"}}' >> /tmp/test-project/.stellar-powers/workflow.jsonl
```

Run in the test directory:
```bash
cd /tmp/test-project && CLAUDE_PLUGIN_ROOT=/Users/rohits/dev/stellar-powers bash /Users/rohits/dev/stellar-powers/hooks/session-start
```

Expected: JSON output includes workflow summary mentioning "brainstorming [abc-1234]: spec written (2026-03-18) but review not approved".

- [ ] **Step 6: Clean up and commit**

```bash
rm -rf /tmp/test-project/.stellar-powers
git add hooks/session-start
git commit -m "feat: enhance session-start with workflow summary and migration notice"
```

---

### Task 3: Update brainstorming skill with workflow logging

**Files:**
- Modify: `skills/brainstorming/SKILL.md:29,114`
- Modify: `skills/brainstorming/spec-document-reviewer-prompt.md:7`

- [ ] **Step 1: Add workflow preamble to brainstorming skill**

At the top of the `## Checklist` section (before item 1), add a new item 0:

```markdown
0. **Workflow setup** — Generate workflow ID and log skill invocation:
   ```bash
   WF_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
   mkdir -p .stellar-powers/specs .stellar-powers/plans
   echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"skill_invocation\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"brainstorming\",\"args\":\"$(echo "$ARGS" | sed 's/"/\\\\"/g')\"}}" >> .stellar-powers/workflow.jsonl
   ```
   Also check `.stellar-powers/workflow.jsonl` for incomplete brainstorming workflows. If found, load the most recent workflow's context (spec path, last event) to inform your work. Do not re-prompt the user — session-start already surfaced incomplete work.
```

- [ ] **Step 2: Add spec_created logging after spec is written**

In the "After the Design" / "Documentation" section, after "Commit the design document to git", add:

```markdown
- Log spec creation to workflow:
  ```bash
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"spec_created\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"path\":\"SPEC_PATH\",\"skill\":\"brainstorming\",\"topic\":\"TOPIC\"}}" >> .stellar-powers/workflow.jsonl
  ```
  Replace `SPEC_PATH` and `TOPIC` with actual values.
```

- [ ] **Step 3: Update spec path references**

In `skills/brainstorming/SKILL.md`, change both occurrences:
- Line 29: `docs/stellar-powers/specs/YYYY-MM-DD-<topic>-design.md` → `.stellar-powers/specs/YYYY-MM-DD-<topic>-design.md`
- Line 114: `docs/stellar-powers/specs/YYYY-MM-DD-<topic>-design.md` → `.stellar-powers/specs/YYYY-MM-DD-<topic>-design.md`

In `skills/brainstorming/spec-document-reviewer-prompt.md`:
- Line 7: `docs/stellar-powers/specs/` → `.stellar-powers/specs/`

- [ ] **Step 4: Commit**

```bash
git add skills/brainstorming/SKILL.md skills/brainstorming/spec-document-reviewer-prompt.md
git commit -m "feat: add workflow logging to brainstorming skill + update spec paths"
```

---

### Task 4: Update writing-plans skill with workflow logging

**Files:**
- Modify: `skills/writing-plans/SKILL.md:18,130`

- [ ] **Step 1: Add workflow preamble**

Before the `## Scope Check` section, add:

```markdown
## Workflow Logging

On invocation, generate a workflow ID and log:

```bash
WF_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
mkdir -p .stellar-powers/specs .stellar-powers/plans
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"skill_invocation\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"writing-plans\",\"args\":\"\"}}" >> .stellar-powers/workflow.jsonl
```

Check `.stellar-powers/workflow.jsonl` for incomplete writing-plans workflows. If found, load the most recent workflow's context to inform your work. Do not re-prompt the user.

After saving the plan, log plan creation:

```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"plan_created\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"path\":\"PLAN_PATH\",\"skill\":\"writing-plans\",\"topic\":\"TOPIC\"}}" >> .stellar-powers/workflow.jsonl
```
```

- [ ] **Step 2: Update plan path references**

- Line 18: `docs/stellar-powers/plans/YYYY-MM-DD-<feature-name>.md` → `.stellar-powers/plans/YYYY-MM-DD-<feature-name>.md`
- Line 130: `docs/stellar-powers/plans/<filename>.md` → `.stellar-powers/plans/<filename>.md`

- [ ] **Step 3: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "feat: add workflow logging to writing-plans skill + update plan paths"
```

---

### Task 5: Update requesting-code-review skill with workflow logging

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md:61`

- [ ] **Step 1: Add workflow preamble**

After the skill description frontmatter and before "Dispatch stellar-powers:code-reviewer...", add:

```markdown
## Workflow Logging

On invocation, generate a workflow ID and log:

```bash
WF_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
mkdir -p .stellar-powers
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"skill_invocation\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"requesting-code-review\",\"args\":\"\"}}" >> .stellar-powers/workflow.jsonl
```

After each review verdict, log:

```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"review_verdict\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"verdict\":\"VERDICT\",\"reviewer_persona\":\"code-reviewer\",\"iteration\":N,\"spec_path\":\"PATH\"}}" >> .stellar-powers/workflow.jsonl
```

Replace `VERDICT` (approved/issues_found), `N` (iteration number), and `PATH` with actual values.
```

- [ ] **Step 2: Update path reference**

- Line 61: `docs/stellar-powers/plans/deployment-plan.md` → `.stellar-powers/plans/deployment-plan.md`

- [ ] **Step 3: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "feat: add workflow logging to requesting-code-review skill + update paths"
```

---

### Task 6: Update executing-plans skill with workflow logging

**Files:**
- Modify: `skills/executing-plans/SKILL.md`

- [ ] **Step 1: Add workflow preamble**

After the skill description frontmatter and before "## Overview", add:

```markdown
## Workflow Logging

On invocation, generate a workflow ID and log:

```bash
WF_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
mkdir -p .stellar-powers
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"skill_invocation\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"executing-plans\",\"args\":\"\"}}" >> .stellar-powers/workflow.jsonl
```

Check `.stellar-powers/workflow.jsonl` for incomplete executing-plans workflows. If found, load the most recent workflow's context to inform your work. Do not re-prompt the user.
```

- [ ] **Step 2: Commit**

```bash
git add skills/executing-plans/SKILL.md
git commit -m "feat: add workflow logging to executing-plans skill"
```

---

### Task 7: Update subagent-driven-development skill with workflow logging

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md:133`

- [ ] **Step 1: Add workflow preamble**

After the skill description frontmatter and before "# Subagent-Driven Development", add:

```markdown
## Workflow Logging

On invocation, generate a workflow ID and log:

```bash
WF_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
mkdir -p .stellar-powers
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"skill_invocation\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"subagent-driven-development\",\"args\":\"\"}}" >> .stellar-powers/workflow.jsonl
```

After each review verdict (spec compliance or code quality), log:

```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"review_verdict\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"verdict\":\"VERDICT\",\"reviewer_persona\":\"PERSONA\",\"iteration\":N,\"spec_path\":\"PATH\"}}" >> .stellar-powers/workflow.jsonl
```

Replace `VERDICT`, `PERSONA` (spec-reviewer/code-quality-reviewer), `N`, and `PATH` with actual values.

Check `.stellar-powers/workflow.jsonl` for incomplete workflows. If found, load context. Do not re-prompt.
```

- [ ] **Step 2: Update path reference**

- Line 133: `docs/stellar-powers/plans/feature-plan.md` → `.stellar-powers/plans/feature-plan.md`

- [ ] **Step 3: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat: add workflow logging to subagent-driven-development skill + update paths"
```

---

### Task 8: Add workflow abandonment to using-stellarpowers skill

**Files:**
- Modify: `skills/using-stellarpowers/SKILL.md`

- [ ] **Step 1: Add abandon workflow command documentation**

After the `## User Instructions` section at the end of the file, add:

```markdown
## Workflow Commands

**Abandon workflow:** When the user says "abandon workflow [workflow_id]", append an abandonment event:

```bash
mkdir -p .stellar-powers
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"workflow_abandoned\",\"workflow_id\":\"WORKFLOW_ID\",\"session\":\"\",\"data\":{\"reason\":\"user requested\"}}" >> .stellar-powers/workflow.jsonl
```

Replace `WORKFLOW_ID` with the ID provided by the user. Confirm: "Workflow [id] abandoned. It won't appear in future session summaries."
```

- [ ] **Step 2: Commit**

```bash
git add skills/using-stellarpowers/SKILL.md
git commit -m "feat: add workflow abandonment command to using-stellarpowers skill"
```

---

### Task 9: Version bump and final verification

**Files:**
- Modify: `package.json`

- [ ] **Step 1: Bump version to 1.0.6**

In `package.json`, change `"version": "1.0.5"` to `"version": "1.0.6"`.

- [ ] **Step 2: Verify all path references are updated**

Run:
```bash
grep -r "docs/stellar-powers/specs/\|docs/stellar-powers/plans/" skills/ --include="*.md"
```

Expected: No matches (all paths should now be `.stellar-powers/specs/` or `.stellar-powers/plans/`).

- [ ] **Step 3: Verify hooks.json is valid JSON**

```bash
python3 -c "import json; json.load(open('hooks/hooks.json'))"
```

Expected: No error.

- [ ] **Step 4: Verify post-tool-use hook is executable**

```bash
ls -la hooks/post-tool-use | grep "^-rwx"
```

Expected: File has execute permission.

- [ ] **Step 5: Run the existing test suite if present**

```bash
ls tests/ && echo "Run any existing tests" || echo "No test directory"
```

- [ ] **Step 6: Commit version bump**

```bash
git add package.json
git commit -m "chore: bump version to 1.0.6 for closed-loop workflow tracking"
```
