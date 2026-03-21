# Stellar Powers Release Notes

## v1.4.0 — Self-Improving Agent + Bug Fixes

- **New local skill:** `self-improving-agent` — autoresearch-inspired loop that analyzes feedback issues, runs eval scenarios, proposes skill improvements on a dedicated branch, and keeps/discards based on score comparison
- **New eval system:** Test scenario runner with 3 baseline scenarios for hook validation, context resolution, and kill switch
- **Fix:** Completion checkpoint now inlines full packager/pruner scripts (was referencing snippets.md which agents skipped)
- **Fix:** Context fields (repo, task_type, sp_version) resolve correctly via env vars with .active-workflow fallback
- **Fix:** Duration calculation added to metrics packager
- **Fix:** Step tracking fires in all skills with .active-workflow step field updates at each phase
- **Fix:** `.active-workflow` step field updates at each phase transition (was stuck on "workflow_setup")
- **New:** Incremental metrics packaging — partial snapshots at brainstorming and writing-plans handoffs

---

## v1.3.0 — Self-Improving Capabilities

- **New hooks:** UserPromptSubmit, TaskCompleted, SubagentStop, Stop, PostToolUseFailure — automatic event capture for workflow metrics
- **New skill:** `/stellar-powers:send-feedback` — files accumulated metrics as GitHub issues
- **Workflow lifecycle:** `.active-workflow` state file tracks current workflow, completion checkpoint in terminal skills
- **Metrics packaging:** Automatic packaging on workflow completion, pruning of workflow.jsonl
- **Kill switch:** `feedback_enabled` config flag to disable all feedback capture
- **Privacy:** Redaction filter strips API keys, tokens, emails, and absolute paths from previews
- **Step tracking:** All skills log step_started/step_completed events
- **Correction capture:** Review gates log user corrections for feedback analysis

---

## v1.2.0 (2026-03-21)

### SDD Task Batching

Subagent-driven-development now batches small mechanical tasks to reduce dispatch overhead.

- **`[batch]` / `[solo]` annotations** — writing-plans emits complexity annotations on every task heading. Users can override during plan review.
- **Automatic grouping** — SDD groups 2-4 consecutive `[batch]` tasks into one sub-agent dispatch with per-task commits
- **Fallback heuristic** — unannotated plans (old or external) are classified per-task using the same complexity signals
- **Dependency detection** — tasks referencing other tasks by number, shared files, or prior output are auto-promoted to `[solo]`
- **Token budget guard** — batches capped at 60k tokens, max 4 tasks
- **Per-task review** — one reviewer per stage delivers per-task verdicts; failed tasks get targeted re-review without re-reviewing passing tasks
- **SHA parsing with fallback** — controller extracts commit SHAs from implementer report; falls back to `git log` if format drifts
- **Multi-task implementer prompt** — new variant with inline self-review checklist, no "Before You Begin" block (automated dispatch has no question channel)

---

## v1.1.0 (2026-03-21)

### Context7 Library Documentation Integration

Automatic, up-to-date library documentation lookups embedded across the entire skill chain — prevents LLMs from using outdated or deprecated APIs.

**Integration points:**
- **writing-plans** — verifies library APIs before writing task code blocks, adds `## Library References` appendix to every plan
- **brainstorming** — checks current docs when proposing approaches with specific libraries
- **subagent-driven-development** — enriches implementer prompts with current library docs via `## Library References` section
- **code reviewer** — non-optional API currency check on every external library in the diff
- **feature-porting scanner** — Phase 4.5 checks source patterns against current docs, flags stale APIs

**Key properties:**
- Uses Context7 REST API via `curl` (no MCP, no npm install)
- `--max-time 10` on all API calls, `tokens=5000` response cap
- Selects libraries by highest `trustScore`, not arbitrary first result
- Version-aware: checks project's pinned version, won't "correct" to a newer major version
- Graceful degradation: skips silently if `CONTEXT7_API_KEY` not set
- Skips utility libs (lodash, zod) and private `@org/` packages

**Setup:** Get a free API key at context7.com/dashboard, set `CONTEXT7_API_KEY` env var.

### Additional Improvements

- **Visual companion mandatory for UI work** — brainstorming now MUST offer mockups for UI/frontend topics, with mockup persistence to `.stellar-powers/mockups/`
- **PostToolUse hook fix** — suppressed false "hook error" messages from async stderr output, added exemptions for stellar-powers agent types
- **42-check test suite** — static validation tests covering all Context7 integration points, opus prohibition, loop guard, skill catalog, and more

---

## v1.0.9 (2026-03-21)

### Audit Remediation

Comprehensive audit of all 15 skills, hooks, manifests, and integration points — 24 issues fixed.

**Critical fixes:**
- **Loop guard** — brainstorming now skips cross-project intent detection when invoked from feature-porting (prevents infinite dispatch loop)
- **Opus prohibition** — explicit `model=sonnet` and "never use opus for subagents" added to brainstorming, writing-plans, and subagent-driven-development
- **Skill catalog** — using-stellarpowers now lists all 15 available skills with descriptions

**Skill chain fixes:**
- Brainstorming step 9 now invokes `using-git-worktrees` before writing-plans (was documented as required but never called)
- Brainstorming passes parsed source path + feature name when invoking feature-porting
- Fixed broken `stellar-powers:code-reviewer` references in requesting-code-review (was referencing a non-existent skill instead of prompt template)
- Added session resumption to requesting-code-review
- Added `task_completed` and `plan_executed` logging events to executing-plans
- Added `receiving-code-review` cross-reference from requesting-code-review
- Fixed subagent-driven-development flowchart label

**Consistency fixes:**
- Replaced `@` force-load anti-pattern with `./` in writing-skills and test-driven-development
- Unified code-reviewer severity labels (emoji → word system)
- Fixed visual-companion.md path reference in brainstorming
- Fixed brainstorming description to start with "Use when"

**Infrastructure:**
- Added PostToolUse hook to hooks-cursor.json (Cursor parity)
- Added missing keywords to .cursor-plugin/plugin.json
- Fixed gemini-extension.json (name, version, description were stale superpowers artifacts)
- Fixed package.json (removed superpowers.js main field, added missing metadata)
- Updated README with feature-porting, workflow tracking, and PostToolUse hook docs
- Added feature-porting test prompts for skill-triggering and explicit-skill-requests

---

## v1.0.8 (2026-03-21)

### New Skill: Feature Porting

Cross-project feature extraction and adaptation — port features from one project to another with automated analysis.

- **`stellar-powers:feature-porting` skill** — dispatches a Sonnet sub-agent to scan a source project, discover its tech stack dynamically, extract a specific feature's backend/frontend/business logic, map it to the target project, and produce a combined extraction report
- **Stack-agnostic discovery** — no hardcoded framework assumptions; the scanner reads project indicators (CLAUDE.md, package.json, composer.json, etc.) and adapts to whatever stack it finds
- **Scope boundary heuristics** — file-level, import, and naming tests to determine what's feature-owned vs. shared, with uncertain items deferred to user approval
- **Brainstorming integration** — brainstorming skill now detects cross-project porting intent and can invoke feature-porting automatically, or accept an existing extraction report
- **Approval gate** — report summary presented for user review before proceeding to design phase
- **Session resumption** — interrupted scans are recoverable via workflow.jsonl
- **Graceful degradation** — partial reports saved with `## Incomplete` section if context limits are hit

### Docs Reorganization

- Moved docs from `docs/plans/` and `docs/superpowers/` to `docs/stellar-powers/` for consistency with project naming

---

## v1.0.7 (2026-03-21)

### Maintenance

- Version bump and frontmatter fixes

---

## v1.0.6 (2026-03-20)

### Closed-Loop Workflow Tracking

Persistent workflow tracking across Claude Code sessions with compliance enforcement.

- **PostToolUse hook** — automatically logs every Agent dispatch to `.stellar-powers/workflow.jsonl`, detects missing persona templates, and warns on violations
- **Session continuity** — enhanced session-start hook parses workflow.jsonl and surfaces incomplete work (unfinished specs, unapproved reviews, pending plans) at session start
- **Skill-level logging** — brainstorming, writing-plans, requesting-code-review, executing-plans, and subagent-driven-development skills log semantic events (skill_invocation, spec_created, plan_created, review_verdict) with UUID correlation
- **Workflow abandonment** — `abandon workflow [id]` command marks workflows as terminal
- **Path migration** — specs and plans now live under `.stellar-powers/specs/` and `.stellar-powers/plans/` (migration notice shown for existing users)
- **20 automated tests** covering hook behavior, session-start parsing, path migration, and manifest validation

---

## v1.0.5 (2026-03-20)

### Critical Fix: Enforce persona template usage

- **SKILL.md dispatch instructions made mandatory** — brainstorming, writing-plans, subagent-driven-development, and requesting-code-review skills now explicitly instruct the agent to READ the prompt template files before dispatching subagents. Previously, agents were constructing their own ad-hoc prompts and bypassing the persona injections entirely.
- This ensures the multi-persona catalog and single-persona injections are actually used during reviews.

---

## v1.0.4 (2026-03-20)

### Fixes

- **Renamed `using-stellar-powers` directory** to `using-stellarpowers` (no dash)

---

## v1.0.3 (2026-03-20)

### Fixes

- **Renamed `using-superpowers` directory** to `using-stellar-powers` — fixes `/using-superpowers` showing in Claude Code command list
- **Fixed session-start hook** — was still reading from old directory path
- **Updated GEMINI.md, Codex docs, and test files** for directory rename

---

## v1.0.2 (2026-03-20)

### Full Rebrand

- **All skill references rebranded** — every `superpowers:` prefix across all 14 SKILL.md files, cross-references, agents, hooks, and test files now uses `stellar-powers:`
- **`using-superpowers` skill renamed** to `using-stellar-powers` in frontmatter
- **PR template updated** to reference `stellar-powers:writing-skills`
- **Test files updated** — all test assertions and prompts use `stellar-powers:` namespace

---

## v1.0.1 (2026-03-20)

### Fixes

- **Deprecated commands updated** — `/brainstorm`, `/write-plan`, `/execute-plan` now correctly reference `stellar-powers:` skills instead of `superpowers:`

---

## v1.0.0 (2026-03-20)

### Initial Release

Stellar Powers is a fork of [Superpowers v5.0.5](https://github.com/obra/superpowers) enhanced with multi-persona subagent dispatch from [Agency-Agents](https://github.com/msitarzewski/agency-agents).

### New Features

**Multi-persona review subagents**

The spec-document-reviewer and plan-document-reviewer subagents now receive a catalog of 8 expert personas with directive framing, concrete "Look for:" criteria, and a structured Domain Perspectives output section. Each review systematically applies relevant domain lenses (Software Architect, Code Reviewer, Security Engineer, Senior Project Manager, Incident Response Commander, Backend Architect, Sprint Prioritizer, DevOps Automator) and surfaces findings per persona.

**Single-persona technical subagents**

The spec-reviewer receives a Software Architect persona with an operationalized architectural integrity review category and Architect's Notes output section. The code-reviewer receives a Code Reviewer persona with a priority system and Supporting Lenses (Security Engineer, Software Architect) with a dedicated Security & Architecture Notes output section.

**Local agency-agents library**

All 156 agent persona files from agency-agents are downloaded locally under `personas/source/` for future expansion. 8 curated excerpts (~20-30 lines each) are maintained under `personas/curated/` and a master catalog at `personas/catalog.md`.

### Files Added

- `personas/catalog.md` — Master persona routing table with summaries
- `personas/curated/*.md` — 8 curated persona excerpts
- `personas/source/` — Full agency-agents library (156 files across 13 divisions)

### Files Modified

- `skills/brainstorming/spec-document-reviewer-prompt.md` — Multi-persona catalog injection
- `skills/writing-plans/plan-document-reviewer-prompt.md` — Multi-persona catalog injection
- `skills/subagent-driven-development/spec-reviewer-prompt.md` — Software Architect persona injection
- `skills/requesting-code-review/code-reviewer.md` — Code Reviewer persona + Supporting Lenses
- `.claude-plugin/plugin.json` — Rebranded to stellar-powers, author updated
- `.claude-plugin/marketplace.json` — Rebranded to stellar-powers, author updated
- `README.md` — Rewritten for Stellar Powers

### Unchanged

- All SKILL.md files (dispatch logic unchanged)
- `skills/subagent-driven-development/implementer-prompt.md` (no good persona match)
- `skills/subagent-driven-development/code-quality-reviewer-prompt.md` (delegates to code-reviewer.md)
- All other skills, hooks, scripts, and configurations

### Based On

- Superpowers v5.0.5 by Jesse Vincent
- Agency-Agents by Mike Sitarzewski

---

For Superpowers release history prior to this fork, see the [upstream release notes](https://github.com/obra/superpowers/blob/main/RELEASE-NOTES.md).
