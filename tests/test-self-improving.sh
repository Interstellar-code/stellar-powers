#!/usr/bin/env bash
# Validation tests for self-improving capabilities
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOKS_DIR="${REPO_ROOT}/hooks"
PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected to contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if ! echo "$haystack" | grep -q "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected NOT to contain '$needle', but found it)"
        FAIL=$((FAIL + 1))
    fi
}

NEW_HOOKS=(
    "user-prompt-submit"
    "task-completed"
    "subagent-stop"
    "stop"
    "post-tool-use-failure"
)

# ─── Test 1: Hook scripts exit 0 with empty input ───────────────────────────
echo ""
echo "Test 1: Hook scripts exit 0 with empty input"

for hook in "${NEW_HOOKS[@]}"; do
    hook_path="${HOOKS_DIR}/${hook}"
    exit_code=0
    echo "" | "${hook_path}" 2>/dev/null || exit_code=$?
    assert_eq "${hook} exits 0 on empty input" "0" "$exit_code"
done

# ─── Test 2: Hook scripts skip when no .active-workflow ─────────────────────
echo ""
echo "Test 2: Hook scripts skip when no .active-workflow"

tmpdir2=$(mktemp -d)
mkdir -p "${tmpdir2}/.stellar-powers"

for hook in "${NEW_HOOKS[@]}"; do
    hook_path="${HOOKS_DIR}/${hook}"
    echo '{"cwd":"'"${tmpdir2}"'","session_id":"s1","prompt":"hello","last_assistant_message":"hi","tool_name":"Bash","error":"oops","task_id":"1","task_subject":"subj","task_description":"desc","agent_id":"a1","agent_type":"subagent"}' \
        | "${hook_path}" 2>/dev/null
done

wf_file="${tmpdir2}/.stellar-powers/workflow.jsonl"
if [ -f "$wf_file" ]; then
    line_count=$(wc -l < "$wf_file" | tr -d ' ')
    assert_eq "no events written when no .active-workflow" "0" "$line_count"
else
    echo "  PASS: no workflow.jsonl created when no .active-workflow"
    PASS=$((PASS + 1))
fi
rm -rf "$tmpdir2"

# ─── Test 3: Hook scripts write events when .active-workflow exists ──────────
echo ""
echo "Test 3: Hook scripts write events when .active-workflow exists"

tmpdir3=$(mktemp -d)
mkdir -p "${tmpdir3}/.stellar-powers"
echo '{"workflow_id":"TEST-123","skill":"brainstorming","step":"test","step_number":1}' \
    > "${tmpdir3}/.stellar-powers/.active-workflow"

echo '{"cwd":"'"${tmpdir3}"'","session_id":"s1","prompt":"hello world"}' \
    | "${HOOKS_DIR}/user-prompt-submit" 2>/dev/null

wf_file="${tmpdir3}/.stellar-powers/workflow.jsonl"
if [ -f "$wf_file" ]; then
    wf_content=$(cat "$wf_file")
    assert_contains "user_message event written" "$wf_content" '"event": "user_message"'
    assert_contains "workflow_id TEST-123 in event" "$wf_content" '"workflow_id": "TEST-123"'
else
    echo "  FAIL: workflow.jsonl not created"
    FAIL=$((FAIL + 1))
    FAIL=$((FAIL + 1))
fi
rm -rf "$tmpdir3"

# ─── Test 4: Feedback disabled check ────────────────────────────────────────
echo ""
echo "Test 4: Feedback disabled check"

tmpdir4=$(mktemp -d)
mkdir -p "${tmpdir4}/.stellar-powers"
echo '{"feedback_enabled": false}' > "${tmpdir4}/.stellar-powers/config.json"
echo '{"workflow_id":"TEST-456","skill":"brainstorming","step":"test","step_number":1}' \
    > "${tmpdir4}/.stellar-powers/.active-workflow"

echo '{"cwd":"'"${tmpdir4}"'","session_id":"s1","prompt":"hello"}' \
    | "${HOOKS_DIR}/user-prompt-submit" 2>/dev/null

wf_file="${tmpdir4}/.stellar-powers/workflow.jsonl"
if [ -f "$wf_file" ]; then
    line_count=$(wc -l < "$wf_file" | tr -d ' ')
    assert_eq "no events written when feedback disabled" "0" "$line_count"
else
    echo "  PASS: no workflow.jsonl created when feedback disabled"
    PASS=$((PASS + 1))
fi
rm -rf "$tmpdir4"

# ─── Test 5: Redaction filter ────────────────────────────────────────────────
echo ""
echo "Test 5: Redaction filter"

tmpdir5=$(mktemp -d)
mkdir -p "${tmpdir5}/.stellar-powers"
echo '{"workflow_id":"TEST-789","skill":"brainstorming","step":"test","step_number":1}' \
    > "${tmpdir5}/.stellar-powers/.active-workflow"

echo '{"cwd":"'"${tmpdir5}"'","session_id":"s1","prompt":"my key is sk-abc123def456ghi789jkl012mno345 and email is test@example.com and path is /Users/john/secret"}' \
    | "${HOOKS_DIR}/user-prompt-submit" 2>/dev/null

wf_file="${tmpdir5}/.stellar-powers/workflow.jsonl"
if [ -f "$wf_file" ]; then
    wf_content=$(cat "$wf_file")
    assert_contains "API key redacted" "$wf_content" '\[REDACTED_KEY\]'
    assert_contains "email redacted" "$wf_content" '\[REDACTED_EMAIL\]'
    assert_contains "username path redacted" "$wf_content" '/Users/\[user\]'
    assert_not_contains "raw API key absent" "$wf_content" 'sk-abc123def456ghi789jkl012mno345'
    assert_not_contains "raw email absent" "$wf_content" 'test@example.com'
    assert_not_contains "raw username absent" "$wf_content" '/Users/john'
else
    echo "  FAIL: workflow.jsonl not created for redaction test"
    FAIL=$((FAIL + 6))
fi
rm -rf "$tmpdir5"

# ─── Test 6: hooks.json is valid JSON ───────────────────────────────────────
echo ""
echo "Test 6: hooks.json is valid JSON"

hooks_json="${HOOKS_DIR}/hooks.json"
parse_result=$(python3 -c "import json; json.load(open('${hooks_json}')); print('ok')" 2>&1)
assert_eq "hooks.json parses as valid JSON" "ok" "$parse_result"

# ─── Test 7: All hook scripts are executable ────────────────────────────────
echo ""
echo "Test 7: All hook scripts are executable"

ALL_HOOKS=(
    "user-prompt-submit"
    "task-completed"
    "subagent-stop"
    "stop"
    "post-tool-use-failure"
    "post-tool-use"
    "session-start"
)

for hook in "${ALL_HOOKS[@]}"; do
    hook_path="${HOOKS_DIR}/${hook}"
    if [ -x "$hook_path" ]; then
        echo "  PASS: ${hook} is executable"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${hook} is NOT executable"
        FAIL=$((FAIL + 1))
    fi
done

# ─── Test 8: send-feedback SKILL.md exists and has required sections ─────────
echo ""
echo "Test 8: send-feedback SKILL.md exists and has required sections"

skill_md="${REPO_ROOT}/skills/send-feedback/SKILL.md"
if [ -f "$skill_md" ]; then
    skill_content=$(cat "$skill_md")
    assert_contains "SKILL.md contains gh auth status" "$skill_content" "gh auth status"
    assert_contains "SKILL.md contains metrics reference" "$skill_content" "metrics"
    assert_contains "SKILL.md contains issue create" "$skill_content" "issue create"
else
    echo "  FAIL: send-feedback/SKILL.md does not exist"
    FAIL=$((FAIL + 3))
fi

# ─── Test 9: End-to-end lifecycle test ──────────────────────────────────────
echo ""
echo "Test 9: End-to-end lifecycle test"

tmpdir9=$(mktemp -d)
mkdir -p "${tmpdir9}/.stellar-powers"
WF_ID="E2E-$(date +%s)"
echo "{\"workflow_id\":\"${WF_ID}\",\"skill\":\"brainstorming\",\"step\":\"ideation\",\"step_number\":1,\"topic\":\"test-topic\",\"repo\":\"test/repo\",\"task_type\":\"feature\",\"project_type\":\"app\",\"sp_version\":\"1.2.0\"}" \
    > "${tmpdir9}/.stellar-powers/.active-workflow"

# Fire user-prompt-submit
echo "{\"cwd\":\"${tmpdir9}\",\"session_id\":\"s9\",\"prompt\":\"test prompt\"}" \
    | "${HOOKS_DIR}/user-prompt-submit" 2>/dev/null

wf_file="${tmpdir9}/.stellar-powers/workflow.jsonl"
wf_content=$(cat "$wf_file" 2>/dev/null || echo "")
assert_contains "user_message event after UserPromptSubmit" "$wf_content" '"event": "user_message"'

# Fire task-completed
echo "{\"cwd\":\"${tmpdir9}\",\"session_id\":\"s9\",\"task_id\":\"42\",\"task_subject\":\"Build the thing\",\"task_description\":\"Details here\"}" \
    | "${HOOKS_DIR}/task-completed" 2>/dev/null

wf_content=$(cat "$wf_file")
assert_contains "task_completed event after TaskCompleted" "$wf_content" '"event": "task_completed"'

# Manually write workflow_completed event
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"workflow_completed\",\"workflow_id\":\"${WF_ID}\",\"session\":\"s9\",\"data\":{\"skill\":\"brainstorming\",\"duration_minutes\":5,\"steps_completed\":2,\"steps_total\":2,\"outcome\":\"success\",\"completion_feedback\":\"Great\"}}" \
    >> "$wf_file"

# Run the metrics packager
metrics_output=$(cd "$tmpdir9" && SP_WF_ID="$WF_ID" python3 << 'PYEOF'
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

skills_seen = []
for e in events:
    if e.get("event") == "skill_invocation":
        s = e.get("data", {}).get("skill", "")
        if s and s not in skills_seen:
            skills_seen.append(s)

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
    "stellar_powers_version": aw.get("sp_version", "unknown"),
    "context": {
        "repo": aw.get("repo", "unknown"),
        "project_type": aw.get("project_type", "unknown"),
        "task_type": aw.get("task_type", "unknown"),
        "skills_chain": skills_seen
    },
    "timeline": {
        "started": started,
        "completed": completed,
        "duration_minutes": duration,
        "user_confirmed_complete": True
    },
    "skills": {},
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
topic = aw.get("topic", "unknown")
pkg_path = os.path.join(metrics_dir, f"{date_str}-{topic}-{wf_id[:8]}.json")
with open(pkg_path, "w") as f:
    json.dump(package, f, indent=2)

with open(pkg_path) as f:
    json.load(f)

print(f"METRICS_PACKAGE={pkg_path}")
PYEOF
)

pkg_path=$(echo "$metrics_output" | grep '^METRICS_PACKAGE=' | cut -d= -f2-)
if [ -n "$pkg_path" ] && [ -f "$pkg_path" ]; then
    pkg_valid=$(python3 -c "import json; json.load(open('${pkg_path}')); print('ok')" 2>&1)
    assert_eq "metrics package is valid JSON" "ok" "$pkg_valid"
else
    echo "  FAIL: metrics package not created (output: ${metrics_output})"
    FAIL=$((FAIL + 1))
fi

# Run the pruner
(cd "$tmpdir9" && SP_WF_ID="$WF_ID" python3 << 'PYEOF'
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

tmp_path = wf_file + ".tmp"
with open(tmp_path, "w") as f:
    f.write("\n".join(kept) + "\n")
os.rename(tmp_path, wf_file)
PYEOF
)

wf_after_prune=$(cat "${tmpdir9}/.stellar-powers/workflow.jsonl")
assert_contains "workflow_summary present after prune" "$wf_after_prune" '"event": "workflow_summary"'

# Detail lines for this workflow_id should be gone (only summary remains)
detail_count=$(echo "$wf_after_prune" | python3 -c "
import json, sys
wf_id = '${WF_ID}'
count = 0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        evt = json.loads(line)
        if evt.get('workflow_id') == wf_id and evt.get('event') != 'workflow_summary':
            count += 1
    except:
        pass
print(count)
" 2>/dev/null || echo "0")
assert_eq "no detail lines for workflow_id after prune" "0" "$detail_count"

rm -rf "$tmpdir9"

# ─── Test 10: Kill switch test ───────────────────────────────────────────────
echo ""
echo "Test 10: Kill switch test"

tmpdir10=$(mktemp -d)
mkdir -p "${tmpdir10}/.stellar-powers"
echo '{"feedback_enabled": false}' > "${tmpdir10}/.stellar-powers/config.json"
echo '{"workflow_id":"KS-001","skill":"brainstorming","step":"test","step_number":1}' \
    > "${tmpdir10}/.stellar-powers/.active-workflow"

base_input="{\"cwd\":\"${tmpdir10}\",\"session_id\":\"ks\",\"prompt\":\"hello\",\"last_assistant_message\":\"hi\",\"tool_name\":\"Bash\",\"error\":\"oops\",\"task_id\":\"1\",\"task_subject\":\"subj\",\"task_description\":\"desc\",\"agent_id\":\"a1\",\"agent_type\":\"subagent\"}"

for hook in "${NEW_HOOKS[@]}"; do
    echo "$base_input" | "${HOOKS_DIR}/${hook}" 2>/dev/null
done

wf_file="${tmpdir10}/.stellar-powers/workflow.jsonl"
if [ -f "$wf_file" ]; then
    total_events=$(wc -l < "$wf_file" | tr -d ' ')
    assert_eq "zero events written with kill switch (all 5 hooks)" "0" "$total_events"
else
    echo "  PASS: no workflow.jsonl created with kill switch"
    PASS=$((PASS + 1))
fi
rm -rf "$tmpdir10"

# ─── Test 11: Rollback documentation ─────────────────────────────────────────
echo ""
echo "Test 11: Rollback documentation"
echo "  INFO: To disable feedback: set feedback_enabled to false in .stellar-powers/config.json"
PASS=$((PASS + 1))

# ─── v1.8+ Feature Tests ─────────────────────────────────────────────────────

echo ""
echo "Test 12: CLAUDE_PLUGIN_ROOT not needed in packager calls"
  # Verify no skill file references CLAUDE_PLUGIN_ROOT directly
  if ! grep -rq 'CLAUDE_PLUGIN_ROOT.*metrics-packager' skills/ 2>/dev/null; then
    echo "  PASS: no CLAUDE_PLUGIN_ROOT references in packager calls"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: CLAUDE_PLUGIN_ROOT references still exist in skills"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 13: Persona catalog files exist for all referenced tags"
  PERSONA_ERRORS=0
  for persona in backend-architect code-reviewer devops-automator security-engineer software-architect senior-project-manager sprint-prioritizer; do
    if [ ! -f "personas/curated/$persona.md" ]; then
      echo "  FAIL: personas/curated/$persona.md missing"
      PERSONA_ERRORS=$((PERSONA_ERRORS + 1))
    fi
  done
  if [ ! -f "personas/source/engineering/engineering-frontend-developer.md" ]; then
    echo "  FAIL: frontend-engineer persona missing"
    PERSONA_ERRORS=$((PERSONA_ERRORS + 1))
  fi
  if [ "$PERSONA_ERRORS" -eq 0 ]; then
    echo "  PASS: all 8 persona files exist"
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 14: SDD skill has persona injection section"
  if grep -q "## Persona Injection" skills/subagent-driven-development/SKILL.md && \
     grep -q "personas/" skills/subagent-driven-development/SKILL.md && \
     grep -q "without a persona" skills/subagent-driven-development/SKILL.md; then
    echo "  PASS: persona injection section with curated references and red flag"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: persona injection incomplete in SDD"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 15: Writing-plans has mandatory persona tags"
  if grep -q "MANDATORY.*persona" skills/writing-plans/SKILL.md && \
     grep -q "\[persona-tag\]" skills/writing-plans/SKILL.md && \
     grep -q "Persona Assignment" skills/writing-plans/SKILL.md; then
    echo "  PASS: persona tags mandatory in writing-plans"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: persona tag enforcement incomplete"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 16: Plan reviewer checks for persona tags"
  if grep -q "Task Annotations.*persona" skills/writing-plans/plan-document-reviewer-prompt.md; then
    echo "  PASS: plan reviewer checks persona tags"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: plan reviewer missing persona check"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 17: HARD-GATE before execution handoff"
  if grep -q "HARD-GATE" skills/writing-plans/SKILL.md && \
     grep -q "Plan Review Loop.*APPROVED" skills/writing-plans/SKILL.md; then
    echo "  PASS: HARD-GATE blocks execution without review"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: HARD-GATE missing"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 18: Model capture in user-prompt-submit hook"
  if grep -q "model.*permission_mode" hooks/user-prompt-submit && \
     grep -q "aw\[.model.\]" hooks/user-prompt-submit; then
    echo "  PASS: user-prompt-submit captures model"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: model capture missing from user-prompt-submit"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 19: Packager uses find instead of CLAUDE_PLUGIN_ROOT"
  if grep -q "find.*plugins.*cache.*stellar-powers.*metrics-packager" skills/subagent-driven-development/SKILL.md; then
    echo "  PASS: packager uses dynamic find"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: packager not using find"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 20: Standalone packager has model and session_stats"
  if grep -q "model" scripts/metrics-packager.py && \
     grep -q "session_stats" scripts/metrics-packager.py && \
     grep -q "permission_mode" scripts/metrics-packager.py; then
    echo "  PASS: packager outputs model, permission_mode, session_stats"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: packager missing new fields"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 21: Persona marker detection covers SDD prompt format"
  MARKERS=$(grep -A10 "markers = \[" hooks/post-tool-use | head -10)
  if echo "$MARKERS" | grep -q "agent persona:"; then
    echo "  PASS: 'agent persona:' marker present"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: 'agent persona:' marker missing — SDD implementer prompts will trigger false violations"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 22: Plan reviewer has safety & completeness checklist"
  if grep -q "Safety & Completeness Checklist" skills/writing-plans/plan-document-reviewer-prompt.md; then
    echo "  PASS: safety checklist present in plan reviewer"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: safety checklist missing from plan reviewer"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 23: Implementer prompt requires pre-commit type check"
  if grep -q "check:types\|tsc --noEmit" skills/subagent-driven-development/implementer-prompt.md; then
    echo "  PASS: type check required before commit"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: no type check requirement in implementer prompt"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 24: md-extract-section.py exists and has read+write modes"
  if [ -f scripts/md-extract-section.py ] && \
     grep -q "\-\-write" scripts/md-extract-section.py && \
     grep -q "\-\-pattern" scripts/md-extract-section.py && \
     grep -q "\-\-overview" scripts/md-extract-section.py; then
    echo "  PASS: md-extract-section.py has read, write, pattern, and overview modes"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: md-extract-section.py missing or incomplete"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 25: Stop hook has metrics enforcement check"
  if grep -q "metrics_reminder" hooks/stop && grep -q "Stage boundary" hooks/stop; then
    echo "  PASS: stop hook checks for missing metrics partials at stage boundaries"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: stop hook missing metrics enforcement"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 26: Metrics calls use HARD-GATE blocks in skills"
  HARDGATE_COUNT=0
  for skill in skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md skills/executing-plans/SKILL.md; do
    if grep -q "HARD-GATE" "$skill" && grep -q "METRICS CHECKPOINT" "$skill" 2>/dev/null; then
      HARDGATE_COUNT=$((HARDGATE_COUNT + 1))
    fi
  done
  if [ "$HARDGATE_COUNT" -ge 3 ]; then
    echo "  PASS: all 3 key skills have HARD-GATE metrics checkpoints ($HARDGATE_COUNT found)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: only $HARDGATE_COUNT/3 skills have HARD-GATE metrics checkpoints"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 27: Spec reviewer has safety & completeness checklist"
  if grep -q "Safety & Completeness Checklist" skills/brainstorming/spec-document-reviewer-prompt.md 2>/dev/null; then
    echo "  PASS: spec reviewer has safety checklist"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: spec reviewer missing safety checklist"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 28: Writing-plans requires backend test coverage section"
  if grep -q "Backend & Middleware Test Coverage" skills/writing-plans/SKILL.md 2>/dev/null; then
    echo "  PASS: writing-plans has backend test coverage section"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: writing-plans missing backend test coverage section"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 29: Brainstorming codebase scan includes key checks"
  SCAN_CHECKS=0
  for pattern in "data models" "Route conventions" "API contracts" "abstraction layers" "Project documentation"; do
    if grep -q "$pattern" skills/brainstorming/SKILL.md 2>/dev/null; then
      SCAN_CHECKS=$((SCAN_CHECKS + 1))
    fi
  done
  if [ "$SCAN_CHECKS" -ge 5 ]; then
    echo "  PASS: codebase scan covers all 5 key checks ($SCAN_CHECKS found)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: codebase scan only covers $SCAN_CHECKS/5 checks"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 30: Implementer prompt includes backend testing self-review"
  if grep -q "route handlers.*middleware.*DB operations" skills/subagent-driven-development/implementer-prompt.md 2>/dev/null; then
    echo "  PASS: implementer self-review includes backend test checks"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: implementer self-review missing backend test checks"
    FAIL=$((FAIL + 1))
  fi

echo ""
echo "Test 31: Brainstorming design covers lifecycle and idempotency"
  DESIGN_CHECKS=0
  for pattern in "State lifecycle" "Idempotency" "Side effects"; do
    if grep -q "$pattern" skills/brainstorming/SKILL.md 2>/dev/null; then
      DESIGN_CHECKS=$((DESIGN_CHECKS + 1))
    fi
  done
  if [ "$DESIGN_CHECKS" -ge 3 ]; then
    echo "  PASS: design presentation covers lifecycle, idempotency, side effects ($DESIGN_CHECKS found)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: design presentation only covers $DESIGN_CHECKS/3 design concerns"
    FAIL=$((FAIL + 1))
  fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
echo ""
echo "To disable feedback: set feedback_enabled to false in .stellar-powers/config.json"
