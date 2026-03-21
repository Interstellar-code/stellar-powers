# Self-Improving v1.4.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use stellar-powers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Create the self-improving-agent local skill, fix 6 bugs from Issue #1, add test scenarios, and release v1.4.0.

**Architecture:** One new local skill (`.claude/skills/self-improving-agent/SKILL.md`), bug fixes across 6 plugin skills + snippets.md, test scenarios in `.claude/tests/skill-scenarios/`.

**Tech Stack:** Bash, Python3, `gh` CLI, JSONL

**Spec:** `.stellar-powers/specs/2026-03-21-self-improving-v1.4.0-design.md`

**Commit strategy:** Group into 4 commits: skill creation, bug fixes, tests, manifests.

---

### Task 1: Create self-improving-agent local skill [solo]

**Files:**
- Create: `.claude/skills/self-improving-agent/SKILL.md`

- [ ] **Step 1: Create the skill directory and SKILL.md**

Create `.claude/skills/self-improving-agent/SKILL.md` with:

Frontmatter:
```yaml
---
name: self-improving-agent
description: Use when working on the stellar-powers repo to analyze skill-feedback GitHub issues, identify improvement patterns, evaluate current skill quality via test scenarios, propose and apply fixes, then verify improvements
---
```

The skill content instructs Claude to run the following loop:

**Phase 1: Gather feedback**
```bash
# Fetch all open skill-feedback issues
gh issue list --repo Interstellar-code/stellar-powers --label skill-feedback --state open --json number,title,body --limit 50
```
Parse each issue body to extract:
- Key Corrections section (per-skill corrections with step context)
- Patterns section (review iterations, violations, tool failures)
- User Feedback section
- Raw Metrics JSON from the `<details>` block

Group findings by skill. Identify recurring patterns across issues.

**Phase 2: Run baseline eval**
```bash
# Run existing tests
bash tests/test-self-improving.sh

# Run scenario-based tests
python3 .claude/tests/run-scenarios.py
```
Record baseline scores.

**Phase 3: Propose changes**
Based on analysis + eval gaps, list specific skill file edits with reasoning and confidence:
```
Skill: brainstorming
File: skills/brainstorming/SKILL.md
Change: Add explicit step_completed logging after each checklist item
Reason: steps_completed=0 in 3/3 feedback issues
Confidence: high (100% occurrence)
```

Present all proposals. On user approval, apply changes.

**Phase 4: Re-run eval**
```bash
bash tests/test-self-improving.sh
python3 .claude/tests/run-scenarios.py
```
Compare scores to baseline. Report improvement/regression per scenario.

**Phase 5: Close processed issues**
```bash
gh issue close NUMBER --repo Interstellar-code/stellar-powers --comment "Incorporated in v1.X.0. Changes: [summary]"
```

The skill should be concise — under 300 words for the main content, with bash blocks for the commands. Reference the test runner and scenario format but don't embed them.

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/self-improving-agent/SKILL.md
```

---

### Task 2: Create test scenario runner and scenarios [solo]

**Files:**
- Create: `.claude/tests/run-scenarios.py`
- Create: `.claude/tests/skill-scenarios/basic-workflow-completion.json`
- Create: `.claude/tests/skill-scenarios/context-field-resolution.json`
- Create: `.claude/tests/skill-scenarios/incremental-packaging.json`

- [ ] **Step 1: Create the scenario runner**

Create `.claude/tests/run-scenarios.py` — a Python script that:
1. Reads all `.json` files in `.claude/tests/skill-scenarios/`
2. For each scenario:
   a. Creates a temp directory
   b. Sets up `.stellar-powers/.active-workflow` from scenario's `setup.active_workflow`
   c. Writes initial events from `setup.workflow_events` to `workflow.jsonl`
   d. For each item in `hooks_to_test`: pipes the input JSON to the hook script, setting `cwd` to the temp dir
   e. Checks `expected` assertions:
      - `metrics_package_exists`: check `.stellar-powers/metrics/*.json` exists
      - `metrics_fields_not_unknown`: parse the package, verify listed fields are not "unknown"
      - `workflow_summary_in_jsonl`: grep for `workflow_summary` event
      - `duration_minutes_gt_zero`: check the field in metrics or summary
      - `event_types_present`: verify specific event types appear in workflow.jsonl
   f. Reports pass/fail per assertion, scores the scenario (passed/total assertions)
3. Prints aggregate report: `N scenarios, M passed, K failed, score: X%`

- [ ] **Step 2: Create test scenarios**

Create 3 scenario JSON files:

**basic-workflow-completion.json:** Tests that hooks fire, events are logged, and workflow.jsonl has expected structure. Tests user-prompt-submit, task-completed, stop hooks.

**context-field-resolution.json:** Tests that `.active-workflow` fields (repo, sp_version, task_type) are picked up by hooks and appear in events (not "unknown").

**incremental-packaging.json:** Tests that partial package creation works — creates a `-partial.json` file with stage info.

- [ ] **Step 3: Run the scenarios to establish baseline**

```bash
python3 .claude/tests/run-scenarios.py
```

- [ ] **Step 4: Commit**

```bash
git add .claude/tests/
```

---

### Task 3: Fix bugs in snippets.md and terminal skills [solo]

**Files:**
- Modify: `skills/_shared/snippets.md`
- Modify: `skills/subagent-driven-development/SKILL.md`
- Modify: `skills/executing-plans/SKILL.md`
- Modify: `skills/test-driven-development/SKILL.md`
- Modify: `skills/finishing-a-development-branch/SKILL.md`

This task applies Fixes 1, 2, 3, 4, and 6 from the spec.

- [ ] **Step 1: Update snippets.md**

Update the Metrics Packaging snippet:
- Read env vars `SP_REPO`, `SP_TASK_TYPE`, `SP_VERSION`, `SP_TOPIC` with fallback to `.active-workflow`
- Add duration calculation from timestamps
- The packager should use: `repo = os.environ.get("SP_REPO") or aw.get("repo", "unknown")`

Update the Completion Checkpoint snippet:
- Add env var export block BEFORE the packager call
- Include the full packager and pruner scripts inline (not as references)

Add new snippet: `.active-workflow` step update:
```bash
python3 -c "
import json
aw = json.load(open('.stellar-powers/.active-workflow'))
aw['step'] = 'STEP_NAME'
aw['step_number'] = N
json.dump(aw, open('.stellar-powers/.active-workflow.tmp', 'w'))
" && mv .stellar-powers/.active-workflow.tmp .stellar-powers/.active-workflow
```

- [ ] **Step 2: Update all 4 terminal skills**

For each of SDD, executing-plans, TDD, finishing-branch:
1. Replace the completion checkpoint section with inlined packager/pruner (not snippets.md reference)
2. Add env var export block before packager
3. Add `.active-workflow` step update at major phase transitions
4. Add explicit `step_started`/`step_completed` bash blocks at each phase

Read each SKILL.md before modifying. Preserve all existing content — only modify the completion checkpoint section and add step logging.

- [ ] **Step 3: Commit**

```bash
git add skills/
```

---

### Task 4: Fix step tracking in handoff skills + incremental packaging [solo]

**Files:**
- Modify: `skills/brainstorming/SKILL.md`
- Modify: `skills/writing-plans/SKILL.md`

This task applies Fixes 4 and 5 from the spec.

- [ ] **Step 1: Update brainstorming SKILL.md**

Read the file first. Add:
- `.active-workflow` step update at each major phase (explore_context, clarifying_questions, propose_approaches, present_design, write_doc, spec_review, user_review)
- Stage snapshot at handoff: before invoking writing-plans, run the packager with `"stage": "brainstorming"` to create a partial metrics package

- [ ] **Step 2: Update writing-plans SKILL.md**

Read the file first. Add:
- `.active-workflow` step update at each major phase (reading_spec, library_verification, writing_tasks, plan_review, execution_handoff)
- Stage snapshot at handoff: before invoking SDD/executing-plans, run the packager with `"stage": "writing-plans"` to create/update the partial metrics package
- Delete previous partial package before creating new one (brainstorming partial superseded by writing-plans partial)

- [ ] **Step 3: Commit**

```bash
git add skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md
```

---

### Task 5: Update tests and run full validation [solo]

**Files:**
- Modify: `tests/test-self-improving.sh`

- [ ] **Step 1: Update existing tests**

Add tests for:
- Duration calculation in packager
- Env var fallback in packager (SP_REPO etc.)
- Partial package creation with `-partial` suffix
- `.active-workflow` step update pattern

- [ ] **Step 2: Run all tests**

```bash
bash tests/test-self-improving.sh
python3 .claude/tests/run-scenarios.py
```

Both must pass.

- [ ] **Step 3: Commit**

```bash
git add tests/
```

---

### Task 6: Version bump and release [batch]

**Files:**
- Modify: `package.json`
- Modify: `gemini-extension.json`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `.cursor-plugin/plugin.json`
- Modify: `RELEASE-NOTES.md`

- [ ] **Step 1: Bump version to 1.4.0 in ALL 5 manifest files**

Read each file, change version from 1.3.0 to 1.4.0.

- [ ] **Step 2: Update RELEASE-NOTES.md**

Add at the top:
```markdown
## v1.4.0 — Self-Improving Agent + Bug Fixes

- **New local skill:** `self-improving-agent` — analyzes feedback issues, runs eval scenarios, proposes and verifies skill improvements (autoresearch-inspired loop)
- **Fix:** Completion checkpoint now inlines packager/pruner scripts (was referencing snippets.md which agents skipped)
- **Fix:** Context fields (repo, task_type, sp_version) now resolve correctly via env vars with .active-workflow fallback
- **Fix:** Duration calculation added to metrics packager
- **Fix:** Step tracking now fires in writing-plans and SDD skills
- **Fix:** .active-workflow step field updates at each phase transition
- **New:** Incremental metrics packaging — partial snapshots at each skill handoff
- **New:** Test scenario runner with 3 baseline scenarios
```

- [ ] **Step 3: Commit all together**

```bash
git add package.json gemini-extension.json .claude-plugin/ .cursor-plugin/ RELEASE-NOTES.md .claude/ skills/ tests/
git commit -m "chore: bump version to 1.4.0 — self-improving agent + bug fixes"
```

- [ ] **Step 4: Push, tag, and release**

```bash
git push origin main
git tag v1.4.0
git push origin v1.4.0
gh release create v1.4.0 --repo Interstellar-code/stellar-powers --title "v1.4.0 — Self-Improving Agent + Bug Fixes" --notes "See RELEASE-NOTES.md for details"
```
