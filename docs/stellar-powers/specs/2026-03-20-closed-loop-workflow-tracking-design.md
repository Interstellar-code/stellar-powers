# Closed-Loop Workflow Tracking System

**Date:** 2026-03-20
**Status:** Design approved
**Version:** stellar-powers v1.0.6 (target)

## Problem

Stellar-powers skills and persona templates rely on prompt-level enforcement (HARD-GATE, MANDATORY directives). Agents can bypass these. There is no persistent state across sessions, so incomplete work (unfinished specs, abandoned plans, in-progress reviews) is invisible when a new session starts. There is no audit trail of what skills were invoked, which personas were used, or whether compliance was maintained.

Three problems, one system:

1. **Compliance enforcement** — Prove that subagents actually used persona templates
2. **Session continuity** — Resume incomplete work across Claude Code sessions
3. **Self-awareness** — Skills check what's already in-flight before starting new work

## Approach: Hybrid (Hooks + Skills)

Hooks handle automatic, low-level logging and enforcement. Skills handle rich, semantic event logging at meaningful milestones. Each layer does what it's naturally suited for.

- **Hooks log**: agent dispatches, persona violations, skill invocations, task state changes
- **Skills log**: spec creation, review verdicts (with iteration count, reviewer persona, verdict)

## Directory Structure

In each user project where stellar-powers is active:

```
.stellar-powers/
├── workflow.jsonl          # Append-only event log
├── specs/                  # Design specs
└── plans/                  # Implementation plans
```

- Committed to git by default; users can gitignore if preferred
- Replaces `docs/stellar-powers/specs/` and `docs/stellar-powers/plans/` paths

### Path Migration

All skill templates that reference `docs/stellar-powers/specs/` or `docs/stellar-powers/plans/` are updated to `.stellar-powers/specs/` and `.stellar-powers/plans/` respectively.

## Component 1: JSONL Event Registry

### Schema

Every line in `workflow.jsonl` is a JSON object with a common envelope:

```json
{
  "ts": "2026-03-20T14:30:00Z",
  "event": "<event_type>",
  "session": "<claude-session-id-if-available>",
  "data": { ... }
}
```

### Event Types

| Event | Source | Data fields |
|-------|--------|------------|
| `skill_invocation` | Hook | `skill`, `args` |
| `agent_dispatch` | Hook | `persona`, `task`, `model`, `has_persona_template` |
| `spec_created` | Skill | `path`, `skill`, `topic` |
| `review_verdict` | Skill | `verdict`, `reviewer_persona`, `iteration`, `spec_path` |
| `task_state_change` | Hook | `task_id`, `subject`, `from_status`, `to_status` |
| `hook_violation` | Hook | `type`, `tool_input_summary`, `reason` |

### Staleness

Events older than 30 days are excluded from session-start summaries but retained in the JSONL for audit purposes.

## Component 2: Hook Layer

Follows existing stellar-powers hook conventions: bash scripts invoked via `run-hook.cmd`, extensionless filenames, JSON output for context injection.

### PostToolUse Hook (New)

**File:** `hooks/post-tool-use`

Added to `hooks/hooks.json` as a PostToolUse entry. Receives `$TOOL_NAME` and `$TOOL_INPUT` as environment variables.

Behavior by tool:

- **Agent**: Append `agent_dispatch` event. Check tool input for persona template markers (e.g. persona name patterns from the personas catalog). If missing, append `hook_violation` and print warning to stderr.
- **Skill**: Append `skill_invocation` event.
- **TaskCreate/TaskUpdate**: Append `task_state_change` event.
- **All others**: No-op (fast exit).

### SessionStart Hook (Enhanced)

**File:** `hooks/session-start` (existing, extended)

After the current using-stellarpowers context injection, the hook also:

1. Checks if `.stellar-powers/workflow.jsonl` exists in the working directory
2. Parses recent events to identify incomplete work:
   - `skill_invocation` without a corresponding completion (spec created, review approved)
   - `spec_created` without a subsequent `review_verdict(approved)`
   - `task_state_change` to `in_progress` without a later `completed`
3. Injects a summary into session context:

```
Stellar Powers — Incomplete work detected:
  - brainstorming: spec written (2026-03-18) but review not approved
    -> .stellar-powers/specs/2026-03-18-auth-redesign-design.md
  - executing-plans: 3/7 tasks completed (2026-03-19)
    -> .stellar-powers/plans/2026-03-19-auth-redesign.md

Resume, abandon, or start fresh?
```

### File Structure (plugin repo)

```
hooks/
├── hooks.json              # Updated: add PostToolUse entry
├── run-hook.cmd            # Existing polyglot wrapper (unchanged)
├── session-start           # Enhanced with workflow summary
└── post-tool-use           # New: event logging + persona enforcement
```

## Component 3: Skill Integration

Skills add lightweight logging instructions at key milestones. No new infrastructure — skills instruct the agent to append a JSON line to `workflow.jsonl` using Bash at the appropriate moment.

### Per-skill changes

| Skill | Logging added |
|-------|--------------|
| `brainstorming` | `spec_created` after writing spec |
| `writing-plans` | `spec_created` after writing plan |
| `requesting-code-review` | `review_verdict` after each review iteration |
| `executing-plans` | `task_state_change` as plan items complete |
| `subagent-driven-development` | `review_verdict` for spec/code reviews |

Other skills get `skill_invocation` logging automatically via the PostToolUse hook — no template changes needed.

### Incomplete work detection (skill preamble)

Each skill that logs events gets a preamble instruction:

> Before starting, check if `.stellar-powers/workflow.jsonl` exists. If it contains incomplete work related to this skill, present a summary and ask: "Resume, abandon, or start fresh?"

This makes skills self-aware of prior session state.

## What Changes in the Plugin Repo

### New files
- `hooks/post-tool-use` — PostToolUse hook script

### Modified files
- `hooks/hooks.json` — add PostToolUse entry
- `hooks/session-start` — add workflow summary injection
- `skills/brainstorming/SKILL.md` — add spec_created logging + preamble
- `skills/writing-plans/SKILL.md` — add spec_created logging + preamble
- `skills/requesting-code-review/SKILL.md` — add review_verdict logging + preamble
- `skills/executing-plans/SKILL.md` — add task_state_change logging + preamble
- `skills/subagent-driven-development/SKILL.md` — add review_verdict logging + preamble
- All skills referencing `docs/stellar-powers/specs/` or `docs/stellar-powers/plans/` — path updates

### No changes
- `run-hook.cmd` — unchanged
- Persona files — unchanged
- `package.json` — version bump only
