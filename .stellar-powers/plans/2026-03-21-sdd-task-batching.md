# SDD Task Batching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use stellar-powers:subagent-driven-development (recommended) or stellar-powers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add task batching to subagent-driven-development so small mechanical tasks are grouped 2-4 per sub-agent, with `[batch]`/`[solo]` annotations emitted by writing-plans.

**Architecture:** Three file modifications: (1) SDD SKILL.md gets a new "Task Batching" section with grouping logic, SHA parsing, and batched review flow, (2) implementer-prompt.md gets a multi-task variant, (3) writing-plans SKILL.md gets annotation instructions in its Task Structure section.

**Tech Stack:** Markdown skill files only — no code, no scripts.

**Spec:** `.stellar-powers/specs/2026-03-21-sdd-task-batching-design.md`

**Failure recovery:** If any task fails midway and the file is in a broken state, run `git checkout -- <file>` to restore it, then re-attempt. Do not leave files in intermediate states.

---

## File Structure

| Action | File | Change |
|---|---|---|
| Modify | `skills/writing-plans/SKILL.md` | Add `[batch]`/`[solo]` annotation instruction to Task Structure section |
| Modify | `skills/subagent-driven-development/SKILL.md` | Add Task Batching section after Handling Implementer Status |
| Modify | `skills/subagent-driven-development/implementer-prompt.md` | Add multi-task variant after the existing single-task template |

---

### Task 1: Add batch/solo annotations to writing-plans [solo]

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

- [ ] **Step 1: Read the current file**

Read `skills/writing-plans/SKILL.md`. Locate the "Task Structure" section (around line 120). The task template starts with:
````markdown
### Task N: [Component Name]
````

Also locate the `## Remember` section that follows the Task Structure template block. If `## Remember` doesn't exist, the insertion goes after the Task Structure template's closing code fence.

- [ ] **Step 2: Add annotation instruction**

In the "Task Structure" section, change the task heading template from:
```
### Task N: [Component Name]
```
to:
```
### Task N: [Component Name] [batch|solo]
```

Then, immediately after the closing code fence of the Task Structure template block, BEFORE the `## Remember` section (or at end of file if `## Remember` doesn't exist), insert using the Edit tool:

```markdown
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
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -En "\[batch\]|\[solo\]" skills/writing-plans/SKILL.md
```

Expected: Multiple lines showing the annotation template and the new section. Count should be 4+ (template heading, section title, batch signals heading, solo signals heading).

- [ ] **Step 4: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "feat: add [batch]/[solo] task annotations to writing-plans"
```

---

### Task 2: Add Task Batching section to SDD SKILL.md [solo]

This is the largest change — adds the complete batching logic, SHA parsing, and batched review flow.

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

- [ ] **Step 1: Read the current file**

Read `skills/subagent-driven-development/SKILL.md`. Locate:
- "Handling Implementer Status" section (around line 124) — ends with the line `**Never** ignore an escalation or force the same model to retry without changes. If the implementer said it's stuck, something needs to change.`
- "Prompt Templates" section (around line 142)

The new section goes between these two. Confirm both anchors exist before proceeding.

- [ ] **Step 2: Insert Task Batching section**

After the "Handling Implementer Status" section's last line, and BEFORE `## Prompt Templates`, insert using the Edit tool. The content below contains code examples inside it — use the Edit tool's old_string/new_string approach to insert, NOT echo/heredoc:

**Content to insert:**

---

## Task Batching

Group consecutive small tasks into batches of 2-4 per sub-agent to reduce dispatch overhead. Solo tasks always get their own sub-agent.

### Reading Annotations

Plans annotated by `writing-plans` include `[batch]` or `[solo]` in each task heading:

    ### Task 1: Install deps [batch]
    ### Task 2: Add i18n keys [batch]
    ### Task 3: Design API contract [solo]

**Fallback for unannotated tasks:** If a task has no annotation, classify it using the complexity signals:
- **Batch** if ALL: touches 1-2 files, mechanical steps, no integration concerns, no judgment/architecture language, no dependencies on other tasks
- **Solo** if ANY: touches 3+ files, multi-file coordination, judgment/design language, has dependencies, modifies shared interfaces

This applies per-task — a plan can have a mix of annotated and unannotated tasks.

### Grouping Rules

1. Group consecutive `[batch]` tasks into batches of 2-4
2. Never exceed 4 tasks per batch (keeps combined prompt under ~60k tokens and reviewer diffs manageable)
3. **Single trailing batch task:** If a consecutive group has exactly 1 `[batch]` task, dispatch it as solo — no efficiency benefit from a 1-task batch
4. `[solo]` tasks always get their own sub-agent
5. **Dependency detection:** A task has a dependency if: (a) it references another task by number (e.g., "uses the schema from Task 2"), (b) its Files section lists a file created by a prior task, or (c) its steps reference output from a prior task. Promote dependent `[batch]` tasks to `[solo]`
6. Batches are formed from consecutive tasks only — do not reorder
7. **Token budget:** Before dispatching a batch, estimate combined prompt size. If >60k tokens, split into smaller batches

### Batch Dispatch

1. Record current HEAD as `BASE_SHA` (the commit immediately before any task in the batch) before dispatching
2. Read `./implementer-prompt.md` — use the **Multi-Task Variant** section for batched dispatch
3. Construct prompt with all batch tasks, shared context, and Library References
4. Dispatch via Agent tool with `model=sonnet`

### Parsing Implementer Report

The batched implementer returns per-task status in this format:

    - Task 1: DONE — sha: abc1234f
    - Task 2: DONE_WITH_CONCERNS — sha: d9e12345 — note: concern text
    - Task 3: BLOCKED — reason: why it failed

Parse rules:
- DONE / DONE_WITH_CONCERNS: extract the SHA, store for reviewer
- BLOCKED: no SHA — mark for re-dispatch or escalation
- **If parsing fails** (format drift, partial output): fall back to `git log --oneline -N` to extract last N commits, match by commit message. If that also fails, report parsing failure to user and skip review for unparseable tasks

### Batched Review

**BLOCKED tasks:** Do not pass to reviewers. Instead:
- Log the block reason
- Report to user: "Task {N} was blocked: {reason}. Re-dispatch as solo, or skip?"
- User decides

**Completed tasks (DONE / DONE_WITH_CONCERNS):** Two-stage review using one reviewer per stage:

**Stage 1 — Spec compliance:** dispatch `./spec-reviewer-prompt.md` with all completed task descriptions + per-task SHAs. Reviewer delivers per-task verdicts.

**Stage 2 — Code quality:** dispatch `./code-quality-reviewer-prompt.md` with combined diff (`BASE_SHA` → final commit SHA). Reviewer delivers per-task verdicts.

Verdict format:

    Task 1: PASS
    Task 2: PASS
    Task 3: ISSUES — [specific issues]

**If ISSUES found:** dispatch fix sub-agent for just the failing task(s). Re-review only the fixed task(s) — tasks that passed are NOT re-reviewed.

**Partial batch failure** (e.g., Task 1 DONE, Task 2 BLOCKED, Task 3 DONE):
- Tasks 1 and 3 proceed through normal review
- Task 2 handled via BLOCKED path
- If Task 2 is later re-dispatched and completed, it gets its own solo review pass

---

- [ ] **Step 3: Verify the insertion**

Run:
```bash
grep -n "Task Batching\|Grouping Rules\|Batch Dispatch\|Batched Review" skills/subagent-driven-development/SKILL.md
```

Expected: 4+ lines showing all major subsection headers.

- [ ] **Step 4: Verify ordering (new section is between Handling Status and Prompt Templates)**

Run:
```bash
grep -n "## Handling Implementer Status\|## Task Batching\|## Prompt Templates" skills/subagent-driven-development/SKILL.md
```

Expected: Three lines in ascending order: Handling Implementer Status < Task Batching < Prompt Templates.

- [ ] **Step 5: Verify no broken markdown (check for unmatched code fences)**

Run:
```bash
grep -c '```' skills/subagent-driven-development/SKILL.md
```

The count should be even (every opening fence has a closing fence). Note the existing count before your edit and confirm the new count is still even.

- [ ] **Step 6: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat: add task batching logic to subagent-driven-development"
```

---

### Task 3: Add multi-task variant to implementer-prompt.md [solo]

**Files:**
- Modify: `skills/subagent-driven-development/implementer-prompt.md`

- [ ] **Step 1: Read the current file and verify end state**

Read `skills/subagent-driven-development/implementer-prompt.md`. Verify the file ends with a closing ` ``` ` (the single-task template's closing fence). Run:
```bash
tail -5 skills/subagent-driven-development/implementer-prompt.md
```
Confirm the last non-empty line is ` ``` `. If the file structure differs, report and stop.

- [ ] **Step 2: Append multi-task variant**

After the closing ` ``` ` of the existing template, append the following using the Edit tool. The content uses indented code blocks (4-space indent) to avoid nested fence conflicts:

```markdown

---

# Multi-Task Variant (for batched dispatch)

Use this template when dispatching a batch of 2-4 tasks to a single implementer.

    Task tool (general-purpose):
      description: "Implement Tasks N-M: [batch summary]"
      prompt: |
        You are implementing {N} tasks sequentially. Complete each in order, commit after each.

        ## Task 1: {title}
        {FULL TEXT from plan}

        ## Task 2: {title}
        {FULL TEXT from plan}

        [... repeat for each task in batch ...]

        ## Context
        [Scene-setting, shared across all tasks]

        ## Library References (if provided by controller via Context7)
        [Controller injects current library documentation here.
        Use these as the authoritative API reference — they override
        your training data if there are differences.]

        ## Your Job

        For EACH task, in order:
        1. Implement exactly what the task specifies
        2. Write tests if required
        3. Verify implementation works
        4. Commit with a message specific to that task
        5. Self-review:
           - Completeness: Did I implement everything? Miss any requirements? Edge cases?
           - Quality: Clean, maintainable code? Clear naming?
           - Discipline: YAGNI? Only what was requested? Following existing patterns?
           - Testing: Tests verify behavior? Comprehensive?

        If you get BLOCKED on a task due to an external blocker (missing tool,
        failed command, permission error), skip it and continue with the next task.
        All tasks in a batch are independent — a block on one does not affect the others.

        ## Report Format

        After ALL tasks are done, report back with per-task status using this
        EXACT format (controller parses this to extract SHAs for reviewers):

        - Task 1: DONE — sha: {commit_sha}
        - Task 2: DONE_WITH_CONCERNS — sha: {commit_sha} — note: {concern}
        - Task 3: BLOCKED — reason: {why}

        Rules:
        - DONE tasks MUST include the commit sha
        - DONE_WITH_CONCERNS tasks MUST include sha AND note
        - BLOCKED tasks have no sha — include reason
        - Also include: files changed per task, test results per task, self-review findings
```

Note: The "Before You Begin" question-asking block is intentionally omitted from the multi-task variant. Batched dispatch is automated — the implementer has no channel to ask questions back. All context must be provided upfront in the prompt.

- [ ] **Step 3: Verify**

Run:
```bash
grep -n "Multi-Task Variant\|batched dispatch\|EXACT format" skills/subagent-driven-development/implementer-prompt.md
```

Expected: Multiple lines showing the new variant section.

- [ ] **Step 4: Commit**

```bash
git add skills/subagent-driven-development/implementer-prompt.md
git commit -m "feat: add multi-task variant to implementer prompt template"
```

---

### Task 4: End-to-end verification [solo]

**Files:**
- Read: all 3 modified files

**If any verification step returns unexpected results, STOP and report which check failed and the actual output. Do NOT proceed.**

- [ ] **Step 1: Verify writing-plans has annotation instruction**

Run:
```bash
grep -En "\[batch\]|\[solo\]" skills/writing-plans/SKILL.md | wc -l
```

Expected: 4+ lines. These come from: (1) task heading template `[batch|solo]`, (2) section title `[batch] / [solo]`, (3) `[batch]` signals heading, (4) `[solo]` signals heading.

- [ ] **Step 2: Verify SDD has all batching subsections**

Run:
```bash
grep -n "## Task Batching\|### Reading Annotations\|### Grouping Rules\|### Batch Dispatch\|### Parsing Implementer Report\|### Batched Review" skills/subagent-driven-development/SKILL.md
```

Expected: 6 lines, all in ascending line-number order.

- [ ] **Step 3: Verify implementer-prompt has multi-task variant**

Run:
```bash
grep -n "Multi-Task Variant\|EXACT format" skills/subagent-driven-development/implementer-prompt.md
```

Expected: Both present.

- [ ] **Step 4: Verify dependency detection is specified**

Run:
```bash
grep -c "dependency\|Dependency" skills/subagent-driven-development/SKILL.md
```

Expected: 2+ occurrences.

- [ ] **Step 5: Verify token budget ceiling is specified**

Run:
```bash
grep "60k" skills/subagent-driven-development/SKILL.md
```

Expected: At least 1 line mentioning the 60k token budget.

- [ ] **Step 6: Verify BASE_SHA is defined**

Run:
```bash
grep "BASE_SHA" skills/subagent-driven-development/SKILL.md
```

Expected: At least 1 line.

- [ ] **Step 7: Verify self-review checklist is inline in multi-task variant (not cross-referenced)**

Run:
```bash
grep -A5 "Self-review" skills/subagent-driven-development/implementer-prompt.md | grep "Completeness\|Quality\|Discipline\|Testing"
```

Expected: All 4 checklist items present inline.

- [ ] **Step 8: Verify "Before You Begin" is NOT in multi-task variant**

Run:
```bash
grep -c "Before You Begin" skills/subagent-driven-development/implementer-prompt.md
```

Expected: Exactly 1 (from the single-task template only, not from the multi-task variant).

- [ ] **Step 9: Verify git history**

Run:
```bash
git log --oneline -5
```

Expected: 3 new commits for tasks 1-3.
