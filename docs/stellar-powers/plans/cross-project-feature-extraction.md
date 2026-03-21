# Cross-Project Feature Extraction & Adaptation Procedure

> **Purpose:** Structured workflow for porting features from existing projects (Laravel+React or other stacks) into this Next.js boilerplate. Designed for sub-agent execution — each phase produces a saved artifact in `.stellar-powers/reports/`.

---

## When to Use

When the user says any of:
- "Port the X feature from my other project"
- "I have this working in another app, bring it here"
- "Extract X from /path/to/project"
- "Migrate X from my Laravel app"
- "I already have X built in another project"
- "Take the X logic from my other app"
- "Copy the X feature from project Y"
- "Reuse the X implementation from /path/"
- "I built X in another codebase, use it here"
- Any reference to using an existing feature from another local project

## Scope Boundaries

**Include:** Only what is exclusively owned by the target feature. If a component/model/service is used ONLY by this feature, include it.

**Defer:** Shared dependencies used by multiple features. Log them as blockers:
```markdown
## Shared Dependencies (Out of Scope)
- `NotificationService` — used by billing AND case management. Port separately.
- `users` table changes — affects auth. Coordinate with auth migration.
```

**Rule:** When in doubt, defer. It's safer to port a feature without a shared dependency and add it later than to accidentally break another feature by porting shared code.

## Prerequisites

- **Source project path:** Local filesystem path (e.g., `/Users/rohits/dev/Nyayasathi/`)
- **Feature name:** What to extract (e.g., "billing", "case management", "document uploads")
- **User context:** Any notes about how the feature works, special flows, or things to skip

---

## Phase 1: Source Project Scan

**Agent:** Sonnet sub-agent
**Input:** Source project path + feature name
**Output:** `.stellar-powers/reports/$(date +%Y-%m-%d)-{feature}-source-scan.md`

### Step 1: Identify Tech Stack

Read these files from the source project root:
- `composer.json` → Laravel version, PHP packages
- `package.json` → Frontend framework, JS packages
- `.env.example` or `.env` → Services, API keys, database type
- `config/` directory listing → Laravel service configs
- `resources/js/` or `src/` directory listing → Frontend structure

Document the stack:
```
## Tech Stack
- Backend: Laravel X.x (PHP X.x)
- Frontend: React X.x (via Inertia.js / standalone SPA / Blade)
- Database: MySQL / PostgreSQL
- Payment: Razorpay / Stripe
- Auth: Laravel Sanctum / Breeze / Jetstream
- State: Redux / Context / Zustand
```

### Step 2: Scan Backend (Feature-Specific)

For the target feature, read and document:

**Routes:**
```bash
grep -n "{feature}" routes/web.php routes/api.php
```
Document: HTTP method, URL, controller@method, middleware

**Controllers:**
- Read each controller file referenced in routes
- Document: method name, input validation, business logic, response format

**Models:**
- Read Eloquent models related to the feature
- Document: table name, fillable fields, relationships, scopes, accessors

**Migrations:**
- Read migration files for feature tables
- Document: table name, columns (name, type, nullable, default, FK)

**Services / Repositories:**
- Read any service classes the controllers depend on
- Document: method signatures, external API calls, business rules

**Middleware:**
- Read any feature-specific middleware
- Document: what it checks, when it redirects

**Events / Listeners / Jobs:**
- Read any async processing related to the feature

**External Dependencies & Infrastructure:**
- Webhooks: inbound webhook endpoints (Stripe, Razorpay, etc.)
- Queued Jobs: background processing (emails, PDF generation, etc.)
- Email Templates: transactional emails sent by the feature
- File Storage: S3, local disk, or other storage for uploads
- Scheduled Commands: cron/artisan commands the feature depends on
- Seeder Data: seed files that populate required reference data

**Tests:**
- Read `tests/Feature/` and `tests/Unit/` for files related to the feature
- Document: what scenarios are tested, edge cases covered, permission checks
- These are the best source of truth for business rules and edge cases
- Note: tests are not ported directly but inform the target implementation's test plan

### Step 3: Scan Frontend (Feature-Specific)

**Framework Detection:**
Before documenting components, identify the frontend integration pattern:
- Check for `@inertiajs/react` in package.json → Inertia.js (server-driven)
- Check for `axios` / `fetch` calls → REST API (SPA pattern)
- Check for `@tanstack/react-query` / `swr` → Data fetching library
- Check for `@trpc/client` / `@orpc/client` → Type-safe RPC
- Check for `@apollo/client` / `graphql` → GraphQL
- Check for Redux / Zustand / Jotai → State management

Document: "Frontend communicates with backend via {pattern}"

**Pages / Views:**
- List all pages/views for the feature
- Read each file — document: route path, component tree, data fetching

**Components:**
- Read each component file
- Document: props, state, event handlers, API calls, UI library used

**API Integration:**
- How does the frontend call the backend? (axios, fetch, Inertia)
- Document: endpoint, method, request body, response handling

**Styling:**
- What CSS framework? (Tailwind, Bootstrap, custom)
- Note any reusable patterns (card layouts, table structures, modals)

### Step 4: Document Business Logic

Synthesize the scan into business rules:
- User flows (step by step, what happens on each click)
- Edge cases (what if payment fails, what if user cancels mid-flow)
- Permissions (who can do what)
- Data validation rules

### Step 5: Extract Environment Variables

Scan `.env.example`, `config/services.php`, and any service files for required env vars:

```markdown
## Required Environment Variables

| Var Name | Purpose | Required/Optional | Target Env.ts Mapping |
|---|---|---|---|
| RAZORPAY_KEY_ID | Razorpay API key | Required for payments | Env.RAZORPAY_KEY_ID (exists) |
| S3_BUCKET | Document storage | Required for uploads | — (new, add to Env.ts) |
```

### Step 6: Save Report

Save to `.stellar-powers/reports/$(date +%Y-%m-%d)-{feature}-source-scan.md` with this structure:

> The sub-agent MUST substitute the actual current date, not use the literal string 'YYYY-MM-DD'.

```markdown
# Source Scan: {Feature Name}

**Source:** {path}
**Scanned:** {date}
**Stack:** Laravel X.x + React X.x

## Tech Stack Summary
...

## Backend

### Routes
| Method | URL | Controller | Middleware |
|---|---|---|---|
| POST | /api/billing/subscribe | BillingController@subscribe | auth, verified |

### Controllers
#### BillingController
- `subscribe(Request $request)` — validates plan_id, creates Razorpay subscription...
...

### Models & Schema
#### Subscription
| Column | Type | Notes |
|---|---|---|
| id | bigint PK | |
| user_id | FK → users | |
...

### Services
...

## Frontend

### Pages
| Route | Component | Data |
|---|---|---|
| /billing | BillingPage | plans, subscription, invoices |

### Components
#### PricingCard
- Props: plan, currentPlan, onSubscribe
- Renders: card with price, features, CTA button
...

### API Calls
| Component | Endpoint | Method | Purpose |
|---|---|---|---|
| PricingCard | /api/billing/subscribe | POST | Create subscription |

## Business Logic
### User Flows
1. Subscribe: ...
2. Cancel: ...
3. Upgrade: ...

### Edge Cases
- ...

### Permissions
- ...
```

### ⏸ Quick Review

After Phase 1 scan, present a summary to the user: "Scan complete — found {N} routes, {N} components, {N} tables. Report saved to {path}. Proceeding to mapping." User can interrupt to adjust scope.

---

## Phase 2: Target Mapping

**Agent:** Sonnet sub-agent (can be same or different)
**Input:** Source scan report + target project knowledge (CLAUDE.md, existing code)
**Output:** `.stellar-powers/reports/$(date +%Y-%m-%d)-{feature}-mapping.md`

### Step 1: Read Target Project State

Read these files for target architecture context:
- `{TARGET_PATH}/CLAUDE.md` — architecture overview (references AGENTS.md)
- `{TARGET_PATH}/AGENTS.md` — coding conventions, patterns, commit rules
- `{TARGET_PATH}/src/models/Schema.ts` — current schema barrel exports
- `{TARGET_PATH}/src/server/router.ts` — current oRPC router structure
- `{TARGET_PATH}/src/server/procedures/` — existing procedure patterns
- `{TARGET_PATH}/src/libs/Env.ts` — current env var definitions
- `{TARGET_PATH}/src/components/billing/` — example component patterns

### Step 2: Produce Mapping Table

For every item in the source scan, determine:

```markdown
# Feature Mapping: {Feature Name}

**Source → Target**

## Backend Mapping

| Source (Laravel) | Target (Next.js + oRPC) | Status | Adaptation Notes |
|---|---|---|---|
| BillingController@subscribe | billing.createCheckout | ✅ Exists | Compare input validation |
| Subscription model | BillingSchema.subscription | ✅ Exists | Compare columns |
| RazorpayService | RazorpayAdapter | ✅ Exists | Compare methods |
| CaseController@index | — | ❌ New | Need new procedure |
| Case model | — | ❌ New | Need new schema |

## Frontend Mapping

| Source (React) | Target (Next.js) | Status | Adaptation Notes |
|---|---|---|---|
| PricingCard.jsx | PlanCard.tsx | ✅ Exists | Port styling |
| CheckoutModal.jsx | CheckoutDialog.tsx | ✅ Exists | Compare UX |
| CaseList.jsx | — | ❌ New | Need new component |

## Schema Mapping

| Source Table | Target Table | Status | Column Diff |
|---|---|---|---|
| subscriptions | subscription | ✅ Exists | Source has `grace_period`, target doesn't |
| invoices | invoice | ✅ Exists | Match |
| cases | — | ❌ New | Full port needed |

## Missing in Target (New Work)
1. ...
2. ...

## Exists but Needs Update
1. ...

## Can Skip (Already Better in Target)
1. ...
```

### Conflict Resolution Rules

When source and target both have the same entity but differ:

1. **Additive columns:** Add new columns from source to target schema. Never remove existing columns.
2. **Different column types:** Prefer the target's type unless the source type is strictly better. Document the decision.
3. **Different API shape:** Keep the target's oRPC procedure interface. Adapt source business logic to fit.
4. **UI conflicts:** Prefer the source's visual design (reason: user wants to port the UX). Adapt to target's component patterns (shadcn, i18n, etc.).
5. **Breaking changes:** Flag any change that would break existing callers. These require explicit user approval before proceeding.

### Step 3: Save Report

Save to `.stellar-powers/reports/$(date +%Y-%m-%d)-{feature}-mapping.md`

> The sub-agent MUST substitute the actual current date, not use the literal string 'YYYY-MM-DD'.

### ⏸ Human Approval Gate

After Phase 2 mapping is complete, STOP and present the mapping report to the user:

> "Feature mapping complete. Report saved to `.stellar-powers/reports/{file}`. Key findings:
> - {N} items already exist in target
> - {N} items need porting
> - {N} shared dependencies identified
>
> Please review the mapping and confirm scope before I proceed to design."

Do NOT proceed to Phase 3 until the user explicitly approves. Mapping mistakes compound into bad implementations.

---

## Phase 3: Brainstorm Adaptation

**Skill:** `stellar-powers:brainstorming`
**Input:** Source scan + mapping report
**Output:** Design spec at `.stellar-powers/specs/`

Feed both reports into the brainstorming skill. The personas evaluate:
- **Software Architect:** Which patterns to keep vs adapt
- **Security Engineer:** Auth/permission model differences
- **Backend Architect:** Schema changes, API contract differences
- **Code Reviewer:** Code quality improvements possible during port

The brainstorming produces a design spec for the adaptation work.

---

## Phase 4: Plan & Execute

**Skill:** `stellar-powers:writing-plans` → `stellar-powers:subagent-driven-development`

### Step 1: Invoke writing-plans
```
Skill tool → stellar-powers:writing-plans
Args: "Create implementation plan based on the design spec at .stellar-powers/specs/$(date +%Y-%m-%d)-{feature}-adaptation-design.md. The spec was produced from cross-project feature extraction — source scan at .stellar-powers/reports/$(date +%Y-%m-%d)-{feature}-source-scan.md, mapping at .stellar-powers/reports/$(date +%Y-%m-%d)-{feature}-mapping.md."
```

> The sub-agent MUST substitute the actual current date, not use the literal string 'YYYY-MM-DD'.

### Step 2: Plan review
The writing-plans skill runs its own persona-based review loop.

### Step 3: User approval
Present the plan for user approval before execution.

### Step 4: Execute via subagent-driven-development
```
Skill tool → stellar-powers:subagent-driven-development
Args: "Execute the plan at .stellar-powers/plans/$(date +%Y-%m-%d)-{feature}-adaptation.md"
```

Each task is dispatched to a fresh sonnet sub-agent with the plan as context.

---

## Skill References

These skills are invoked via the `Skill` tool in Claude Code:

| Skill | When Used | Purpose |
|---|---|---|
| `stellar-powers:brainstorming` | Phase 3 | Design the adaptation through clarifying questions, approach proposals, and persona-based review |
| `stellar-powers:writing-plans` | Phase 4 | Create a detailed implementation plan from the design spec |
| `stellar-powers:subagent-driven-development` | Phase 4 | Execute the plan task-by-task with fresh sub-agents |

Invoke with: `Skill tool → skill name → args describing the task`

---

## Sub-Agent Prompt Template

When dispatching the Phase 1 scan sub-agent, use this template:

> The orchestrator resolves {TARGET_PATH} to the current working directory at dispatch time.

```
You are scanning a source project to extract a specific feature for porting to another codebase.

## Source Project
- Path: {SOURCE_PATH}
- Feature to extract: {FEATURE_NAME}
- User context: {ANY_NOTES}

## Your Task
Follow the Cross-Project Feature Extraction procedure at:
{TARGET_PATH}/.stellar-powers/plans/cross-project-feature-extraction.md

Execute Phase 1 (Source Project Scan) completely:
1. Identify tech stack
2. Scan backend (routes, controllers, models, migrations, services)
3. Scan frontend (pages, components, API calls, styling)
4. Document business logic (flows, edge cases, permissions)
5. Extract environment variables
6. Save the report to .stellar-powers/reports/$(date +%Y-%m-%d)-{feature}-source-scan.md

DO NOT modify any files in the source project.
DO NOT modify any files in the target project except the report file.
Report DONE with a summary of findings.
```

For Phase 2 mapping sub-agent:

> The orchestrator resolves {TARGET_PATH} to the current working directory at dispatch time.

```
You are mapping a scanned source feature to a target codebase for adaptation.

## Source Scan Report
- Path: .stellar-powers/reports/$(date +%Y-%m-%d)-{feature}-source-scan.md

## Target Project
- Path: {TARGET_PATH}
Read these files for target architecture context:
- {TARGET_PATH}/CLAUDE.md — architecture overview (references AGENTS.md)
- {TARGET_PATH}/AGENTS.md — coding conventions, patterns, commit rules
- {TARGET_PATH}/src/models/Schema.ts — current schema barrel exports
- {TARGET_PATH}/src/server/router.ts — current oRPC router structure
- {TARGET_PATH}/src/server/procedures/ — existing procedure patterns
- {TARGET_PATH}/src/libs/Env.ts — current env var definitions
- {TARGET_PATH}/src/components/billing/ — example component patterns

## Your Task
Follow the Cross-Project Feature Extraction procedure at:
.stellar-powers/plans/cross-project-feature-extraction.md

Execute Phase 2 (Target Mapping) completely:
1. Read target project state (schema, procedures, components, routes)
2. Produce mapping table (source → target, status, adaptation notes)
3. Save to .stellar-powers/reports/$(date +%Y-%m-%d)-{feature}-mapping.md

DO NOT modify any source code files.
Report DONE with a summary of the mapping.
```

---

## Reports Directory

All scan and mapping reports are saved to:
```
.stellar-powers/reports/
├── 2026-03-21-billing-source-scan.md
├── 2026-03-21-billing-mapping.md
├── 2026-03-22-case-management-source-scan.md
├── 2026-03-22-case-management-mapping.md
└── ...
```

---

## Summary of Roles

| Phase | Who | Input | Output |
|---|---|---|---|
| 1. Source Scan | Sonnet sub-agent | Source path + feature name | Source scan report |
| 2. Target Mapping | Sonnet sub-agent | Scan report + target codebase | Mapping report |
| 3. Brainstorm | Stellar Powers | Both reports | Design spec |
| 4. Plan & Execute | Stellar Powers | Design spec | Implementation |

**User effort:** Provide the path and feature name. Everything else is automated.
