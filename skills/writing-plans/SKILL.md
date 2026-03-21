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

Check `.stellar-powers/workflow.jsonl` for incomplete writing-plans workflows. If found, load the most recent workflow's context to inform your work. Do not re-prompt the user.

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

## Execution Handoff

After saving the plan, offer execution choice:

**"Plan complete and saved to `.stellar-powers/plans/<filename>.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?"**

**If Subagent-Driven chosen:**
- **REQUIRED SUB-SKILL:** Use stellar-powers:subagent-driven-development
- Fresh subagent per task + two-stage review

**If Inline Execution chosen:**
- **REQUIRED SUB-SKILL:** Use stellar-powers:executing-plans
- Batch execution with checkpoints for review
