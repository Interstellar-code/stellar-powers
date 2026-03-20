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

- **Hooks log**: agent dispatches, persona violations
- **Skills log**: skill invocation (with workflow_id), spec/plan creation, review verdicts, workflow abandonment

Note: Hook-based `skill_invocation` logging was considered but dropped. The `Skill` tool name needs verification against Claude Code's actual tool naming, and skills already log their own invocation with richer context (workflow_id, args). Avoiding duplicate events from both hook and skill layers.

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

### Directory Initialization

The `.stellar-powers/` directory and its subdirectories (`specs/`, `plans/`) are created by skills on first use. When a skill needs to write a spec, plan, or workflow event, it creates the directory structure if it doesn't exist:

```
mkdir -p .stellar-powers/specs .stellar-powers/plans
```

The `post-tool-use` hook also creates `.stellar-powers/` before writing to `workflow.jsonl` if it doesn't exist.

### Path Migration

All skill templates that reference `docs/stellar-powers/specs/` or `docs/stellar-powers/plans/` are updated to `.stellar-powers/specs/` and `.stellar-powers/plans/` respectively.

**Breaking change:** Existing users may have specs and plans at the old paths. The session-start hook checks for files at the old `docs/stellar-powers/` paths and, if found, injects a one-time migration notice:

```
Stellar Powers: Specs/plans path changed from docs/stellar-powers/ to .stellar-powers/.
Found existing files at old path. Run: mv docs/stellar-powers/specs/* .stellar-powers/specs/ && mv docs/stellar-powers/plans/* .stellar-powers/plans/
```

## Component 1: JSONL Event Registry

### Schema

Every line in `workflow.jsonl` is a JSON object with a common envelope:

```json
{
  "ts": "2026-03-20T14:30:00Z",
  "event": "<event_type>",
  "workflow_id": "<uuid-correlating-related-events>",
  "session": "<claude-session-id-if-available>",
  "data": { ... }
}
```

### Correlation

The `workflow_id` field links related events across a workflow. Skills own the workflow_id lifecycle:

1. On skill invocation, the skill instructs the agent to generate a UUID: `uuidgen` (macOS/Linux) or `python3 -c "import uuid; print(uuid.uuid4())"` as fallback
2. The skill template instructs the agent to store this UUID in a shell variable and reuse it for all subsequent JSONL appends within that workflow (spec creation, review verdicts, etc.)
3. Agent dispatches logged by the hook do NOT get their own workflow_id — they use an empty string. The hook cannot know which skill workflow triggered the dispatch. This is acceptable because the hook's primary job is compliance detection (persona presence), not workflow correlation.

The session-start summary correlates events by `workflow_id` for skill-sourced events, and treats hook-sourced `agent_dispatch` events as standalone audit entries.

### Event Types

| Event | Source | Data fields |
|-------|--------|------------|
| `skill_invocation` | Skill | `skill`, `args`, `workflow_id` |
| `agent_dispatch` | Hook | `persona`, `task`, `model`, `has_persona_template` (envelope `workflow_id` set to `""`) |
| `spec_created` | Skill | `path`, `skill`, `topic`, `workflow_id` |
| `plan_created` | Skill | `path`, `skill`, `topic`, `workflow_id` |
| `review_verdict` | Skill | `verdict`, `reviewer_persona`, `iteration`, `spec_path`, `workflow_id` |
| `workflow_abandoned` | Skill | `workflow_id`, `reason` |
| `hook_violation` | Hook | `type`, `tool_input_summary`, `reason` |

Note: `task_state_change` events were removed. The codebase uses `TodoWrite`/`TodoRead` (not `TaskCreate`/`TaskUpdate`), and these tools don't appear in Claude Code's hook matcher system. Task state is already visible in plan files.

### Staleness

Events older than 30 days are excluded from session-start summaries but retained in the JSONL for audit purposes.

## Component 2: Hook Layer

Follows existing stellar-powers hook conventions: bash scripts invoked via `run-hook.cmd`, extensionless filenames, JSON output for context injection.

### PostToolUse Hook (New)

**File:** `hooks/post-tool-use`

Added to `hooks/hooks.json` as a PostToolUse entry. The matcher targets only the `Agent` tool — the only tool the hook needs to observe:

```json
"PostToolUse": [
  {
    "matcher": "Agent",
    "hooks": [
      {
        "type": "command",
        "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" post-tool-use",
        "async": true
      }
    ]
  }
]
```

The hook receives event data as **JSON on stdin** (Claude Code's hook API contract), containing `session_id`, `cwd`, `hook_event_name`, `tool_name`, and `tool_input`.

The hook reads stdin, parses JSON, and:

1. Creates `.stellar-powers/` in `cwd` if it doesn't exist
2. Appends an `agent_dispatch` event to `workflow.jsonl`
3. Checks `tool_input.prompt` for persona template markers (see Persona Detection below)
4. If no markers found, appends `hook_violation` and prints warning to stderr

### Persona Detection Logic

The hook checks `tool_input.prompt` (the Agent tool's prompt field) for the presence of persona template content. Detection uses a whitelist of marker strings extracted from the persona catalog:

**Required marker:** The prompt must contain at least ONE of these strings (case-insensitive):
- `"You are a"` followed by a persona role name (e.g. `"You are a Software Architect"`)
- `"## Agent Persona Catalog"` (multi-persona template marker)
- `"## Persona Summary"` or `"### Core:"` (single-persona template marker)

**Exempt dispatches** (never flagged as violations):
- `subagent_type` is `Explore` or `Plan` — these are codebase navigation agents, not persona-driven
- `tool_input.prompt` contains `"spec document reviewer"` or `"code quality reviewer"` — these use the built-in reviewer templates

The marker strings are defined as a bash array in the hook script and can be updated as personas evolve.

Note: A **PreToolUse** hook could block persona-less dispatches (exit 2 = deny). However, this risks breaking legitimate non-persona Agent dispatches. We start with PostToolUse (log + warn) and can upgrade to PreToolUse blocking later if needed.

### Error Handling Policy

All hooks follow **silent degradation**:
- If `.stellar-powers/` doesn't exist: create it on first write
- If `workflow.jsonl` is missing: create it on first write, skip reads silently
- If `workflow.jsonl` is malformed/unreadable: skip parsing, log nothing, exit 0
- If JSON parsing of stdin fails: exit 0 silently (do not block the tool call)
- Hooks must never exit non-zero except for intentional PreToolUse denials
- The `set -euo pipefail` pattern from `session-start` is NOT used in `post-tool-use` — errors are caught and swallowed individually

### SessionStart Hook (Enhanced)

**File:** `hooks/session-start` (existing, extended)

After the current using-stellarpowers context injection, the hook also:

1. Checks for old-path files at `docs/stellar-powers/specs/` or `docs/stellar-powers/plans/` — if found, inject migration notice
2. Checks if `.stellar-powers/workflow.jsonl` exists in the working directory (if not, skip silently)
3. Parses recent events to identify incomplete work (if parse fails, skip silently) using the completion rules table below
4. Injects a summary into session context with the incomplete work and instructions

#### Workflow Completion Rules

The session-start hook uses these rules to determine if a workflow is incomplete:

| Start event | Completed when | Example |
|-------------|---------------|---------|
| `skill_invocation` where `skill=brainstorming` | Same `workflow_id` has `review_verdict` with `verdict=approved` | Brainstorming started but spec not reviewed |
| `skill_invocation` where `skill=writing-plans` | Same `workflow_id` has `plan_created` | Plan skill started but no plan written |
| `spec_created` | Same `workflow_id` has `review_verdict` with `verdict=approved` | Spec written but not approved |
| `plan_created` | Same `workflow_id` has a `skill_invocation` for `executing-plans` | Plan written but not started |
| `workflow_abandoned` | Workflow is terminal — always complete | N/A |

Workflows with a `workflow_abandoned` event are never surfaced as incomplete.

#### Session-start output format

```
Stellar Powers — Incomplete work detected:
  - brainstorming [abc-123]: spec written (2026-03-18) but review not approved
    -> .stellar-powers/specs/2026-03-18-auth-redesign-design.md
  - writing-plans [def-456]: plan not yet written (2026-03-19)

  To resume a workflow, invoke the relevant skill — it will pick up from workflow.jsonl.
  To abandon, tell Claude: "abandon workflow [workflow_id]"
```

The skill preamble does NOT re-ask "resume/abandon/start fresh?" — the session-start hook is the single point of contact for surfacing incomplete work. Skills only check workflow.jsonl to load context for an active workflow, not to prompt the user again.

### File Structure (plugin repo)

```
hooks/
├── hooks.json              # Updated: add PostToolUse entry
├── run-hook.cmd            # Existing polyglot wrapper (unchanged)
├── session-start           # Enhanced with workflow summary + migration notice
└── post-tool-use           # New: agent dispatch logging + persona enforcement
```

## Component 3: Skill Integration

Skills add lightweight logging instructions at key milestones. No new infrastructure — skills instruct the agent to append a JSON line to `workflow.jsonl` using Bash at the appropriate moment.

### UUID generation

Skills include this instruction in their preamble:

> Generate a workflow ID for this session: `WF_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")`
> Use this `$WF_ID` value in all workflow.jsonl appends for this skill invocation.

### Per-skill changes

| Skill | Events logged |
|-------|--------------|
| `brainstorming` | `skill_invocation` on entry, `spec_created` after writing spec |
| `writing-plans` | `skill_invocation` on entry, `plan_created` after writing plan |
| `requesting-code-review` | `skill_invocation` on entry, `review_verdict` after each review iteration |
| `executing-plans` | `skill_invocation` on entry |
| `subagent-driven-development` | `skill_invocation` on entry, `review_verdict` for spec/code reviews |

### Workflow abandonment

When a user says "abandon workflow [workflow_id]", any active skill (or a general instruction in using-stellarpowers) appends:

```json
{"ts":"...","event":"workflow_abandoned","workflow_id":"<id>","data":{"reason":"user requested"}}
```

This is documented in the using-stellarpowers skill so the agent knows how to handle the command regardless of which skill is active.

### Skill preamble (context loading, not prompting)

Each instrumented skill gets a preamble:

> On invocation, check if `.stellar-powers/workflow.jsonl` exists. If it contains events with the same skill name that are not yet completed (per the completion rules), load the most recent workflow's context (spec path, plan path, last event) to inform your work. Do not prompt the user — session-start already surfaced incomplete work at the top of this session.

## What Changes in the Plugin Repo

### New files
- `hooks/post-tool-use` — PostToolUse hook script for agent dispatch logging + persona enforcement

### Modified files
- `hooks/hooks.json` — add PostToolUse entry
- `hooks/session-start` — add workflow summary injection + old-path migration notice
- `skills/brainstorming/SKILL.md` — add workflow logging (skill_invocation, spec_created) + preamble
- `skills/brainstorming/spec-document-reviewer-prompt.md` — path update to `.stellar-powers/specs/`
- `skills/writing-plans/SKILL.md` — add workflow logging (skill_invocation, plan_created) + preamble + path update
- `skills/requesting-code-review/SKILL.md` — add workflow logging (skill_invocation, review_verdict) + preamble + path update
- `skills/executing-plans/SKILL.md` — add workflow logging (skill_invocation) + preamble
- `skills/subagent-driven-development/SKILL.md` — add workflow logging (skill_invocation, review_verdict) + preamble + path update
- `skills/using-stellarpowers/SKILL.md` — add "abandon workflow" command documentation

### No changes
- `run-hook.cmd` — unchanged
- Persona files — unchanged
- `package.json` — version bump only
