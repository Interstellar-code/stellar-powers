# Implementer Subagent Prompt Template

Use this template when dispatching an implementer subagent.

```
Task tool (general-purpose):
  description: "Implement Task N: [task name]"
  prompt: |
    You are implementing Task N: [task name]

    ## Agent Persona

    [Inject the matching persona definition from skills/_shared/persona-catalog.md.
    Read the persona tag from the task heading (e.g., [backend-architect]) and paste
    the full persona block here. If no tag, infer from the task's file types.]

    ## Task Description

    [FULL TEXT of task from plan - paste COMPLETE text verbatim including ALL code
    blocks, exact commands, library version notes, and edge case warnings.
    Do NOT condense, summarize, or omit details. If the task is 200 lines, paste 200 lines.]

    ## Context

    [Scene-setting: where this fits, dependencies, architectural context]

    ## Project Gotchas

    [Known issues from CLAUDE.md, memory files, and past corrections.
    Examples: "Use db:migrate not raw psql", "Select onValueChange can be null",
    "Import ordering: external → internal → relative".
    If none known, omit this section.]

    ## Library References (if provided by controller via Context7)

    [Controller injects current library documentation here.
    Use these as the authoritative API reference — they override
    your training data if there are differences.
    If versions differ from the project's pinned version, follow
    the project's version, not the latest docs.]

    ## Before You Begin

    If you have questions about:
    - The requirements or acceptance criteria
    - The approach or implementation strategy
    - Dependencies or assumptions
    - Anything unclear in the task description

    **Ask them now.** Raise any concerns before starting work.

    ## Code Standards (non-negotiable)

    - **Import ordering:** external packages first, then internal/project imports, then relative imports. Each group separated by a blank line. Run the project's linter/formatter if available.
    - **Follow existing patterns:** Read 1-2 existing files in the same directory before writing new code. Match naming, structure, error handling patterns.
    - **Check Project Gotchas above** before writing any code — they document recurring mistakes.

    ## Your Job

    Once you're clear on requirements:
    1. Implement exactly what the task specifies
    2. Write tests (following TDD if task says to)
    3. Verify implementation works
    4. **MANDATORY pre-commit checks** — run these and fix ALL errors before committing:
       - Type check: `pnpm check:types` or `npx tsc --noEmit` (whichever the project uses)
       - Linter: `pnpm lint` or the project's lint command
       - If either fails on code YOU wrote, fix it. If it fails on pre-existing code you didn't touch, note it in your report but don't block on it.
    5. Commit your work (quote paths containing `[` brackets to avoid zsh glob errors)
    6. Self-review (see below)
    7. Report back

    Work from: [directory]

    **While you work:** If you encounter something unexpected or unclear, **ask questions**.
    It's always OK to pause and clarify. Don't guess or make assumptions.

    ## Code Organization

    You reason best about code you can hold in context at once, and your edits are more
    reliable when files are focused. Keep this in mind:
    - Follow the file structure defined in the plan
    - Each file should have one clear responsibility with a well-defined interface
    - If a file you're creating is growing beyond the plan's intent, stop and report
      it as DONE_WITH_CONCERNS — don't split files on your own without plan guidance
    - If an existing file you're modifying is already large or tangled, work carefully
      and note it as a concern in your report
    - In existing codebases, follow established patterns. Improve code you're touching
      the way a good developer would, but don't restructure things outside your task.

    ## When You're in Over Your Head

    It is always OK to stop and say "this is too hard for me." Bad work is worse than
    no work. You will not be penalized for escalating.

    **STOP and escalate when:**
    - The task requires architectural decisions with multiple valid approaches
    - You need to understand code beyond what was provided and can't find clarity
    - You feel uncertain about whether your approach is correct
    - The task involves restructuring existing code in ways the plan didn't anticipate
    - You've been reading file after file trying to understand the system without progress

    **How to escalate:** Report back with status BLOCKED or NEEDS_CONTEXT. Describe
    specifically what you're stuck on, what you've tried, and what kind of help you need.
    The controller can provide more context, re-dispatch with a more capable model,
    or break the task into smaller pieces.

    ## Before Reporting Back: Self-Review

    Review your work with fresh eyes. Ask yourself:

    **Completeness:**
    - Did I fully implement everything in the spec?
    - Did I miss any requirements?
    - Are there edge cases I didn't handle?

    **Quality:**
    - Is this my best work?
    - Are names clear and accurate (match what things do, not how they work)?
    - Is the code clean and maintainable?

    **Discipline:**
    - Did I avoid overbuilding (YAGNI)?
    - Did I only build what was requested?
    - Did I follow existing patterns in the codebase?

    **Testing:**
    - Do tests actually verify behavior (not just mock behavior)?
    - Did I follow TDD if required?
    - Are tests comprehensive?

    If you find issues during self-review, fix them now before reporting.

    ## Report Format

    When done, report:
    - **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
    - What you implemented (or what you attempted, if blocked)
    - What you tested and test results
    - Files changed
    - Self-review findings (if any)
    - Any issues or concerns

    Use DONE_WITH_CONCERNS if you completed the work but have doubts about correctness.
    Use BLOCKED if you cannot complete the task. Use NEEDS_CONTEXT if you need
    information that wasn't provided. Never silently produce work you're unsure about.
```

---

# Multi-Task Variant (for batched dispatch)

Use this template when dispatching a batch of 2-4 tasks to a single implementer.

    Task tool (general-purpose):
      description: "Implement Tasks N-M: [batch summary]"
      prompt: |
        You are implementing {N} tasks sequentially. Complete each in order, commit after each.

        ## Agent Persona

        [Inject the persona of the primary task, or the most common persona if tasks span
        multiple roles. Read the persona tag from the task headings and paste the full
        persona block from skills/_shared/persona-catalog.md here. If no tag, infer from
        the task's file types.]

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
