# Self-Improving Capabilities for Stellar Powers

**Status:** Design approved
**Date:** 2026-03-21
**Workflow ID:** 8354597C-3008-4FFC-BFC3-8A22C1BCD800

## Inspiration

Andrej Karpathy's [autoresearch](https://github.com/karpathy/autoresearch) — an autonomous loop where an AI agent modifies code, trains for 5 minutes, evaluates via validation loss (bits-per-byte), keeps or discards the change, and repeats (~100 experiments overnight). The key insight: a tight modify → run → evaluate → keep/discard loop with an objective metric drives continuous improvement without human intervention.

## Problem Statement

Stellar Powers skills are used across multiple repositories and scenarios. Each usage generates implicit feedback — workflow completions, abandonments, user corrections, review outcomes — but this data is either not captured or stays siloed in each repo. There is no mechanism to:

1. Collect structured usage feedback from skill executions
2. Aggregate feedback across repositories back to the stellar-powers repo
3. Analyze patterns and propose skill improvements
4. Close the loop so skills get better over time

## Core Concept

A **self-improving feedback loop** for stellar-powers skills, adapted from the autoresearch pattern:

| Autoresearch | Stellar Powers |
|---|---|
| `train.py` (single modification target) | Skill file (e.g., `SKILL.md`) |
| 5-minute training run | N real workflow executions across repos |
| `val_bpb` (objective metric) | Completion rate + correction count + abandonment patterns |
| Agent proposes code change | Dedicated agent proposes skill edits |
| Automatic keep/discard | User approves/rejects (initially); auto-apply for low-risk changes (future) |

## Approach: Skill-Only (Option A)

A new `send-feedback` skill handles feedback submission. Enhanced event capture is added to existing skills via shared utilities. Hooks are added for automatic structural data capture. The session-start hook gets minor enhancements for lifecycle enforcement.

**Why this approach:** Stays within the existing stellar-powers architecture. Skills already log to workflow.jsonl — we're just making them log more. No new infrastructure. Future phases (analysis agent, autonomous improvement) build on top once we prove the data collection works.

**Options considered but deferred:**
- **Dedicated hook layer** — hooks can't capture conversational feedback (user corrections), only tool calls
- **Hybrid agent service** — over-engineered for current stage; adds background process complexity

## Architecture: Cross-Repo Feedback Loop

```
repo-A/.stellar-powers/workflow.jsonl ───┐
repo-B/.stellar-powers/workflow.jsonl ───┼──→ /stellar-powers:send-feedback ──→ GitHub Issues
repo-C/.stellar-powers/workflow.jsonl ───┘    (on stellar-powers repo)
                                                    │
                                              labeled: skill-feedback
                                              one issue per workflow
                                              structured + raw metrics
```

**Flow:**
1. Hooks continuously capture events to workflow.jsonl (automatic)
2. Skills capture semantic events — corrections, review outcomes, step progression (automatic)
3. On workflow completion, user confirms "yes, complete" → metrics packaged automatically
4. User runs `/stellar-powers:send-feedback` when ready → issues filed, metrics cleaned up

## Component 1: Hook-Driven Data Capture

### Available Claude Code Hook Events

Full hook event reference (all events that Claude Code CLI supports):

| Hook Event | Trigger | Key Data Fields |
|---|---|---|
| SessionStart | New session, resume, /clear, compact | source, model |
| InstructionsLoaded | CLAUDE.md loaded | file_path, load_reason |
| UserPromptSubmit | User submits prompt | prompt text |
| PreToolUse | Before tool execution | tool_name, tool_input |
| PermissionRequest | Permission dialog shown | tool_name, tool_input |
| PostToolUse | After tool completion | tool_name, tool_input, tool_response |
| PostToolUseFailure | Tool execution fails | tool_name, error |
| SubagentStart | Subagent spawned | agent_id, agent_type |
| SubagentStop | Subagent finishes | agent_id, agent_type, agent_transcript_path, last_assistant_message |
| Stop | Main agent completes response | last_assistant_message |
| StopFailure | Turn ends due to API error | error, error_details |
| TaskCompleted | Task marked complete | task_id, task_subject, task_description |
| Notification | System notification | message, notification_type |
| ConfigChange | Settings files change | source, file_path |
| WorktreeCreate | Worktree created | name |
| WorktreeRemove | Worktree cleanup | worktree_path |
| PreCompact | Before compaction | trigger, custom_instructions |
| PostCompact | After compaction | trigger, compact_summary |
| SessionEnd | Session terminates | reason |
| TeammateIdle | Teammate about to idle | teammate_name |
| Elicitation | MCP requests user input | mcp_server_name, message |
| ElicitationResult | User responds to MCP | content |

**Important discovery:** All hooks receive `transcript_path` — a path to the full conversation JSON. This means the complete conversation (including AI responses and tool calls) IS accessible during the session via hooks, even though it's not stored permanently in `~/.claude/`.

### Claude Code Data Available at `~/.claude/`

| Source | Contents | Accessible? |
|---|---|---|
| `history.jsonl` | Every user message with timestamp, project path, session ID | Yes — input side only |
| `sessions/*.json` | Minimal metadata: pid, sessionId, cwd, startedAt | Yes — very sparse |
| `tasks/<session>/*.json` | Task state (subject, description, status, dependencies) | Yes |
| `context-mode/sessions/*.db` | Hook-injected context, session resume snapshots | Yes — limited content |
| Full conversation transcripts | AI responses, tool calls, corrections | **Only via `transcript_path` during active hooks** |

### New Hooks to Add

**`UserPromptSubmit` hook** — captures user messages with workflow correlation:
```jsonl
{"event":"user_message","workflow_id":"7DD9E572","data":{"prompt_preview":"you missed the error handling for...","active_skill":"brainstorming","active_step":"spec_review"}}
```
Truncated to first 200 chars. Enough to understand feedback nature without bloating the log.

**`TaskCompleted` hook** — logs every task completion:
```jsonl
{"event":"task_completed","workflow_id":"7DD9E572","data":{"task_id":"3","task_subject":"Implement auth middleware","task_description":"Add JWT validation..."}}
```

**`SubagentStop` hook** — captures subagent outcomes:
```jsonl
{"event":"subagent_completed","workflow_id":"655FD11D","data":{"agent_id":"abc123","agent_type":"implementer","outcome_preview":"Created 3 files, all tests passing..."}}
```
`outcome_preview` extracted from `last_assistant_message` (first 300 chars).

**`Stop` hook** — captures AI's final response per turn:
```jsonl
{"event":"turn_completed","workflow_id":"7DD9E572","data":{"response_preview":"Design section 2 approved. Moving to...","active_skill":"brainstorming"}}
```

**`PostToolUseFailure` hook** — captures failures:
```jsonl
{"event":"tool_failure","workflow_id":"7DD9E572","data":{"tool_name":"Bash","error_preview":"npm test failed: 3 assertions..."}}
```

### How Hooks Know the Active Workflow

Hooks read `.stellar-powers/.active-workflow` to correlate events with the current workflow:

```json
{
  "workflow_id": "7DD9E572",
  "skill": "brainstorming",
  "topic": "feature-porting",
  "step": "spec_review",
  "step_number": 5,
  "started": "2026-03-21T07:01:22Z",
  "repo": "appsfomo",
  "task_type": "feature",
  "sp_version": "1.2.0"
}
```

Skills create and update this file. Hooks read it. This is the bridge between automatic structural capture (hooks) and semantic intentional capture (skills).

### Existing Hooks (enhanced)

**`post-tool-use` (existing)** — already logs agent dispatches and persona violations. No changes needed.

**`session-start` (existing)** — already detects incomplete workflows. Enhanced to check `.active-workflow` for lifecycle enforcement (see Component 3).

## Component 2: Enhanced workflow.jsonl

### Current Event Types (unchanged)

| Event | Source | Data Fields |
|---|---|---|
| `skill_invocation` | Skills | skill, args, workflow_id |
| `spec_created` | Skills | path, skill, topic |
| `plan_created` | Skills | path, skill, topic |
| `handoff_writing_plans` | Skills | spec_path |
| `agent_dispatch` | PostToolUse hook | task, model, persona |
| `hook_violation` | PostToolUse hook | type, reason, summary |
| `review_verdict` | Skills | verdict, reviewer, iteration |

### New Event Types

**From hooks (automatic):**

| Event | Source Hook | Data Fields |
|---|---|---|
| `user_message` | UserPromptSubmit | prompt_preview, active_skill, active_step |
| `task_completed` | TaskCompleted | task_id, task_subject, task_description |
| `subagent_completed` | SubagentStop | agent_id, agent_type, outcome_preview |
| `turn_completed` | Stop | response_preview, active_skill |
| `tool_failure` | PostToolUseFailure | tool_name, error_preview |

**From skills (semantic):**

| Event | Source | Data Fields |
|---|---|---|
| `workflow_started` | Skill entry | skill, topic, repo, task_type, sp_version |
| `step_started` | Skill checklist | skill, step, step_number |
| `step_completed` | Skill checklist | skill, step, step_number |
| `user_correction` | Skill (on user feedback) | skill, context, correction, history_ref |
| `workflow_completed` | Terminal skill | skill, duration_minutes, steps_completed, steps_total, outcome, completion_feedback |
| `workflow_abandoned` | User command | abandoned_at_step, reason |
| `workflow_on_hold` | User choice | held_reason |
| `workflow_summary` | Pruning step | full summary replacing detail lines |
| `feedback_sent` | send-feedback skill | issue_urls, packages_sent |

### Pruning Strategy

**During execution:** Full detail logging — every step, message, task, subagent event.

**After workflow completion:** All detail lines for that workflow_id are replaced with a single `workflow_summary` line:

```jsonl
{"event":"workflow_summary","workflow_id":"7DD9E572","data":{
  "skill_chain":["brainstorming","writing-plans","sdd"],
  "topic":"feature-porting",
  "repo":"appsfomo",
  "task_type":"feature",
  "sp_version":"1.2.0",
  "started":"2026-03-21T07:01:22Z",
  "completed":"2026-03-21T08:45:00Z",
  "duration_minutes":104,
  "outcome":"success",
  "steps_completed":15,
  "steps_total":15,
  "corrections":1,
  "review_iterations":2,
  "violations":0,
  "tasks_completed":5,
  "artifacts":["specs/2026-03-21-feature-porting-design.md","plans/2026-03-21-feature-porting.md"]
}}
```

The detailed events move to the metrics package before pruning. workflow.jsonl stays lean — one line per completed workflow, full detail only for active workflows.

## Component 3: Workflow Lifecycle Management

### The .active-workflow State File

Located at `.stellar-powers/.active-workflow`. Created by skills on invocation, read by hooks for correlation, cleared on completion.

### Skill Invocation Gate

When any stellar-powers skill is invoked, before doing anything else:

1. Check if `.active-workflow` exists
2. If no → proceed normally, create `.active-workflow`
3. If yes, same workflow chain (brainstorming → writing-plans for same topic) → update file, continue
4. If yes, different topic → prompt user:
   ```
   Previous workflow [brainstorming/feature-porting] is still active
   (started 2026-03-21, currently at step: spec_review).

   a) Complete it — mark as done, package metrics
   b) Abandon it — mark as abandoned, package metrics
   c) Hold it — park it, start new workflow
   d) Resume it — continue where you left off
   ```

### Chain Detection

Workflows chain: brainstorming → writing-plans → SDD/executing-plans. The `.active-workflow` file carries forward with the same `workflow_id` and `topic`, only `skill` and `step` fields change.

### Completion Checkpoint

Terminal skills (SDD, executing-plans, TDD, finishing-a-development-branch) ask at their final step:

```
All tasks completed. Is the workflow implementation now complete?

a) Yes, complete — I'll package the metrics and close this workflow
b) Not yet — what's remaining?
c) Complete, and here's my feedback: [user types feedback]
```

On completion:
1. Log `workflow_completed` event with user's feedback
2. Package metrics to `.stellar-powers/metrics/`
3. Prune workflow.jsonl (replace detail lines with summary)
4. Delete `.active-workflow`

### Hold/Park Behavior

If user parks a workflow, `.active-workflow` gets `"status": "on_hold"`. Next skill invocation mentions it briefly ("Note: workflow [feature-porting] is on hold since 2026-03-21") but doesn't block.

## Component 4: Metrics Packaging

### Trigger

Automatic on workflow completion (when user confirms "yes, complete" at the checkpoint). No user action required for packaging — only for sending.

### Package Structure

```json
// .stellar-powers/metrics/2026-03-21-feature-porting-7DD9E572.json
{
  "package_version": "1.0",
  "workflow_id": "7DD9E572",
  "stellar_powers_version": "1.2.0",

  "context": {
    "repo": "appsfomo",
    "project_type": "nextjs-webapp",
    "task_type": "feature",
    "skills_chain": ["brainstorming", "writing-plans", "subagent-driven-development"]
  },

  "timeline": {
    "started": "2026-03-21T07:01:22Z",
    "completed": "2026-03-21T08:45:00Z",
    "duration_minutes": 104,
    "user_confirmed_complete": true
  },

  "skills": {
    "brainstorming": {
      "steps_completed": 6,
      "steps_total": 6,
      "corrections": [
        {"step": "spec_review", "feedback": "missed auth flow for API routes"}
      ],
      "review_iterations": 2,
      "review_verdict": "approved_after_fixes"
    },
    "writing-plans": {
      "steps_completed": 4,
      "steps_total": 4,
      "corrections": [],
      "review_iterations": 1,
      "review_verdict": "approved"
    },
    "subagent-driven-development": {
      "tasks_total": 5,
      "tasks_completed": 5,
      "violations": [{"type": "missing_persona_template", "count": 3}],
      "review_verdicts": ["approved", "approved_after_fixes", "approved"]
    }
  },

  "tasks": [
    {"id": "1", "subject": "Create scanner-prompt.md", "status": "completed"},
    {"id": "2", "subject": "Create SKILL.md", "status": "completed"},
    {"id": "3", "subject": "Modify brainstorming SKILL.md", "status": "completed"}
  ],

  "user_messages": [
    {"timestamp": "2026-03-21T07:10:00Z", "context": "brainstorming/clarifying_questions", "preview": "Yes Option A with confirmation of the target tech stack"},
    {"timestamp": "2026-03-21T07:22:00Z", "context": "brainstorming/spec_review", "preview": "missed auth flow for API routes"}
  ],

  "ai_responses": [
    {"timestamp": "2026-03-21T07:25:00Z", "context": "brainstorming/spec_review", "preview": "Updated spec to include auth flow..."},
    {"timestamp": "2026-03-21T08:40:00Z", "context": "sdd/final_task", "preview": "All 5 tasks completed, tests passing..."}
  ],

  "tool_failures": [],

  "completion_feedback": "worked well but brainstorming step was too verbose on the approaches section"
}
```

### Directory Structure

```
.stellar-powers/
├── workflow.jsonl              # live event stream (pruned on completion)
├── .active-workflow            # current workflow state (transient)
├── metrics/                    # packaged metrics awaiting send-feedback
│   ├── 2026-03-21-feature-porting-7DD9E572.json
│   └── 2026-03-21-sdd-batching-1D06F239.json
├── specs/
└── plans/
```

## Component 5: Send-Feedback Skill

### Invocation

`/stellar-powers:send-feedback`

A dedicated skill at `skills/send-feedback/SKILL.md`.

### Flow

1. Scan `.stellar-powers/metrics/` for package files
2. If empty: "No pending feedback to send."
3. For each package:
   a. Read metrics JSON
   b. Light analysis pass — summarize patterns, extract key corrections, calculate stats
   c. Create GitHub issue on stellar-powers repo via `gh` CLI:
      ```
      Title: [skill-feedback] brainstorming + SDD: feature-porting (appsfomo)
      Labels: skill-feedback, brainstorming, sdd

      Body:
      ## Skill Feedback: feature-porting workflow
      **Repo:** appsfomo | **Type:** nextjs-webapp | **Version:** 1.2.0
      **Duration:** 104 min | **Skills:** brainstorming → writing-plans → SDD
      **Outcome:** Completed successfully

      ### Key Corrections
      - Brainstorming/spec_review: "missed auth flow for API routes"

      ### Patterns
      - Spec reviewer needed 2 iterations (approved_after_fixes)
      - 3 persona template violations during SDD

      ### User Feedback
      "brainstorming step was too verbose on the approaches section"

      <details><summary>Raw Metrics</summary>
      ```json
      {full metrics JSON}
      ```
      </details>
      ```
   d. Confirm issue created (show URL)
   e. Delete metrics file
4. Log `feedback_sent` event to workflow.jsonl
5. Report: "N issues created on stellar-powers: [URLs]"

### Prerequisites

- `gh` CLI authenticated with access to stellar-powers repo
- Metrics packages exist in `.stellar-powers/metrics/`

## Component 6: Changes to Existing Skills

### Shared Utilities

```
skills/
├── _shared/
│   ├── lifecycle.sh          # workflow gate, .active-workflow management, step logging
│   └── metrics-packager.sh   # package metrics, prune workflow.jsonl on completion
├── brainstorming/
├── writing-plans/
├── send-feedback/            # NEW
...
```

### All Skills (common changes)

1. **On entry:** Read/create `.active-workflow`, handle invocation gate
2. **At each checklist step:** Log `step_started` and `step_completed` events
3. **On user corrections:** Log `user_correction` event with preview and timestamp

### Terminal Skills (completion checkpoint)

Skills that end a workflow chain — ask "Is the workflow implementation now complete?" at final step:
- subagent-driven-development
- executing-plans
- test-driven-development
- finishing-a-development-branch

On completion: log event, package metrics, prune workflow.jsonl, clear `.active-workflow`.

### Handoff Skills (chain to next)

Skills that chain to the next skill — update `.active-workflow` but don't trigger packaging:
- brainstorming → writing-plans
- writing-plans → SDD or executing-plans

## Component 7: Measuring Improvement

Each metrics package captures `stellar_powers_version`. When a skill change is made in v1.3.0 based on feedback from v1.2.0, subsequent feedback from v1.3.0 carries that version tag. Comparison across versions reveals whether changes helped:

```
v1.2.0: brainstorming spec_review corrections in 4/6 workflows
v1.3.0: brainstorming spec_review corrections in 1/6 workflows → improvement confirmed
```

Key metrics to compare across versions:
- Correction count per skill per step
- Workflow completion rate (completed vs abandoned)
- Review iteration count (fewer = better)
- Hook violation count (should trend to zero)
- User completion feedback sentiment

## Future Work (documented, not in scope)

### Phase 2: Analysis Agent

A skill on the stellar-powers repo: `/stellar-powers:analyze-feedback`
- Reads all open `skill-feedback` issues via `gh` CLI
- Groups by skill, extracts patterns across issues
- Proposes specific skill edits with confidence levels
- User approves → agent makes edits
- Processed issues closed as "incorporated"

### Phase 3: Autonomous Self-Improvement

- Low-risk changes (rewording, checklist additions) auto-applied via PR
- Structural changes (new steps, flow changes) require approval
- Each change tagged with which feedback issues drove it — full traceability
- The autoresearch loop realized: collect feedback → analyze → propose → apply → measure → repeat

### Phase 4: Multi-User

- `auto_send_feedback` config flag (default false for other users)
- Anonymized repo identifiers
- Aggregated patterns across users
- Synthetic benchmarks grounded in real failure modes from collected feedback
