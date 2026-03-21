# Self-Improving v1.4.0 — Self-Improving Agent Skill and Bug Fixes

**Status:** Design approved
**Date:** 2026-03-21
**Workflow ID:** 4F93072F-6AB3-4E33-A32E-565FAD1EB8E8

## Problem

v1.3.0 shipped the self-improving feedback capture system. First real-world usage (Issue #1 on nyayasathi-app) revealed:

1. **Completion checkpoint doesn't run the metrics packager** — it logs `workflow_completed` but skips the packaging/pruning scripts
2. **Context fields resolve to "unknown"** — repo, task_type, sp_version not populated in metrics package
3. **`duration_minutes` = 0** — packager doesn't calculate from timestamps
4. **`steps_completed` = 0** for writing-plans and SDD — step logging not firing in those skills
5. **`active_step` stuck on "workflow_setup"** — `.active-workflow` step field never updated after initial creation
6. **No incremental metrics** — packaging only at terminal skill, partial/abandoned workflows produce no metrics
7. **No analysis or eval capability** — feedback issues accumulate but no tool to analyze them or verify improvements

## Scope

### Part 1: self-improving-agent skill (local to this repo)

A single Claude Code skill at `.claude/skills/self-improving-agent/SKILL.md` that combines analysis AND evaluation into one autoresearch-inspired loop:

```yaml
---
name: self-improving-agent
description: Use when working on the stellar-powers repo to analyze feedback issues, identify patterns, propose skill improvements, evaluate changes, and verify improvements via test scenarios
---
```

**The skill runs one unified loop:**

1. **Fetch feedback** — read all open `skill-feedback` labeled issues from `Interstellar-code/stellar-powers` via `gh`
2. **Parse and analyze** — extract Key Corrections, Patterns, User Feedback, Raw Metrics from each issue. Group by skill. Identify recurring patterns:
   - Correction themes (same feedback across workflows)
   - Common tool failures
   - Step coverage gaps
   - Context field resolution failures
3. **Run baseline eval** — execute test scenarios against current skill state. Score:
   - Event completeness: did all expected events fire? (0-100%)
   - Context field resolution: fields resolved vs "unknown" (0-100%)
   - Packaging: metrics package created with valid JSON? (pass/fail)
   - Pruning: workflow.jsonl pruned correctly? (pass/fail)
   - Duration calculation correct? (pass/fail)
4. **Propose changes** — based on analysis + eval gaps, propose specific skill file edits with reasoning and confidence
5. **Apply changes** — on approval, make the edits
6. **Re-run eval** — same test scenarios, compare scores. Did they improve?
7. **Report** — "Baseline score: 65%. After changes: 90%. Improvement confirmed on: [list]. Regression on: [none]."
8. **Close issues** — mark processed feedback issues as "incorporated"

**Test scenarios** are stored in `.claude/tests/skill-scenarios/` as JSON files:

```json
{
  "name": "basic-brainstorming-completion",
  "description": "Brainstorming workflow completes with spec creation",
  "setup": {
    "active_workflow": {"workflow_id": "TEST-001", "skill": "brainstorming", "topic": "test-feature", "repo": "test-repo", "sp_version": "1.4.0"},
    "workflow_events": [
      {"event": "skill_invocation", "data": {"skill": "brainstorming"}},
      {"event": "workflow_started", "data": {"skill": "brainstorming", "topic": "test-feature"}},
      {"event": "step_completed", "data": {"skill": "brainstorming", "step": "explore_context", "step_number": 1}},
      {"event": "spec_created", "data": {"path": "specs/test.md"}},
      {"event": "workflow_completed", "data": {"outcome": "success", "duration_minutes": 30}}
    ]
  },
  "hooks_to_test": [
    {"hook": "user-prompt-submit", "input": {"prompt": "yes looks good", "cwd": "TEMP_DIR"}, "expect_event": "user_message"},
    {"hook": "task-completed", "input": {"task_id": "1", "task_subject": "Test task"}, "expect_event": "task_completed"}
  ],
  "expected": {
    "metrics_package_exists": true,
    "metrics_fields_not_unknown": ["repo", "sp_version"],
    "workflow_summary_in_jsonl": true,
    "duration_minutes_gt_zero": true
  }
}
```

The skill also runs the existing `tests/test-self-improving.sh` as part of the eval.

**Not a plugin skill** — lives in `.claude/skills/` on this repo only. Only available when working on stellar-powers.

### Part 2: Bug fixes

#### Fix 1: Completion checkpoint must inline the packager

The completion checkpoint in terminal skills (SDD, executing-plans, TDD, finishing-branch) currently says "read snippets.md for packaging scripts." This doesn't work — the agent skips it.

**Fix:** Inline the actual bash commands directly in the completion checkpoint section of each terminal skill. The agent executes bash blocks it sees in the skill — it won't go read another file mid-execution.

The completion checkpoint section must contain the full packager and pruner python scripts as executable bash blocks, not references to another file.

#### Fix 2: Context fields — read .active-workflow BEFORE packaging

The packager reads `.active-workflow` to get repo, task_type, sp_version. But if the agent deletes `.active-workflow` before packaging, fields resolve to "unknown."

**Fix:** In the completion checkpoint, explicitly read `.active-workflow` fields into env vars BEFORE running the packager:
```bash
export SP_WF_ID="${WF_ID}"
export SP_REPO=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('repo','unknown'))" 2>/dev/null || echo "unknown")
export SP_TASK_TYPE=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('task_type','unknown'))" 2>/dev/null || echo "unknown")
export SP_VERSION=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('sp_version','unknown'))" 2>/dev/null || echo "unknown")
export SP_TOPIC=$(python3 -c "import json; print(json.load(open('.stellar-powers/.active-workflow')).get('topic','unknown'))" 2>/dev/null || echo "unknown")
```
Update the packager script to read `SP_REPO`, `SP_TASK_TYPE`, `SP_VERSION`, `SP_TOPIC` from env vars first, falling back to `.active-workflow` if env vars are empty. This means the packager itself must be modified — both in `snippets.md` and in every terminal skill's inlined packager block.

#### Fix 3: Duration calculation

Add to the packager script:
```python
if started and completed:
    try:
        start_dt = datetime.fromisoformat(started.replace('Z', '+00:00'))
        end_dt = datetime.fromisoformat(completed.replace('Z', '+00:00'))
        duration = int((end_dt - start_dt).total_seconds() / 60)
    except:
        duration = 0
```

#### Fix 4: Step tracking in writing-plans and SDD

Add explicit `step_started`/`step_completed` bash blocks at each major phase in:
- writing-plans: reading spec, library verification, writing tasks, plan review, execution handoff
- SDD: task extraction, each batch dispatch, each review cycle, completion checkpoint

Also update `.active-workflow` step field at each transition:
```bash
python3 -c "
import json
aw = json.load(open('.stellar-powers/.active-workflow'))
aw['step'] = 'STEP_NAME'
aw['step_number'] = N
json.dump(aw, open('.stellar-powers/.active-workflow.tmp', 'w'))
" && mv .stellar-powers/.active-workflow.tmp .stellar-powers/.active-workflow
```

#### Fix 5: Incremental metrics packaging

Add a "stage snapshot" at each handoff point:
- brainstorming → writing-plans: create partial metrics package with `"stage": "brainstorming"`
- writing-plans → SDD/executing-plans: update partial package with `"stage": "writing-plans"`
- Terminal skill completion: create full package, delete partials
- Abandon/hold at invocation gate: rename the `-partial.json` to `.json` (remove the `-partial` suffix) — the partial package becomes the final package for that workflow. No re-run of the packager needed since the partial already has the data up to that stage.

Partial packages use `-partial` suffix: `2026-03-21-topic-ABCD1234-partial.json`
Send-feedback sends both full and partial packages.

#### Fix 6: Update snippets.md

Update `skills/_shared/snippets.md` to reflect all fixes: update the packager code block to use env vars with `.active-workflow` fallback, add the env var export block, add duration calculation, add the `.active-workflow` step update pattern. Do not remove any existing snippets — only update the ones that changed. The snippets file remains as reference documentation — the actual executable code is inlined in each skill.

## Implementation Notes

- self-improving-agent is a LOCAL skill (`.claude/skills/`) not a plugin skill (`skills/`)
- Bug fixes modify plugin skills — require version bump to 1.4.0 and release
- The skill should follow writing-skills naming convention
- Test scenarios go in `.claude/tests/skill-scenarios/`
- The eval runs `tests/test-self-improving.sh` plus scenario-based tests
- Total files to create: 1 skill SKILL.md, 3-5 test scenario JSON files
- Total files to modify: 6 skill SKILL.md files (SDD, executing-plans, TDD, finishing-branch, writing-plans, brainstorming), snippets.md, package.json + manifests
