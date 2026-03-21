# Design Spec: Context7 Library Documentation Integration

**Date:** 2026-03-21
**Workflow ID:** E568960D-7B02-4452-9E78-04909AE9008F
**Status:** Draft

---

## Overview

Embed Context7 library documentation lookups into existing Stellar Powers skills to prevent LLMs from using outdated or deprecated APIs during planning, implementation, and review. Integration via REST API (`curl`), not MCP. No new files — modifications to 6 existing skill files.

## Problem

LLMs hallucinate deprecated APIs because their training data is stale. When a plan contains inline code examples with outdated patterns, every downstream subagent inherits those patterns as authoritative instructions. The spec reviewer checks "does code match spec?" but not "is the spec's API current?" — stale patterns propagate unchecked through the entire skill chain.

## Solution

Add automatic Context7 documentation lookups at key decision points in the skill chain. Fetched docs are used to verify API assumptions and embedded as a `## Library References` appendix in specs/plans so downstream subagents have current documentation without needing to re-fetch.

---

## Context7 API

**Two-step flow:**

Step 1 — Resolve library ID:
```bash
curl -s --max-time 10 "https://context7.com/api/v2/libs/search?libraryName=${LIBRARY}" \
  -H "Authorization: Bearer $CONTEXT7_API_KEY"
```
Returns JSON with `results[].id` (e.g., `/vercel/next.js`), `title`, `trustScore`, `versions`.

Step 2 — Fetch docs for a specific topic:
```bash
curl -s --max-time 10 "https://context7.com/api/v2/context?libraryId=${LIB_ID}&query=${QUERY}&tokens=5000&type=txt" \
  -H "Authorization: Bearer $CONTEXT7_API_KEY"
```
Returns clean markdown with code examples — ideal for prompt injection. The `tokens=5000` parameter caps response size to prevent context window blowout.

**Library ID selection:** Select the result with the highest `trustScore`. The inline pattern uses `max(r, key=trustScore)` to ensure the most authoritative source is used.

**Query string heuristic:** Use the task title, the primary file being modified, or the specific API method being used as the query string. For example, for a task about implementing Stripe webhooks, use `QUERY="webhooks"` not `QUERY="stripe"`.

**Lookup limits:** Limit lookups to the top 3-5 libraries most central to the task. Skip utility/non-API libraries that don't have version-sensitive APIs (e.g., `lodash`, `zod`, `uuid`). Skip packages with `@org/` private scopes — Context7 only indexes public libraries.

**Version awareness:** After fetching docs, check if the project's pinned version (from `package.json` or lock file) matches the docs version. If there's a major version mismatch (e.g., project uses Next.js 13 but docs are for Next.js 15), note the discrepancy and use docs conservatively — don't "correct" patterns to a version the project doesn't use.

**Canonical inline fetch pattern:**
```bash
LIB_ID=$(curl -s --max-time 10 "https://context7.com/api/v2/libs/search?libraryName=${LIBRARY}" \
  -H "Authorization: Bearer $CONTEXT7_API_KEY" \
  | python3 -c "import sys,json; r=json.load(sys.stdin).get('results',[]); print(max(r, key=lambda x: x.get('trustScore',0))['id'] if r else '')" 2>/dev/null)

if [ -n "$LIB_ID" ]; then
  DOCS=$(curl -s --max-time 10 "https://context7.com/api/v2/context?libraryId=${LIB_ID}&query=${QUERY}&tokens=5000&type=txt" \
    -H "Authorization: Bearer $CONTEXT7_API_KEY" 2>/dev/null)
fi
```

All curl calls include `--max-time 10` to prevent hanging on unreachable APIs.

**Prerequisites:** Free API key from context7.com/dashboard, stored as `CONTEXT7_API_KEY` env var.

---

## Integration Points

### 1. writing-plans/SKILL.md (HIGH priority)

**Where:** After populating the `Tech Stack` plan header, before writing task code blocks.

**What to add:**

After the plan header is written (Goal, Architecture, Tech Stack), add a step:

> **Library doc verification:** For the top 3-5 libraries listed in the Tech Stack header (skip utility libs like lodash/zod and private `@org/` packages), fetch current documentation via Context7 using the canonical fetch pattern. Check that the project's pinned version matches the docs version — note any major version mismatches.
>
> Use the fetched docs to verify API patterns before writing inline code examples in tasks. If a pattern you were about to write differs from the current docs, use the current version.
>
> Add a `## Library References` appendix at the bottom of the plan listing each library checked, its resolved ID/version, and 3-5 key API patterns retrieved (max ~200 tokens per library entry). This appendix travels with the plan so implementer subagents have current docs.

**Graceful degradation:** If `CONTEXT7_API_KEY` is not set, note "Context7 API key not configured — proceeding without library doc verification. Set `CONTEXT7_API_KEY` env var for up-to-date API checks." and continue. If a library is not found, note "Could not resolve docs for {library} via Context7 — proceeding with training data" and continue. Never block on API errors.

---

### 2. brainstorming/SKILL.md (HIGH priority)

**Where:** At step 4 (Propose 2-3 approaches), when recommending specific libraries. Also during spec writing (step 6) — verify API patterns in the spec document itself.

**What to add:**

In the "Exploring approaches" section, after "Lead with your recommended option and explain why":

> **Library verification:** When proposing approaches that recommend specific libraries or frameworks, fetch current docs via Context7 (using the canonical fetch pattern) to verify your API assumptions are current. Include version info in the approach (e.g., "Next.js 15 — App Router with Server Components"). If a proposed pattern is deprecated according to current docs, note it in the trade-offs and use the current pattern instead.
>
> Check that the project's pinned version matches the docs — don't recommend patterns from a newer major version than the project uses.
>
> When writing the spec document, include a `## Library References` appendix with the verified patterns (max ~200 tokens per library, 3-5 key patterns each).
>
> If `CONTEXT7_API_KEY` is not set, proceed without verification — note this once.

---

### 3. subagent-driven-development/SKILL.md + implementer-prompt.md (MEDIUM priority)

**Where in SKILL.md:** In the controller's prompt construction workflow, before dispatching each implementer subagent.

**What to add to SKILL.md:**

In the per-task dispatch section:

> **Context7 enrichment:** Before dispatching the implementer, identify which libraries the task touches (from the plan's Tech Stack and the task's file list — max 3 per task, skip utility libs). Fetch current docs via Context7 for the specific topic the task covers (e.g., "stripe webhooks" for a webhook handler task, not all of Stripe). Inject the fetched docs into the `## Library References` section of the implementer prompt.

**What to add to implementer-prompt.md:**

After the `## Context` section, add an optional section:

```
## Library References (if provided)

[Controller injects current library documentation here.
Use these as the authoritative API reference — they override
your training data if there are differences.
If versions differ from the project's pinned version, follow
the project's version, not the latest docs.]
```

---

### 4. requesting-code-review/code-reviewer.md (MEDIUM priority)

**Where:** In the reviewer checklist.

**What to add:**

Under the existing review criteria, add:

> **API Currency:**
> - For every external library appearing in the diff, fetch Context7 docs to verify API usage is current (if `CONTEXT7_API_KEY` is set). This is not optional based on uncertainty — check proactively.
> - Use the canonical fetch pattern with `--max-time 10` and `tokens=5000`.
> - Skip private `@org/` scoped packages and utility libraries without version-sensitive APIs.
> - Flag deprecated API usage as Critical (Must Fix) if a non-deprecated replacement exists in the same major version the project uses.
> - If `CONTEXT7_API_KEY` is not set, note "API currency not verified — Context7 key not configured" and proceed with best-effort review.

---

### 5. feature-porting/scanner-prompt.md (MEDIUM priority)

**Where:** At the end of Phase 4 (Produce Mapping), before Phase 5 (Save Report).

**What to add:**

> **Phase 4.5: API Currency Check**
>
> For key source libraries (auth, payments, ORM, state management — max 5), check whether the patterns extracted in Phase 2 reflect current API conventions using the canonical fetch pattern.
>
> If source patterns are deprecated, add `Port Risk: Stale API` to the Adaptation Notes column of the mapping table with a note: "Source uses {old pattern}, current docs show {new pattern}."
>
> If `CONTEXT7_API_KEY` is not set, skip this step.

---

## Graceful Degradation Rules

| Condition | Behavior |
|---|---|
| `CONTEXT7_API_KEY` not set | Skip all lookups. Note once: "Context7 API key not configured — proceeding without library doc verification." |
| Library not found (empty results) | Note: "Could not resolve docs for {library} via Context7 — proceeding with training data." Continue. |
| Private `@org/` scoped package | Skip lookup silently. Context7 only indexes public libraries. |
| API error (timeout, rate limit, 5xx) | Note the error. Continue without blocking. Never retry in a loop. |
| API returns empty docs for a query | Proceed with training data for that specific query. |
| Major version mismatch (project vs docs) | Note: "Project uses {lib} v{X} but Context7 docs are for v{Y}. Using docs conservatively." |

All degradation is silent except for the one-time notes. No user prompts, no blocking, no errors.

---

## User-Triggered Lookups

Any skill that has Context7 integration (brainstorming, writing-plans, subagent-driven-development, requesting-code-review, feature-porting) should respond to explicit user requests like "check current docs for {library}" or "what does Context7 say about {library} {topic}".

**Behavior:**
- Fetch docs using the canonical pattern
- Present results inline in the conversation
- If a plan or spec already exists in the current workflow, ask: "Should I update the Library References appendix in the plan/spec with this?"
- If the user says yes, update the document

---

## Library References Appendix Format

When embedded in specs or plans:

```markdown
## Library References

> Verified via Context7 on {date}. Use these as authoritative API reference.
> Max ~200 tokens per library. Key patterns only.

### Next.js (resolved: /vercel/next.js, project version: 15.x)
- App Router: use `generateStaticParams()` (replaces `getStaticPaths`)
- Server Components: default in app/ directory, use `'use client'` directive for client components
- Route Handlers: use `route.ts` in app/ directory with exported HTTP method functions

### Drizzle ORM (resolved: /drizzle-team/drizzle-orm, project version: 0.30.x)
- Schema: use `pgTable()` with column helpers
- Queries: use `db.select().from(table).where(eq(col, val))`
```

Max ~200 tokens per library entry. Summarize 3-5 key API patterns relevant to the task.

---

## Files to Modify

| File | Change Type | Priority |
|---|---|---|
| `skills/writing-plans/SKILL.md` | Add Context7 lookup step + Library References appendix instruction | HIGH |
| `skills/brainstorming/SKILL.md` | Add library verification at step 4 + spec writing | HIGH |
| `skills/subagent-driven-development/SKILL.md` | Add Context7 enrichment before implementer dispatch | MEDIUM |
| `skills/subagent-driven-development/implementer-prompt.md` | Add optional `## Library References` section | MEDIUM |
| `skills/requesting-code-review/code-reviewer.md` | Add API currency check to reviewer checklist (non-optional) | MEDIUM |
| `skills/feature-porting/scanner-prompt.md` | Add Phase 4.5 API currency check | MEDIUM |

**6 files modified, 0 files created.**

---

## What This Does NOT Do

- Does not add a new standalone skill (embedded in existing skills)
- Does not use MCP (REST API via curl only)
- Does not cache responses locally (fetch inline, use, done)
- Does not require npm install (curl + python3 only, universally available)
- Does not block on API errors (graceful degradation always)
- Does not store API keys in any committed file (env var only)
- Does not look up private/internal packages (skip `@org/` scopes)
- Does not "correct" code to a newer major version than the project uses
