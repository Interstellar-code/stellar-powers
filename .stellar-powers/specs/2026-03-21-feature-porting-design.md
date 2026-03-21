# Design Spec: Feature Porting Skill

**Date:** 2026-03-21
**Workflow ID:** 7DD9E572-D266-49E4-A454-4DE6A75E0647
**Status:** Draft

---

## Overview

A new Stellar Powers skill (`feature-porting`) that automates the research phase of porting features between projects. It dispatches a Sonnet sub-agent to scan a source project, map findings to the target project, and produce a combined extraction report. The report feeds into the existing brainstorming skill for design, which then flows through writing-plans and subagent-driven-development for implementation.

## Problem

When working across multiple projects with different stacks, porting a proven feature from one project to another requires significant manual research: understanding what exists in the source, what exists in the target, and how to adapt between them. This is time-consuming and error-prone.

## Solution

A two-part solution:

1. **New `feature-porting` skill** — Handles scan + mapping via a Sonnet sub-agent, produces a combined report, presents it for user approval
2. **Brainstorming enhancement** — Detects cross-project porting intent and invokes `feature-porting` before continuing with design

---

## Skill Definition

**Name:** `stellar-powers:feature-porting`

**Trigger phrases:**
- "Port X from /path"
- "Bring X from my other project"
- "Extract X from /path/to/project"
- "I have X working in another app, migrate it here"
- "Reuse X from /path"
- Any reference to using an existing feature from another local project

**Required inputs (collected from user if not provided):**
1. **Source project path** — local filesystem path
2. **Feature name** — what to extract (e.g., "billing", "document uploads")
3. **User context** (optional) — notes about scope, things to skip, how the feature works

**Target project** — always the current working directory.

**Scope boundaries:**
- Include only what is exclusively owned by the target feature
- Shared dependencies (used by multiple features) are logged as "out of scope - port separately"
- When in doubt, defer

### Input Collection Flow

When inputs are missing, collect them in this order:

1. **Source project path** — Ask: "What's the path to the source project?"
   - **Validate:** Check the path exists on disk (`test -d {path}`). If it doesn't exist, report the error and ask again.
   - **Reject remote paths:** If the path looks like a URL, SSH address, or remote mount that isn't accessible, tell the user: "Feature porting requires a local filesystem path. Please clone or mount the project locally first."
2. **Feature name** — Ask: "What feature do you want to extract? (e.g., billing, document uploads, case management)"
3. **User context** — Ask: "Any notes about scope, things to skip, or how the feature works? (optional, press enter to skip)"

All three questions can be asked in a single message if none were provided. If some were provided inline (e.g., "port billing from /path"), only ask for what's missing.

---

## Dynamic Project Discovery

The sub-agent discovers both source and target project architecture without assuming any specific stack or file structure.

### Discovery Sequence

**Step 1 - Read project root indicators** (in order of priority):
- `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` - AI-oriented project docs
- `README.md` - general project overview
- `package.json`, `composer.json`, `Gemfile`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `pom.xml` - stack identification
- `.env.example` or `.env` - services and infrastructure

**Step 2 - Scan for documentation directories:**
- `docs/`, `documentation/`, `architecture/`, `.cursor/`, `.github/`
- Read any architecture or design docs found

**Step 3 - Scan project structure:**
- List top-level directories to understand the layout
- Identify where routes, models/schema, services, and frontend components live based on what exists (not assumptions)

**Step 4 - Summarize stack:**
- Backend framework + language + version
- Frontend framework + version
- Database type
- Key libraries (auth, payments, state management, etc.)
- How frontend communicates with backend (REST, GraphQL, RPC, Inertia, etc.)

The sub-agent performs this discovery for both source and target projects.

---

## Sub-Agent Scan & Mapping Checklist

After discovery, the sub-agent works through this high-level checklist. It determines where each item lives based on the stack it discovered - no framework-specific instructions.

### Backend Scan (source project)

- Routes / API endpoints - HTTP method, URL, handler, middleware
- Controllers / handlers - method signatures, validation, business logic, response format
- Models / schema - tables, columns, types, relationships, constraints
- Migrations - schema history
- Services / business logic - external API calls, business rules
- Middleware - feature-specific auth/permission checks
- Background jobs / events / webhooks
- Tests - what scenarios are covered (informs target test plan, not ported directly)

### Frontend Scan (source project)

- Pages / views - route path, component tree, data fetching
- Components - props, state, event handlers, API calls
- API integration - how frontend talks to backend, endpoints used
- Styling - CSS framework, reusable patterns

### Business Logic Synthesis

- User flows (step by step)
- Edge cases
- Permissions model
- Validation rules

### Target Project Scan

- Same checklist but focused on what already exists that overlaps with the source feature

### Mapping Table (source to target)

- For every item found in source: does it exist in target?
- Status values: Exists / Needs Update / New / Skip
- Conflict resolution rules:
  - Additive changes only - never remove existing columns or features
  - Prefer target patterns - adapt source logic to fit target architecture
  - Flag breaking changes for explicit user approval

### Scope Boundary Heuristics

Determining whether something is "exclusively owned" by the feature or "shared":

1. **File-level test:** If a file (component, service, model) is inside a feature-specific directory (e.g., `billing/`, `invoices/`), it's feature-owned
2. **Import test:** Grep for imports/references to the item across the codebase. If it's imported ONLY by files in the feature scope, it's feature-owned. If imported by other features too, it's shared
3. **Naming test:** If a utility/service has a generic name (`NotificationService`, `FileUploader`, `BaseRepository`), it's likely shared
4. **When uncertain:** Log it in the "Shared Dependencies" section with a note explaining why it's ambiguous. Let the user decide during approval

### Final Sections

- Missing in target (new work)
- Exists but needs update
- Can skip (target is already better)
- Shared dependencies (out of scope)
- Environment variables needed

---

## Report Format

Single combined report saved to `.stellar-powers/reports/YYYY-MM-DD-{feature}-extraction.md`

**Collision handling:** If a report for the same feature and date already exists, append a counter suffix: `2026-03-21-billing-extraction-2.md`, `...-3.md`, etc.

```markdown
# Feature Extraction: {Feature Name}

**Source:** {path}
**Target:** {path}
**Date:** {date}

---

## Source Stack Summary
{framework, language, version, key libraries, frontend-backend communication pattern}

## Target Stack Summary
{same structure as source}

## Backend Analysis
### Routes
| Method | URL | Handler | Middleware |
|---|---|---|---|

### Controllers / Handlers
{method signatures, validation, business logic, response format}

### Models / Schema
| Table | Column | Type | Notes |
|---|---|---|---|

### Services
{method signatures, external API calls, business rules}

### Background Jobs / Events / Webhooks
{if any}

## Frontend Analysis
### Pages
| Route | Component | Data Fetching |
|---|---|---|

### Components
{props, state, event handlers, API calls}

### API Integration
| Component | Endpoint | Method | Purpose |
|---|---|---|---|

### Styling
{CSS framework, reusable patterns}

## Business Logic
### User Flows
1. {flow name}: {step by step}

### Edge Cases
- {case}: {behavior}

### Permissions
- {rule}

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
1. {item} - {type} - {effort: Trivial/Small/Medium/Large}

## Exists But Needs Update
1. {item} - {what needs changing}

## Can Skip
1. {item} - {reason target is already better}

## Shared Dependencies (Out of Scope)
- {dependency} - used by {features}. Port separately.

## Environment Variables
| Source Var | Target Equivalent | Status | Notes |
|---|---|---|---|
```

---

## Approval Gate

After the sub-agent saves the report, the skill presents a summary:

> "Feature extraction complete for {feature}. Report saved to {path}.
> - Source stack: {summary}
> - Target stack: {summary}
> - {N} items already exist in target
> - {N} items need porting
> - {N} shared dependencies deferred
>
> Review the report and confirm before I proceed to design."

**User responses:**

- **Approves:** Skill invokes brainstorming with report path as context
- **Requests changes:** Ask the user: "Would you like me to re-run the full scan, or would you prefer to edit the report directly?" Full re-run is always the default since partial re-scans add complexity for minimal time savings (the sub-agent is fast). If the user edits the report manually, they say "done" and the skill re-presents the summary.

---

## Error & Failure Handling

| Failure | Handling |
|---|---|
| Source path doesn't exist | Validate before dispatching sub-agent. Report error, ask for correct path |
| Source path is empty / not a project | Sub-agent reports "no project indicators found" and returns. Skill surfaces this to user |
| Sub-agent hits context limits mid-scan | Sub-agent should save a partial report with a `## Incomplete` section noting what wasn't scanned. Skill presents partial results and asks user whether to proceed with partial data or narrow scope |
| Report write fails | Skill catches the error, reports it to user, suggests checking disk space / permissions |
| Sub-agent returns no useful data | Skill reports "scan produced no actionable findings" and asks user to provide more context about the feature or narrow the scope |

---

## Brainstorming Integration

### Three Entry Points

**Entry 1 - Direct invocation:** User invokes `feature-porting` explicitly. Skill runs scan+mapping, gets approval, invokes brainstorming with args: `"Design adaptation based on feature extraction report at {report_path}"`

**Entry 2 - Brainstorming detects intent:** During brainstorming, if the user references porting from another project, brainstorming pauses its normal flow, invokes `feature-porting`, gets user approval on the report, then resumes with the report as context.

**Entry 3 - User provides existing report:** User tells brainstorming the report path explicitly (e.g., "I already have the extraction report at .stellar-powers/reports/2026-03-21-billing-extraction.md"). Brainstorming reads that specific path. No scan triggered.

### Where in Brainstorming's Checklist

The integration happens at **step 3 (Ask clarifying questions)**. The detection occurs during the first clarifying question round:

1. Brainstorming completes step 1 (explore project context) and step 2 (offer visual companion) as normal
2. At step 3, before asking the first clarifying question, brainstorming checks whether the user's initial message matches cross-project intent patterns (reference the trigger phrases in `feature-porting/SKILL.md`)
3. If detected, brainstorming asks: "It sounds like you want to port a feature from another project. Should I run a feature extraction scan first?"
4. If yes: brainstorming invokes `feature-porting` skill. Feature-porting runs its full flow (input collection, scan, approval gate). Once approved, control returns to brainstorming.
5. Brainstorming resumes at step 3 with the report path stored as context. It reads the report and uses it to inform all subsequent clarifying questions, approach proposals, and design sections.
6. Steps 4-9 proceed as normal, with the extraction report referenced throughout.

**State on resume:** Brainstorming treats the approved extraction report as equivalent to a requirements document. It does NOT re-ask questions that the report already answers (e.g., "what does the billing feature do?"). Instead, it focuses clarifying questions on adaptation decisions (e.g., "the source uses a 5-step checkout wizard but the target has a simpler 3-step flow — which approach do you prefer?").

### How Brainstorming Uses the Report

- The report becomes input context alongside the project's own docs
- Brainstorming personas evaluate the mapping: architecture fit, security implications, code quality opportunities
- The design spec references the extraction report as its source of truth for what needs to be built
- The spec flows into writing-plans and subagent-driven-development as normal

---

## Sub-Agent Prompt & Constraints

**Model:** Sonnet (never Opus for sub-agents)

**Constraints:**
- **Read-only on source project** - DO NOT modify any files in the source project
- **Write only the report** - The only file created is the extraction report in `.stellar-powers/reports/`
- **No implementation** - Research and document only, no code changes to target project beyond the report
- **Scope discipline** - Shared dependencies logged as out-of-scope, not included. Use the heuristics in "Scope Boundary Heuristics" section
- **Date substitution** - Always use actual current date, never literal `YYYY-MM-DD`
- **Graceful degradation** - If context limits are approaching, save what you have with an `## Incomplete` section

**Token management:**
- Read file listings before reading full files - prioritize what's relevant to the feature
- Skip test files on first pass - only read tests if business logic is unclear from source code
- Summarize rather than copy - the report captures logic and structure, not verbatim code

### Scanner Prompt Template (`scanner-prompt.md`)

The full sub-agent prompt template. The orchestrating skill reads this file, substitutes variables, and dispatches via the Agent tool.

```markdown
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

## Phase 1: Dynamic Discovery (both projects)

For EACH project (source and target), discover the architecture:

1. Read project root indicators (check which exist, skip those that don't):
   - AI project docs: CLAUDE.md, AGENTS.md, GEMINI.md
   - General docs: README.md
   - Package manifests: package.json, composer.json, Gemfile, Cargo.toml, go.mod, pyproject.toml, pom.xml
   - Environment: .env.example or .env

2. List and scan documentation directories (if they exist):
   - docs/, documentation/, architecture/, .cursor/, .github/

3. List top-level directories to understand project layout

4. Produce a stack summary:
   - Backend: framework + language + version
   - Frontend: framework + version
   - Database: type
   - Key libraries: auth, payments, state management, etc.
   - Communication pattern: REST, GraphQL, RPC, Inertia, etc.

## Phase 2: Source Feature Scan

Scan the source project for everything related to {{FEATURE_NAME}}. Use the stack you discovered to know WHERE to look — do not assume any specific file paths.

### Backend Checklist
- Routes / API endpoints: HTTP method, URL, handler, middleware
- Controllers / handlers: method signatures, validation, business logic, response format
- Models / schema: tables, columns, types, relationships, constraints
- Migrations: schema history for feature tables
- Services / business logic: external API calls, business rules
- Middleware: feature-specific auth/permission checks
- Background jobs / events / webhooks
- Tests: what scenarios are covered (document for reference, do not port)

### Frontend Checklist
- Pages / views: route path, component tree, data fetching pattern
- Components: props, state, event handlers, API calls
- API integration: how frontend calls backend, which endpoints
- Styling: CSS framework, reusable visual patterns

### Business Logic
- User flows: step-by-step for each major action
- Edge cases: what happens when things go wrong
- Permissions: who can do what
- Validation rules: input constraints

### Environment Variables
- Scan .env.example, config files, and service files for required env vars
- Document: var name, purpose, required/optional

## Phase 3: Target Overlap Scan

Scan the target project for anything that overlaps with the source feature. Focus on:
- Existing routes/endpoints that serve similar purposes
- Existing schema/models that map to source tables
- Existing components that cover similar UI
- Existing services that handle similar business logic

## Phase 4: Produce Mapping

For every item found in the source scan, determine its status in the target:

| Status | Meaning |
|---|---|
| Exists | Target has an equivalent. Note differences. |
| Needs Update | Target has a partial equivalent. Note what's missing. |
| New | Target has nothing equivalent. Full port needed. |
| Skip | Target already has something better. Explain why. |

### Conflict Resolution
- Additive only: never remove existing target columns or features
- Prefer target patterns: adapt source logic to fit target architecture
- Flag breaking changes: anything that would break existing target callers gets flagged explicitly

### Scope Boundaries
- If a file/component/service is inside a feature-specific directory, it's feature-owned
- Grep for imports: if imported ONLY by feature files, it's feature-owned; if imported elsewhere too, it's shared
- Generic names (NotificationService, FileUploader) are likely shared
- When uncertain, log in "Shared Dependencies" with a note. Do not include uncertain items in the main mapping.

## Phase 5: Save Report

Save the complete report to {{REPORT_PATH}} using the format below. Use the ACTUAL current date, never literal YYYY-MM-DD.

If a file already exists at that path, append a counter suffix (-2, -3, etc.).

### Report Format

# Feature Extraction: {{FEATURE_NAME}}

**Source:** {{SOURCE_PATH}}
**Target:** {{TARGET_PATH}}
**Date:** {actual date}

---

(Include all sections: Source Stack Summary, Target Stack Summary, Backend Analysis, Frontend Analysis, Business Logic, Mapping Table with Backend/Frontend/Schema subsections, New Work Required with T-shirt effort sizing, Exists But Needs Update, Can Skip, Shared Dependencies, Environment Variables)

## Graceful Degradation

If you are running low on context or approaching limits:
1. Save what you have immediately
2. Add an `## Incomplete` section at the end listing what was NOT scanned
3. Prioritize: backend mapping > frontend mapping > business logic > tests

## Done

After saving the report, output a summary:
- Source stack: {one line}
- Target stack: {one line}
- Items already in target: {count}
- Items needing port: {count}
- Shared dependencies deferred: {count}
- Report saved to: {{REPORT_PATH}}
```

---

## File Structure

### New Skill

```
skills/
  feature-porting/
    SKILL.md          - skill definition (trigger, checklist, flow)
    scanner-prompt.md - sub-agent prompt template (full content above)
```

### Reports Output

```
.stellar-powers/
  reports/
    2026-03-21-billing-extraction.md
    2026-03-21-billing-extraction-2.md  (collision: same feature+date)
    2026-03-22-auth-extraction.md
```

### Changes to Existing Files

- `skills/brainstorming/SKILL.md` - add cross-project intent detection at step 3 (see "Where in Brainstorming's Checklist" section)

---

## Workflow Logging

Same pattern as other Stellar Powers skills, logged to `.stellar-powers/workflow.jsonl`.

### Shell Commands

On skill invocation:
```bash
WF_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
mkdir -p .stellar-powers/reports
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"skill_invocation\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"feature-porting\",\"args\":\"feature=${FEATURE_NAME} source=${SOURCE_PATH}\"}}" >> .stellar-powers/workflow.jsonl
```

On scan dispatch:
```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"scan_started\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"source\":\"${SOURCE_PATH}\",\"feature\":\"${FEATURE_NAME}\",\"report_path\":\"${REPORT_PATH}\"}}" >> .stellar-powers/workflow.jsonl
```

On scan completion:
```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"scan_completed\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"report_path\":\"${REPORT_PATH}\",\"status\":\"complete|partial\"}}" >> .stellar-powers/workflow.jsonl
```

On user approval:
```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"user_approved\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"report_path\":\"${REPORT_PATH}\"}}" >> .stellar-powers/workflow.jsonl
```

On handoff to brainstorming:
```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"handoff_brainstorming\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"report_path\":\"${REPORT_PATH}\"}}" >> .stellar-powers/workflow.jsonl
```

### Session Resumption

On skill invocation, check `.stellar-powers/workflow.jsonl` for incomplete `feature-porting` workflows (a `skill_invocation` or `scan_started` event without a corresponding `user_approved` or `handoff_brainstorming`). If found:

1. Load the most recent incomplete workflow's context (source path, feature name, report path)
2. Check if a partial/complete report exists at the report path
3. If report exists: present it to the user for approval (skip re-scanning)
4. If no report: inform the user of the interrupted scan and ask whether to re-run
5. Do not re-prompt for inputs that were already collected

---

## Git Integration

After the sub-agent saves the extraction report and the user approves it:

1. Stage the report file: `git add {REPORT_PATH}`
2. Commit with message: `docs: add {feature} feature extraction report`
3. This keeps the report in version history alongside the spec and plan that follow

The report is committed AFTER user approval, not immediately after the sub-agent saves it.

---

## Skill Chain Flow

```
User: "Port billing from /path/to/project"
  |
  v
feature-porting skill
  |-- validate source path exists
  |-- collect missing inputs
  |-- log workflow start
  |-- dispatch Sonnet sub-agent (scanner-prompt.md)
  |-- sub-agent: dynamic discovery (source + target)
  |-- sub-agent: scan + mapping checklist
  |-- sub-agent: save combined report
  |-- present summary for approval
  |
  v (user approves)
  |-- commit report
  |-- log handoff
  |
  v
brainstorming skill (with report as context)
  |-- design the adaptation
  |-- write spec
  |
  v
writing-plans skill
  |-- create implementation plan
  |
  v
subagent-driven-development skill
  |-- execute plan task by task
```
