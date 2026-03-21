# Feature Porting Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use stellar-powers:subagent-driven-development (recommended) or stellar-powers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `feature-porting` skill to Stellar Powers that dispatches a Sonnet sub-agent to scan a source project, map findings to the target project, produce an extraction report, and hand off to brainstorming for design.

**Architecture:** Two deliverables: (1) new `skills/feature-porting/` directory with SKILL.md and scanner-prompt.md, (2) a small addition to `skills/brainstorming/SKILL.md` for cross-project intent detection. The skill follows the same patterns as existing skills (frontmatter, workflow logging, checklist-driven).

**Tech Stack:** Markdown skill files, shell commands for workflow logging, Agent tool for sub-agent dispatch.

**Spec:** `.stellar-powers/specs/2026-03-21-feature-porting-design.md`

---

## File Structure

| Action | File | Responsibility |
|---|---|---|
| Create | `skills/feature-porting/SKILL.md` | Skill definition: trigger, input collection, checklist, flow, workflow logging, approval gate, error handling, session resumption, handoff to brainstorming |
| Create | `skills/feature-porting/scanner-prompt.md` | Sub-agent prompt template with variable placeholders for source path, feature name, target path, user context, report path |
| Modify | `skills/brainstorming/SKILL.md` | Add cross-project intent detection at step 3, with reference to feature-porting trigger phrases |

---

### Task 1: Create scanner-prompt.md

The sub-agent prompt template is the core artifact. It defines exactly what the Sonnet sub-agent does when dispatched. This task contains the COMPLETE content to write — do not look for it elsewhere.

**Files:**
- Create: `skills/feature-porting/scanner-prompt.md`

- [ ] **Step 1: Create the feature-porting skill directory**

Run:
```bash
mkdir -p skills/feature-porting
```

- [ ] **Step 2: Write scanner-prompt.md**

Create `skills/feature-porting/scanner-prompt.md` with the following EXACT content (this is the complete file, not a summary):

```markdown
# Feature Extraction Scanner Prompt

> **This is a prompt template.** The orchestrating skill reads this file, substitutes the `{{VARIABLES}}` below, and dispatches it via the Agent tool with model=sonnet. Do not invoke this file directly.

## Variables

- `{{SOURCE_PATH}}` — absolute path to the source project
- `{{FEATURE_NAME}}` — name of the feature to extract
- `{{TARGET_PATH}}` — absolute path to the target project (current working directory)
- `{{USER_CONTEXT}}` — optional user-provided notes about scope or behavior
- `{{REPORT_PATH}}` — where to save the extraction report

---

You are a feature extraction analyst. Your job is to scan a source project, understand a specific feature, then map it to a target project for porting.

## Inputs

- **Source project path:** {{SOURCE_PATH}}
- **Feature to extract:** {{FEATURE_NAME}}
- **Target project path:** {{TARGET_PATH}}
- **User context:** {{USER_CONTEXT}}

## Constraints

- DO NOT modify any files in the source project
- DO NOT modify any files in the target project except the report file
- DO NOT write any implementation code
- Save ONLY the extraction report to: {{REPORT_PATH}}
- Always use the ACTUAL current date in the report, never literal YYYY-MM-DD

## Phase 1: Dynamic Discovery

Perform this discovery for BOTH the source and target projects.

### Step 1 — Read project root indicators

Check which of these exist and read them (skip those that don't):
- AI project docs: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`
- General docs: `README.md`
- Package manifests: `package.json`, `composer.json`, `Gemfile`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `pom.xml`
- Environment: `.env.example` or `.env`

### Step 2 — Scan for documentation directories

List and read relevant docs from these directories if they exist:
- `docs/`, `documentation/`, `architecture/`, `.cursor/`, `.github/`

### Step 3 — Scan project structure

List top-level directories to understand the layout. Identify where routes, models/schema, services, and frontend components live based on what actually exists.

### Step 4 — Summarize stack

For each project, produce:
- Backend: framework + language + version
- Frontend: framework + version
- Database: type
- Key libraries: auth, payments, state management, etc.
- Communication pattern: how frontend talks to backend (REST, GraphQL, RPC, Inertia, etc.)

## Phase 2: Source Feature Scan

Scan the source project for everything related to **{{FEATURE_NAME}}**. Use the stack you discovered to know WHERE to look — do not assume any specific file paths or framework conventions.

### Backend Checklist

- **Routes / API endpoints:** HTTP method, URL, handler, middleware
- **Controllers / handlers:** method signatures, input validation, business logic summary, response format
- **Models / schema:** table name, columns (name, type, nullable, default), relationships, constraints
- **Migrations:** schema history for feature tables
- **Services / business logic:** method signatures, external API calls, business rules
- **Middleware:** feature-specific auth or permission checks
- **Background jobs / events / webhooks:** async processing related to the feature
- **Tests:** what scenarios are covered, edge cases tested, permission checks (document for reference — tests are NOT ported directly but inform the target test plan)

### Frontend Checklist

- **Pages / views:** route path, component tree, data fetching pattern
- **Components:** props, state management, event handlers, API calls made
- **API integration:** how frontend calls backend, which endpoints, request/response shapes
- **Styling:** CSS framework used, reusable visual patterns (card layouts, table structures, modals)

### Business Logic

- **User flows:** step-by-step for each major action (e.g., "1. User clicks Subscribe 2. Modal opens 3. ...")
- **Edge cases:** what happens when things go wrong (payment fails, user cancels mid-flow, etc.)
- **Permissions:** who can do what (roles, ownership checks)
- **Validation rules:** input constraints enforced by backend and frontend

### Environment Variables

Scan `.env.example`, config files, and service files for env vars required by this feature:
- Variable name, purpose, required vs optional

### Token Management

- Read file listings before reading full files — prioritize what's relevant to the feature
- Skip test files on first pass — only read tests if business logic is unclear from source code
- Summarize rather than copy — the report captures logic and structure, not verbatim code

## Phase 3: Target Overlap Scan

Scan the target project for anything that overlaps with the source feature. Focus on:
- Existing routes/endpoints that serve similar purposes
- Existing schema/models that map to source tables
- Existing components that cover similar UI
- Existing services that handle similar business logic

This does NOT need to be as thorough as the source scan — focus on finding overlaps and noting differences.

## Phase 4: Produce Mapping

For every item found in the source scan, determine its status in the target:

| Status | Meaning |
|---|---|
| Exists | Target has an equivalent. Note differences in adaptation column. |
| Needs Update | Target has a partial equivalent. Note what's missing. |
| New | Target has nothing equivalent. Full port needed. |
| Skip | Target already has something better. Explain why. |

### Conflict Resolution Rules

- **Additive only:** never remove existing target columns or features
- **Prefer target patterns:** adapt source logic to fit target architecture, not the reverse
- **Flag breaking changes:** anything that would break existing target callers gets flagged explicitly with a warning

### Scope Boundary Heuristics

Use these tests to determine if something is feature-owned or shared:

1. **File-level test:** If a file is inside a feature-specific directory (e.g., `billing/`, `invoices/`), it's feature-owned
2. **Import test:** Grep for imports/references across the codebase. If imported ONLY by files in the feature scope, it's feature-owned. If imported by other features too, it's shared
3. **Naming test:** Generic names (`NotificationService`, `FileUploader`, `BaseRepository`) are likely shared
4. **When uncertain:** Log it in the "Shared Dependencies" section with a note explaining the ambiguity. Let the user decide during approval. Do NOT include uncertain items in the main mapping.

## Phase 5: Save Report

Save the complete report to `{{REPORT_PATH}}`.

If a file already exists at that path, append a counter suffix: `-2.md`, `-3.md`, etc.

Use this report format:

---

(begin report)

# Feature Extraction: {{FEATURE_NAME}}

**Source:** {{SOURCE_PATH}}
**Target:** {{TARGET_PATH}}
**Date:** (actual current date)

---

## Source Stack Summary

(framework, language, version, key libraries, frontend-backend communication pattern)

## Target Stack Summary

(same structure as source)

## Backend Analysis

### Routes
| Method | URL | Handler | Middleware |
|---|---|---|---|

### Controllers / Handlers
(method signatures, validation, business logic, response format)

### Models / Schema
| Table | Column | Type | Notes |
|---|---|---|---|

### Services
(method signatures, external API calls, business rules)

### Background Jobs / Events / Webhooks
(if any exist for this feature)

## Frontend Analysis

### Pages
| Route | Component | Data Fetching |
|---|---|---|

### Components
(props, state, event handlers, API calls)

### API Integration
| Component | Endpoint | Method | Purpose |
|---|---|---|---|

### Styling
(CSS framework, reusable patterns)

## Business Logic

### User Flows
1. (flow name): (step by step)

### Edge Cases
- (case): (behavior)

### Permissions
- (rule)

## Mapping Table

### Backend Mapping
| Source | Target | Status | Adaptation Notes |
|---|---|---|---|

### Frontend Mapping
| Source | Target | Status | Adaptation Notes |
|---|---|---|---|

### Schema Mapping
| Source Table | Target Table | Status | Column Diff |
|---|---|---|---|

## New Work Required
1. (item) - (type) - (effort: Trivial/Small/Medium/Large)

## Exists But Needs Update
1. (item) - (what needs changing)

## Can Skip
1. (item) - (reason target is already better)

## Shared Dependencies (Out of Scope)
- (dependency) - used by (features). Port separately.

## Environment Variables
| Source Var | Target Equivalent | Status | Notes |
|---|---|---|---|

(end report)

---

## Graceful Degradation

If you are running low on context or approaching token limits:
1. Save what you have immediately — a partial report is better than none
2. Add an `## Incomplete` section at the end listing what was NOT scanned
3. Prioritize in this order: backend mapping > frontend mapping > business logic > tests

## Done

After saving the report, output a summary with these exact fields:
- Source stack: (one line)
- Target stack: (one line)
- Items already in target: (count)
- Items needing port: (count)
- Shared dependencies deferred: (count)
- Report saved to: {{REPORT_PATH}}
```

- [ ] **Step 3: Verify the file is structurally correct**

Run:
```bash
grep -n "^## Phase" skills/feature-porting/scanner-prompt.md
```

Expected: 5 lines showing Phase 1 through Phase 5 headers:
```
Phase 1: Dynamic Discovery
Phase 2: Source Feature Scan
Phase 3: Target Overlap Scan
Phase 4: Produce Mapping
Phase 5: Save Report
```

Also verify variable placeholders are present:
```bash
grep -c "{{SOURCE_PATH}}\|{{FEATURE_NAME}}\|{{TARGET_PATH}}\|{{USER_CONTEXT}}\|{{REPORT_PATH}}" skills/feature-porting/scanner-prompt.md
```

Expected: 10+ occurrences across the file.

- [ ] **Step 4: Commit**

```bash
git add skills/feature-porting/scanner-prompt.md
git commit -m "feat: add scanner prompt template for feature-porting skill"
```

---

### Task 2: Create SKILL.md

The main skill definition file. This is what gets loaded when the user invokes `stellar-powers:feature-porting`. This task contains ALL content to write — do not look for it in the spec.

**Files:**
- Create: `skills/feature-porting/SKILL.md`

**Pattern reference:** Study `skills/brainstorming/SKILL.md` for the structural pattern (frontmatter, checklist with numbered steps, workflow logging shell commands, process flow description). The workflow logging shell commands follow the same JSON format as brainstorming — copy that pattern, changing `"skill":"brainstorming"` to `"skill":"feature-porting"` and adapting the event names.

- [ ] **Step 1: Write SKILL.md**

Create `skills/feature-porting/SKILL.md` with the following structure and content:

**Frontmatter:**
```yaml
---
name: feature-porting
description: Use when porting a feature from one project to another - scans source project, maps to target, produces extraction report for brainstorming
---
```

**Section 1 — Title & Overview:**
```markdown
# Feature Porting

Port features between projects by dispatching a scan sub-agent and producing a mapping report. The report feeds into brainstorming for design.
```

**Section 2 — When to Use (canonical trigger phrase list):**
```markdown
## When to Use

- "Port X from /path"
- "Bring X from my other project"
- "Extract X from /path/to/project"
- "I have X working in another app, migrate it here"
- "Reuse X from /path"
- Any reference to using an existing feature from another local project
```

**Section 3 — Checklist:**

Write a numbered checklist (same pattern as brainstorming's checklist — "You MUST create a task for each of these items and complete them in order"):

0. **Workflow setup** — Generate workflow ID and log invocation. Shell commands (follow the brainstorming pattern, using this JSON structure):
   ```bash
   WF_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
   mkdir -p .stellar-powers/reports
   echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"skill_invocation\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"feature-porting\",\"args\":\"feature=${FEATURE_NAME} source=${SOURCE_PATH}\"}}" >> .stellar-powers/workflow.jsonl
   ```
   Also check `.stellar-powers/workflow.jsonl` for incomplete feature-porting workflows (see Session Resumption section).

1. **Collect inputs** — Gather source path, feature name, and optional user context.
   - **Source project path:** Ask if not provided. Validate: run `test -d {path}`. If it doesn't exist, report error and ask again. If it looks like a URL or remote path, reject: "Feature porting requires a local filesystem path. Please clone or mount the project locally first."
   - **Feature name:** Ask if not provided: "What feature do you want to extract? (e.g., billing, document uploads, case management)"
   - **User context:** Ask if not provided: "Any notes about scope, things to skip, or how the feature works? (optional, press enter to skip)"
   - If none were provided inline, ask all three in a single message. If some were provided (e.g., "port billing from /path"), only ask for what's missing.

2. **Dispatch scanner sub-agent** — Read `./scanner-prompt.md` using the Read tool. Substitute the 5 variables:
   - `{{SOURCE_PATH}}` → the validated source path
   - `{{FEATURE_NAME}}` → the feature name
   - `{{TARGET_PATH}}` → current working directory
   - `{{USER_CONTEXT}}` → user context (or "None provided")
   - `{{REPORT_PATH}}` → `.stellar-powers/reports/YYYY-MM-DD-{feature}-extraction.md` (use actual date, kebab-case feature name)

   Dispatch via the Agent tool with `model=sonnet`. Log scan_started:
   ```bash
   echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"scan_started\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"source\":\"${SOURCE_PATH}\",\"feature\":\"${FEATURE_NAME}\",\"report_path\":\"${REPORT_PATH}\"}}" >> .stellar-powers/workflow.jsonl
   ```

3. **Process sub-agent results** — Log scan_completed:
   ```bash
   echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"scan_completed\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"report_path\":\"${REPORT_PATH}\",\"status\":\"complete\"}}" >> .stellar-powers/workflow.jsonl
   ```
   Check if the report contains an `## Incomplete` section. If so, note `"status":"partial"` instead.

4. **Present approval summary** — Show the user:
   > "Feature extraction complete for {feature}. Report saved to {path}.
   > - Source stack: {summary}
   > - Target stack: {summary}
   > - {N} items already exist in target
   > - {N} items need porting
   > - {N} shared dependencies deferred
   >
   > Review the report and confirm before I proceed to design."

5. **Handle user response:**
   - If approved: log user_approved:
     ```bash
     echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"user_approved\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"report_path\":\"${REPORT_PATH}\"}}" >> .stellar-powers/workflow.jsonl
     ```
   - If changes requested: ask "Would you like me to re-run the full scan, or would you prefer to edit the report directly?" Full re-run goes back to step 2. Manual edit: user says "done" when finished, re-present summary.

6. **Commit report:**
   ```bash
   git add {REPORT_PATH}
   git commit -m "docs: add {feature} feature extraction report"
   ```

7. **Handoff to brainstorming** — Log handoff:
   ```bash
   echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"handoff_brainstorming\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"report_path\":\"${REPORT_PATH}\"}}" >> .stellar-powers/workflow.jsonl
   ```
   Invoke brainstorming: use the Skill tool with `skill: "stellar-powers:brainstorming"` and `args: "Design adaptation based on feature extraction report at {REPORT_PATH}"`.

**Section 4 — Session Resumption:**
```markdown
## Session Resumption

On invocation, check `.stellar-powers/workflow.jsonl` for incomplete feature-porting workflows — a `skill_invocation` or `scan_started` event without a corresponding `user_approved` or `handoff_brainstorming`. If found:

1. Load the most recent incomplete workflow's context (source path, feature name, report path from event data)
2. Check if a report exists at the report path
3. If report exists: present it to the user for approval (skip re-scanning)
4. If no report exists: inform the user of the interrupted scan and ask whether to re-run
5. Do not re-prompt for inputs that were already collected
```

**Section 5 — Error Handling:**
```markdown
## Error Handling

| Failure | Handling |
|---|---|
| Source path doesn't exist | Validate with `test -d` before dispatching sub-agent. Report error, ask for correct path |
| Source path is empty / not a project | Sub-agent reports "no project indicators found" and returns. Skill surfaces this to user |
| Sub-agent hits context limits | Sub-agent saves partial report with `## Incomplete` section. Skill presents partial results, asks user whether to proceed with partial data or narrow scope |
| Report write fails | Report error to user, suggest checking disk space / permissions |
| Sub-agent returns no useful data | Report "scan produced no actionable findings", ask user for more context or narrower scope |
```

**Section 6 — Report Collision:**
```markdown
## Report Collision

If a report for the same feature and date already exists at the target path, append a counter suffix: `-2.md`, `-3.md`, etc. Check before dispatching the sub-agent.
```

**Section 7 — Scope Boundaries:**
```markdown
## Scope Boundaries

- Include only what is exclusively owned by the target feature
- Shared dependencies (used by multiple features) are logged as "out of scope - port separately"
- When in doubt, defer — it's safer to port without a shared dependency and add it later
```

- [ ] **Step 2: Verify the file has correct frontmatter**

Run:
```bash
head -4 skills/feature-porting/SKILL.md
```

Expected:
```
---
name: feature-porting
description: Use when porting a feature from one project to another - scans source project, maps to target, produces extraction report for brainstorming
---
```

- [ ] **Step 3: Verify all 5 workflow events have shell commands**

Run:
```bash
grep -c "skill_invocation\|scan_started\|scan_completed\|user_approved\|handoff_brainstorming" skills/feature-porting/SKILL.md
```

Expected: 5+ (at least one per event type).

- [ ] **Step 4: Verify skill invokes brainstorming correctly**

Run:
```bash
grep "stellar-powers:brainstorming" skills/feature-porting/SKILL.md
```

Expected: At least one line referencing `stellar-powers:brainstorming` in the handoff step, with instructions to use the Skill tool.

- [ ] **Step 5: Verify skill is discoverable**

Run:
```bash
ls skills/feature-porting/
```

Expected: `SKILL.md` and `scanner-prompt.md` both present.

- [ ] **Step 6: Commit**

```bash
git add skills/feature-porting/SKILL.md
git commit -m "feat: add feature-porting skill definition"
```

---

### Task 3: Modify brainstorming SKILL.md

Add cross-project intent detection at step 3 of brainstorming's checklist.

**Files:**
- Modify: `skills/brainstorming/SKILL.md`

- [ ] **Step 1: Read the current brainstorming SKILL.md**

Read `skills/brainstorming/SKILL.md` to understand the current structure before making changes. Note the line numbers for:
- The checklist item `3. **Ask clarifying questions**` (around line 33)
- The "Understanding the idea" section under "The Process" (around line 80-88)

- [ ] **Step 2: Update the checklist step 3 description**

Find this exact line in the checklist:
```
3. **Ask clarifying questions** — one at a time, understand purpose/constraints/success criteria
```

Replace it with:
```
3. **Ask clarifying questions** — check for cross-project porting intent first (see "Cross-project feature porting" section), then ask one at a time to understand purpose/constraints/success criteria
```

- [ ] **Step 3: Add cross-project feature porting subsection**

In the "The Process" section, after the "Understanding the idea" bullet list (after the line `- Focus on understanding: purpose, constraints, success criteria`), insert this new subsection:

```markdown
**Cross-project feature porting:**

- Before asking the first clarifying question at step 3, check whether the user's initial message matches cross-project porting intent — references to porting, extracting, migrating, or reusing a feature from another local project. See `feature-porting/SKILL.md` for the canonical trigger phrase list.
- If detected, ask: "It sounds like you want to port a feature from another project. Should I run a feature extraction scan first?"
- If yes: invoke `stellar-powers:feature-porting` skill. It runs its full flow (input collection, scan, approval). Once approved, control returns here.
- If the user provides an existing report path (e.g., "I already have the extraction report at .stellar-powers/reports/..."), read that specific path. No scan needed.
- After feature-porting completes or a report is provided, resume at step 3. Treat the extraction report as a requirements document — don't re-ask questions the report already answers. Focus clarifying questions on adaptation decisions (e.g., "the source uses X approach but the target uses Y — which do you prefer?").
```

- [ ] **Step 4: Verify the edit is in the right location**

Run:
```bash
grep -n "cross-project\|Cross-project\|feature-porting" skills/brainstorming/SKILL.md
```

Expected: The checklist update should appear around the original line 33 area. The new subsection should appear after "Focus on understanding" (around line 88-95 area). Both `feature-porting/SKILL.md` and `stellar-powers:feature-porting` should appear in the output.

- [ ] **Step 5: Review the diff before committing**

Run:
```bash
git diff skills/brainstorming/SKILL.md
```

Verify: Only the checklist line change and the new subsection insertion appear. No unintended deletions or modifications to other parts of the file.

- [ ] **Step 6: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "feat: add cross-project porting intent detection to brainstorming skill"
```

---

### Task 4: End-to-end verification

Verify all files are in place, correctly structured, and consistent with each other.

**Files:**
- Read: `skills/feature-porting/SKILL.md`
- Read: `skills/feature-porting/scanner-prompt.md`
- Read: `skills/brainstorming/SKILL.md`

- [ ] **Step 1: Verify feature-porting skill files exist**

Run:
```bash
ls -la skills/feature-porting/
```

Expected: `SKILL.md` and `scanner-prompt.md` both present.

- [ ] **Step 2: Verify SKILL.md references scanner-prompt.md correctly**

Run:
```bash
grep "scanner-prompt" skills/feature-porting/SKILL.md
```

Expected: At least one reference to `./scanner-prompt.md` in the dispatch step.

- [ ] **Step 3: Verify brainstorming references feature-porting**

Run:
```bash
grep "feature-porting" skills/brainstorming/SKILL.md
```

Expected: References to both `feature-porting/SKILL.md` (canonical trigger list) and `stellar-powers:feature-porting` (skill invocation).

- [ ] **Step 4: Verify trigger phrases are canonical (one location only)**

Run:
```bash
grep -c "Port X from" skills/feature-porting/SKILL.md skills/brainstorming/SKILL.md
```

Expected: `skills/feature-porting/SKILL.md:1` and `skills/brainstorming/SKILL.md:0` — trigger phrases live only in feature-porting, brainstorming references them.

- [ ] **Step 5: Verify all 5 workflow events have shell commands in SKILL.md**

Run:
```bash
grep -o "skill_invocation\|scan_started\|scan_completed\|user_approved\|handoff_brainstorming" skills/feature-porting/SKILL.md | sort -u
```

Expected: All 5 event names listed.

- [ ] **Step 6: Verify scanner-prompt.md has all 5 phases**

Run:
```bash
grep "^## Phase" skills/feature-porting/scanner-prompt.md
```

Expected: 5 lines (Phase 1 through Phase 5).

- [ ] **Step 7: Verify scanner-prompt.md has all variable placeholders**

Run:
```bash
grep -o "{{[A-Z_]*}}" skills/feature-porting/scanner-prompt.md | sort -u
```

Expected: `{{FEATURE_NAME}}`, `{{REPORT_PATH}}`, `{{SOURCE_PATH}}`, `{{TARGET_PATH}}`, `{{USER_CONTEXT}}`

- [ ] **Step 8: Verify git history**

Run:
```bash
git log --oneline -5
```

Expected: 3 new commits for scanner-prompt, SKILL.md, and brainstorming edit.
