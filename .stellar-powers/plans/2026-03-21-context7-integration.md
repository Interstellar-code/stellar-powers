# Context7 Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use stellar-powers:subagent-driven-development (recommended) or stellar-powers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Embed Context7 library documentation lookups into 6 existing Stellar Powers skill files to prevent LLMs from using outdated/deprecated APIs during planning, implementation, and review.

**Architecture:** No new files — each task adds a Context7 integration paragraph and/or code block to an existing skill file. All use the same canonical curl+python3 fetch pattern with `--max-time 10` and `tokens=5000`. Graceful degradation when API key is missing or library not found.

**Tech Stack:** curl, python3 (for JSON parsing), Context7 REST API v2

**Spec:** `.stellar-powers/specs/2026-03-21-context7-integration-design.md`

**Important — QUERY derivation:** In every curl command, `QUERY` should be set to the specific API topic relevant to the task — e.g., `"webhooks"` for a Stripe webhook task, `"app router"` for a Next.js routing task, `"useEffect"` for a React hooks task. Never use just the library name as the query. Derive it from the task title, the primary file being modified, or the specific API method being used.

**Important — failure handling:** If any verification step returns unexpected results, STOP, report which check failed and the actual output, and do NOT proceed. Do not commit until all checks pass.

---

## File Structure

| Action | File | Change |
|---|---|---|
| Modify | `skills/writing-plans/SKILL.md` | Add Context7 lookup step after Plan Document Header section |
| Modify | `skills/brainstorming/SKILL.md` | Add library verification in "Exploring approaches" section |
| Modify | `skills/subagent-driven-development/SKILL.md` | Add Context7 enrichment instruction before dispatch |
| Modify | `skills/subagent-driven-development/implementer-prompt.md` | Add `## Library References` optional section |
| Modify | `skills/requesting-code-review/code-reviewer.md` | Add API Currency checklist item |
| Modify | `skills/feature-porting/scanner-prompt.md` | Add Phase 4.5 API Currency Check |

---

### Task 1: Add Context7 lookup to writing-plans

The highest-priority integration. Plan code blocks are copy-pasted into implementer prompts — stale APIs here propagate everywhere.

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

- [ ] **Step 1: Read the current file**

Read `skills/writing-plans/SKILL.md` to confirm the current structure. Locate the "Plan Document Header" section (around line 63) and the "Task Structure" section that follows it (around line 81).

- [ ] **Step 2: Insert Context7 verification step**

After the "Plan Document Header" section (after the closing ` ``` ` of the header template, before `## Task Structure`), insert this new section:

```markdown
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
```

- [ ] **Step 3: Verify the insertion**

Run:
```bash
grep -n "Context7\|context7" skills/writing-plans/SKILL.md
```

Expected: Multiple lines showing the new section.

- [ ] **Step 4: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "feat: add Context7 library doc verification to writing-plans skill"
```

---

### Task 2: Add Context7 lookup to brainstorming

Verify library API assumptions when proposing approaches. Spec appendix is conditional on whether a spec is produced.

**Files:**
- Modify: `skills/brainstorming/SKILL.md`

- [ ] **Step 1: Read the current file**

Read `skills/brainstorming/SKILL.md`. Locate the "Exploring approaches" section (around line 99). The last bullet is "Lead with your recommended option and explain why" (around line 103).

- [ ] **Step 2: Insert library verification after "Exploring approaches"**

After the line `- Lead with your recommended option and explain why`, insert:

```markdown

**Library verification (Context7):**

- When proposing approaches that recommend specific libraries, fetch current docs via Context7 to verify API assumptions. Set `QUERY` to the specific API topic (e.g., `"app router"` not just `"nextjs"`):
  ```bash
  LIB_ID=$(curl -s --max-time 10 "https://context7.com/api/v2/libs/search?libraryName=${LIBRARY}" \
    -H "Authorization: Bearer $CONTEXT7_API_KEY" \
    | python3 -c "import sys,json; r=json.load(sys.stdin).get('results',[]); print(max(r, key=lambda x: x.get('trustScore',0))['id'] if r else '')" 2>/dev/null)
  if [ -n "$LIB_ID" ]; then
    curl -s --max-time 10 "https://context7.com/api/v2/context?libraryId=${LIB_ID}&query=${QUERY}&tokens=5000&type=txt" \
      -H "Authorization: Bearer $CONTEXT7_API_KEY" 2>/dev/null
  fi
  ```
- Include version info in the approach (e.g., "Next.js 15 — App Router with Server Components")
- Check the project's pinned version matches — don't recommend patterns from a newer major version than the project uses
- If a proposed pattern is deprecated, note it in the trade-offs and use the current pattern
- If this brainstorming session results in a spec document, include a `## Library References` appendix (max ~200 tokens per library, 3-5 key patterns)
- Skip utility libs (lodash, zod) and private `@org/` packages
- If `CONTEXT7_API_KEY` is not set, proceed without verification — note this once
```

- [ ] **Step 3: Verify the insertion**

Run:
```bash
grep -n "Context7\|context7" skills/brainstorming/SKILL.md
```

Expected: Multiple lines showing the new section in the "Exploring approaches" area.

- [ ] **Step 4: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "feat: add Context7 library verification to brainstorming skill"
```

---

### Task 3: Add Context7 enrichment to subagent-driven-development

Inject current library docs into implementer subagent prompts.

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`
- Modify: `skills/subagent-driven-development/implementer-prompt.md`

- [ ] **Step 1: Read both files**

Read `skills/subagent-driven-development/SKILL.md` — locate the "Prompt Templates" section (which describes how to dispatch implementer subagents).

Read `skills/subagent-driven-development/implementer-prompt.md` — locate the `## Context` section (around line 16) and the `## Your Job` section that follows (around line 29). Note the indentation used — the template content is indented with 4 spaces.

- [ ] **Step 2: Add enrichment instruction to SKILL.md**

In the "Prompt Templates" section, after the line about reading `./implementer-prompt.md`, add:

```markdown

**Context7 enrichment:** Before dispatching each implementer, identify which libraries the task touches (from the plan's Tech Stack and the task's file list — max 3 per task, skip utility libs and private `@org/` packages). Set `QUERY` to the specific API topic the task covers (e.g., `"webhooks"` for a Stripe webhook handler, not `"stripe"`). Check the project's pinned version and note any major version mismatch. Fetch current docs via Context7:

```bash
LIB_ID=$(curl -s --max-time 10 "https://context7.com/api/v2/libs/search?libraryName=${LIBRARY}" \
  -H "Authorization: Bearer $CONTEXT7_API_KEY" \
  | python3 -c "import sys,json; r=json.load(sys.stdin).get('results',[]); print(max(r, key=lambda x: x.get('trustScore',0))['id'] if r else '')" 2>/dev/null)
if [ -n "$LIB_ID" ]; then
  curl -s --max-time 10 "https://context7.com/api/v2/context?libraryId=${LIB_ID}&query=${QUERY}&tokens=5000&type=txt" \
    -H "Authorization: Bearer $CONTEXT7_API_KEY" 2>/dev/null
fi
```

Inject the fetched docs into the `## Library References` section of the implementer prompt. If `CONTEXT7_API_KEY` is not set, skip this step silently.
```

- [ ] **Step 3: Add Library References section to implementer-prompt.md**

After the `## Context` section and before `## Your Job`, insert the following. Match the indentation of the existing `## Context` section header (4 spaces):

```
    ## Library References (if provided by controller via Context7)

    [Controller injects current library documentation here.
    Use these as the authoritative API reference — they override
    your training data if there are differences.
    If versions differ from the project's pinned version, follow
    the project's version, not the latest docs.]
```

- [ ] **Step 4: Verify both insertions**

Run:
```bash
grep -n "Context7\|Library References" skills/subagent-driven-development/SKILL.md skills/subagent-driven-development/implementer-prompt.md
```

Expected: "Context7" in SKILL.md, "Library References" and "Context7" in both files.

- [ ] **Step 5: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md skills/subagent-driven-development/implementer-prompt.md
git commit -m "feat: add Context7 enrichment to subagent-driven-development"
```

---

### Task 4: Add API currency check to code reviewer

Make library API verification a non-optional part of code review.

**Files:**
- Modify: `skills/requesting-code-review/code-reviewer.md`

- [ ] **Step 1: Read the current file**

Read `skills/requesting-code-review/code-reviewer.md`. Locate the "Supporting Lenses" section (around line 27) which lists additional review perspectives as bullet points starting with `- **Security Engineer:**`. Confirm this is where review lenses are listed before inserting.

- [ ] **Step 2: Add API Currency lens**

After the last existing supporting lens bullet (e.g., after the Security Engineer line), add:

```markdown
- **API Currency (Context7):** For every external library appearing in the diff, fetch Context7 docs to verify API usage is current (if `CONTEXT7_API_KEY` is set). This is not optional — check proactively, not just when uncertain. Set `QUERY` to the specific method or API pattern being reviewed:
  ```bash
  LIB_ID=$(curl -s --max-time 10 "https://context7.com/api/v2/libs/search?libraryName=${LIBRARY}" \
    -H "Authorization: Bearer $CONTEXT7_API_KEY" \
    | python3 -c "import sys,json; r=json.load(sys.stdin).get('results',[]); print(max(r, key=lambda x: x.get('trustScore',0))['id'] if r else '')" 2>/dev/null)
  if [ -n "$LIB_ID" ]; then
    curl -s --max-time 10 "https://context7.com/api/v2/context?libraryId=${LIB_ID}&query=${METHOD_OR_API}&tokens=5000&type=txt" \
      -H "Authorization: Bearer $CONTEXT7_API_KEY" 2>/dev/null
  fi
  ```
  Skip private `@org/` scoped packages and utility libraries without version-sensitive APIs. Flag deprecated API usage as Critical (Must Fix) if a non-deprecated replacement exists in the same major version. If `CONTEXT7_API_KEY` is not set, note "API currency not verified — Context7 key not configured" and proceed.
```

- [ ] **Step 3: Verify the insertion**

Run:
```bash
grep -n "Context7\|API Currency" skills/requesting-code-review/code-reviewer.md
```

Expected: Multiple lines showing the new lens.

- [ ] **Step 4: Commit**

```bash
git add skills/requesting-code-review/code-reviewer.md
git commit -m "feat: add Context7 API currency check to code reviewer"
```

---

### Task 5: Add Phase 4.5 to feature-porting scanner

Check source library patterns against current docs during feature extraction.

**Files:**
- Modify: `skills/feature-porting/scanner-prompt.md`

- [ ] **Step 1: Read the current file**

Read `skills/feature-porting/scanner-prompt.md`. Locate Phase 4 "Produce Mapping" (around line 112) and Phase 5 "Save Report" (around line 138).

- [ ] **Step 2: Insert Phase 4.5 between Phase 4 and Phase 5**

Before the line `## Phase 5: Save Report`, insert:

```markdown
## Phase 4.5: API Currency Check (Context7)

For key source libraries identified in the Source Stack Summary (auth, payments, ORM, state management — max 5, skip utility libs and private `@org/` packages), check whether the patterns extracted in Phase 2 reflect current API conventions. Set `QUERY` to the specific pattern or method being checked:

```bash
LIB_ID=$(curl -s --max-time 10 "https://context7.com/api/v2/libs/search?libraryName=${LIBRARY}" \
  -H "Authorization: Bearer $CONTEXT7_API_KEY" \
  | python3 -c "import sys,json; r=json.load(sys.stdin).get('results',[]); print(max(r, key=lambda x: x.get('trustScore',0))['id'] if r else '')" 2>/dev/null)

if [ -n "$LIB_ID" ]; then
  curl -s --max-time 10 "https://context7.com/api/v2/context?libraryId=${LIB_ID}&query=${QUERY}&tokens=5000&type=txt" \
    -H "Authorization: Bearer $CONTEXT7_API_KEY" 2>/dev/null
fi
```

If source patterns are deprecated according to current docs, add `Port Risk: Stale API` to the Adaptation Notes column of the mapping table with a note: "Source uses {old pattern}, current docs show {new pattern}."

If `CONTEXT7_API_KEY` is not set, skip this phase entirely.

```

- [ ] **Step 3: Verify the insertion**

Run:
```bash
grep -n "Phase 4.5\|Context7\|API Currency" skills/feature-porting/scanner-prompt.md
```

Expected: Phase 4.5 header and Context7 references between Phase 4 and Phase 5.

- [ ] **Step 4: Commit**

```bash
git add skills/feature-porting/scanner-prompt.md
git commit -m "feat: add Context7 API currency check to feature-porting scanner"
```

---

### Task 6: End-to-end verification

Verify all 6 files have Context7 integration and the pattern is consistent.

**If any verification step returns unexpected results, STOP and report which check failed and the actual output. Do NOT proceed or commit.**

**Files:**
- Read: all 6 modified files

- [ ] **Step 1: Verify Context7 or Library References in all 6 files**

Run:
```bash
grep -l "Context7\|context7\|Library References" \
  skills/writing-plans/SKILL.md \
  skills/brainstorming/SKILL.md \
  skills/subagent-driven-development/SKILL.md \
  skills/subagent-driven-development/implementer-prompt.md \
  skills/requesting-code-review/code-reviewer.md \
  skills/feature-porting/scanner-prompt.md
```

Expected: All 6 files listed. Note: `implementer-prompt.md` matches on "Library References" and "Context7" (both present in the inserted text), not on curl commands.

- [ ] **Step 2: Verify `--max-time 10` in all 5 files with curl commands**

Run:
```bash
grep -c "max-time 10" \
  skills/writing-plans/SKILL.md \
  skills/brainstorming/SKILL.md \
  skills/subagent-driven-development/SKILL.md \
  skills/requesting-code-review/code-reviewer.md \
  skills/feature-porting/scanner-prompt.md
```

Expected: At least 1 occurrence in each file. (`implementer-prompt.md` is excluded — it contains no curl command, only the injected output placeholder.)

- [ ] **Step 3: Verify `tokens=5000` in all 5 files with curl commands**

Run:
```bash
grep -c "tokens=5000" \
  skills/writing-plans/SKILL.md \
  skills/brainstorming/SKILL.md \
  skills/subagent-driven-development/SKILL.md \
  skills/requesting-code-review/code-reviewer.md \
  skills/feature-porting/scanner-prompt.md
```

Expected: At least 1 occurrence in each file.

- [ ] **Step 4: Verify trustScore selection (not r[0])**

Run:
```bash
grep -c "trustScore" \
  skills/writing-plans/SKILL.md \
  skills/brainstorming/SKILL.md \
  skills/subagent-driven-development/SKILL.md \
  skills/requesting-code-review/code-reviewer.md \
  skills/feature-porting/scanner-prompt.md
```

Expected: At least 1 occurrence in each file.

- [ ] **Step 5: Verify graceful degradation**

Run:
```bash
grep -c "CONTEXT7_API_KEY" \
  skills/writing-plans/SKILL.md \
  skills/brainstorming/SKILL.md \
  skills/subagent-driven-development/SKILL.md \
  skills/requesting-code-review/code-reviewer.md \
  skills/feature-porting/scanner-prompt.md
```

Expected: 2+ occurrences in each file (at least once in curl, once in degradation note).

- [ ] **Step 6: Verify no `r[0]` usage (ensure trustScore is used consistently)**

Run:
```bash
grep -n "r\[0\]" \
  skills/writing-plans/SKILL.md \
  skills/brainstorming/SKILL.md \
  skills/subagent-driven-development/SKILL.md \
  skills/requesting-code-review/code-reviewer.md \
  skills/feature-porting/scanner-prompt.md || echo "PASS: no r[0] found"
```

Expected: "PASS: no r[0] found"

- [ ] **Step 7: Verify git history**

Run:
```bash
git log --oneline -7
```

Expected: 5 new commits (one per task 1-5).
