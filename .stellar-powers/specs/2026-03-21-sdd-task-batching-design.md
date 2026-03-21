# Design Spec: SDD Task Batching Heuristic

**Date:** 2026-03-21
**Workflow ID:** 1D06F239-1DCE-47EA-95F3-0E1BE86FB99D
**Status:** Draft

---

## Overview

Add task batching to the subagent-driven-development (SDD) skill so that small mechanical tasks are grouped and dispatched to a single sub-agent instead of one agent per task. Writing-plans emits `[batch]` / `[solo]` annotations on each task. SDD uses annotations when present, falls back to a heuristic when not.

## Problem

SDD currently dispatches one fresh sub-agent per task with two-stage review after each. For small mechanical tasks (10-20k tokens, 1-2 files, 4-6 tool uses), the dispatch + review overhead is disproportionate. A plan with 8 small tasks produces 8 implementer dispatches + 16 reviewer dispatches = 24 sub-agent invocations, when 3-4 batched dispatches + 6-8 reviewer dispatches would produce the same quality output.

## Solution

A hybrid approach: writing-plans annotates tasks with `[batch]` or `[solo]` based on complexity signals. SDD reads these annotations and groups consecutive `[batch]` tasks into batches of 2-4 per sub-agent. When annotations are absent (old plans), SDD falls back to the same complexity signals as a heuristic.

---

## Task Complexity Signals

Used by both writing-plans (to annotate) and SDD (as fallback heuristic). These are the same thresholds in both contexts — if ANY solo signal is present, the task is `[solo]`:

**Batch signals (ALL must be true):**
- Touches 1-2 files
- Steps are mechanical (write file, run command, commit)
- No integration concerns across other tasks
- No "judgment", "architecture", or "design decision" language in description
- Task is independent (no dependencies on other tasks)

**Solo signals (ANY one triggers solo):**
- Touches 3+ files
- Requires multi-file coordination or integration
- Contains judgment/design language
- Has dependencies on other tasks
- Modifies shared interfaces or schemas

---

## Writing-Plans: Annotation Format

Writing-plans assesses each task against the complexity signals above and adds an annotation to the task heading:

```markdown
### Task 1: Install dependencies [batch]
### Task 2: Add i18n keys [batch]
### Task 3: Design API contract [solo]
### Task 4: Create schema migration [batch]
```

The `[batch]` / `[solo]` tag appears at the end of the task heading line. The user can change annotations during plan review before execution begins.

---

## SDD: Batching Logic

When the controller reads the plan and extracts all tasks:

1. Read all tasks, note their `[batch]` / `[solo]` annotations
2. **Fallback for unannotated tasks:** If a task has no `[batch]` or `[solo]` annotation, apply the complexity signals from the "Task Complexity Signals" section above to classify it. This applies per-task, not per-plan — a plan can have a mix of annotated and unannotated tasks
3. Group consecutive `[batch]` tasks into batches of 2-4. Never exceed 4 tasks per batch (rationale: keeps combined prompt under ~80k tokens and reviewer diffs reviewable — 4 small tasks is the practical ceiling before cognitive load degrades review quality)
4. **Single trailing batch task:** If a consecutive group has exactly 1 `[batch]` task (e.g., a lone `[batch]` between two `[solo]` tasks), dispatch it as solo — a 1-task batch has no efficiency benefit
5. Tasks marked `[solo]` always get their own sub-agent
6. **Dependency detection:** A task has a dependency if: (a) it explicitly references another task by number in its description (e.g., "uses the schema from Task 2"), (b) its `Files:` section lists a file created by a prior task in the same plan, or (c) its steps reference output from a prior task. If a `[batch]` task has a detected dependency, promote it to `[solo]`
7. Batches are formed from consecutive tasks only — do not reorder tasks to create batches
8. **Token budget check:** Before dispatching a batch, estimate the combined prompt size (all task texts + context + library references). If estimated >60k tokens, split the batch into smaller groups. Never dispatch a batch prompt that would exceed 60k tokens

**Example grouping:**
```
Task 1: Install deps [batch]        ─┐
Task 2: Add i18n keys [batch]        ├─ Batch A (3 tasks → 1 agent)
Task 3: Create schema [batch]       ─┘
Task 4: Design API contract [solo]  ─── Solo (1 agent)
Task 5: Add sidebar nav [batch]     ─┐
Task 6: Add route config [batch]     ├─ Batch B (2 tasks → 1 agent)
Task 7: Add logout button [batch]   ─── Solo (only 1 consecutive batch task)
```

Result: 4 sub-agent dispatches instead of 7.

---

## Batched Sub-Agent Prompt

When dispatching a batch, the controller records the current HEAD as `BASE_SHA` (the commit before any task in the batch), then constructs a combined prompt using the `implementer-prompt.md` template with all tasks included:

```
You are implementing {N} tasks sequentially. Complete each in order, commit after each.

## Task 1: {title}
{FULL TEXT from plan}

## Task 2: {title}
{FULL TEXT from plan}

## Task 3: {title}
{FULL TEXT from plan}

## Context
{Scene-setting, shared across all tasks}

## Library References (if provided by controller via Context7)
{Injected docs}

## Your Job

For EACH task, in order:
1. Implement exactly what the task specifies
2. Write tests if required
3. Verify implementation works
4. Commit with a message specific to that task
5. Self-review

After ALL tasks are done, report back with per-task status using this EXACT format (controller parses this to extract SHAs for reviewers):

- Task 1: DONE — sha: abc1234f
- Task 2: DONE_WITH_CONCERNS — sha: d9e12345 — note: skipped edge case test
- Task 3: BLOCKED — reason: migration tool not installed

Rules:
- DONE tasks MUST include the commit sha
- DONE_WITH_CONCERNS tasks MUST include sha AND note
- BLOCKED tasks have no sha (nothing was committed) — include reason
- If you get BLOCKED on a task due to an external blocker (missing tool, failed command, permission error), skip it and continue with the next task. All tasks in a batch are independent — a block on one does not affect the others.
```

Key properties:
- Per-task commits preserve git granularity (same as solo dispatch)
- If Task 2 fails, Task 1 is already committed and safe
- BLOCKED on one task doesn't stop the others (all batch tasks are independent by construction)

---

## Controller SHA Parsing

After the implementer returns, the controller parses the per-task status lines:

1. Extract lines matching `Task N: STATUS — sha: HASH` pattern
2. For DONE / DONE_WITH_CONCERNS: extract the SHA and store it for the reviewer
3. For BLOCKED: no SHA to extract — mark task as needing re-dispatch or escalation
4. **If parsing fails** (implementer drifted from format, partial output, missing lines): fall back to `git log --oneline -N` to extract the last N commits, match them to tasks by commit message. If that also fails, report the parsing failure to the user and skip review for the unparseable tasks

---

## Batched Review

After the batched sub-agent completes, the controller handles BLOCKED tasks first, then reviews completed tasks:

**BLOCKED tasks:** Do not pass to reviewers (no commit to review). Instead:
- Log the block reason
- Report to user: "Task {N} was blocked: {reason}. Should I re-dispatch as solo, or skip?"
- User decides: re-dispatch solo, or defer

**Completed tasks (DONE / DONE_WITH_CONCERNS):** Two-stage review using one reviewer per stage:

**Stage 1 — Spec compliance reviewer:**
- Receives all completed task descriptions from the plan
- Receives per-task commit SHAs from the implementer's report
- Reviews each task's commit against its spec
- Delivers per-task verdict

**Stage 2 — Code quality reviewer:**
- Receives combined diff (`BASE_SHA` → final commit SHA, where `BASE_SHA` is the HEAD recorded before batch dispatch)
- Receives per-task breakdown
- Delivers per-task verdict

**Verdict format:**
```
Task 1: PASS
Task 2: PASS
Task 3: ISSUES — [specific issues]
```

**If any completed task has ISSUES:**
- Controller dispatches a fix sub-agent for just the failing task(s)
- Re-dispatches the reviewer for just the fixed task(s) — not the whole batch
- Tasks that passed are NOT re-reviewed

**Partial batch failure (e.g., Task 1 DONE, Task 2 BLOCKED, Task 3 DONE):**
- Tasks 1 and 3 proceed through normal review
- Task 2 is handled via the BLOCKED path above
- If Task 2 is re-dispatched and completed later, it gets its own solo review pass

---

## Files to Modify

| File | Change | Priority |
|---|---|---|
| `skills/subagent-driven-development/SKILL.md` | Add batching section: complexity signals, grouping rules (including dependency detection, token budget, single-task promotion), batch dispatch flow, SHA parsing, batched review flow | HIGH |
| `skills/subagent-driven-development/implementer-prompt.md` | Add multi-task variant with exact per-task report format | HIGH |
| `skills/writing-plans/SKILL.md` | Add `[batch]` / `[solo]` annotation instruction to Task Structure section, using the same complexity signals | HIGH |

**3 files modified, 0 files created.**

---

## Definition of Done

SDD produces fewer sub-agent dispatches for plans with consecutive batch tasks while maintaining:
- Per-task commit granularity
- Per-task review coverage (spec + quality)
- Clean handling of BLOCKED tasks within batches
- Backwards compatibility with unannotated plans (heuristic fallback)

---

## What This Does NOT Do

- Does not change solo dispatch behavior (solo tasks work exactly as before)
- Does not reorder tasks to optimize batching (consecutive only)
- Does not batch tasks with detected dependencies (auto-promoted to solo)
- Does not exceed 4 tasks per batch or 60k token budget
- Does not dispatch 1-task batches (promoted to solo)
- Does not change the review quality (per-task verdicts maintained)
- Does not require old plans to be re-written (per-task heuristic fallback handles mixed plans)
- Does not pass BLOCKED tasks to reviewers (handled separately)
