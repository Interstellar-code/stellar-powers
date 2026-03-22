# Implementation Plan: Stellar Powers v2.0

**Author:** Rohit Sharma
**Status:** In Progress
**Created:** 2026-03-01
**Updated:** 2026-03-22

This plan covers the full implementation of Stellar Powers v2.0, including
closed-loop workflow tracking, HUD metrics enrichment, and SDD batching improvements.

## Phase 1: Foundation

### Task 1: Repository Setup

Initialize the repository structure and configure CI/CD pipelines.

Steps:
- Create directory layout per spec
- Configure GitHub Actions workflows
- Set up branch protection rules
- Add pre-commit hooks for linting

Expected output: Green CI on main branch within 1 day.

### Task 2: Dependency Audit

Review all current dependencies for security vulnerabilities and version drift.

Run `npm audit` and `pip-audit` on all packages. Flag anything with a CVSS score
above 7.0 for immediate patching. Lower severity items go into the backlog.

Expected output: Audit report in `docs/audit-2026-03.md`.

### Task 3: Core Hook Infrastructure

Implement the PostToolUse and SessionStart hooks that feed workflow.jsonl.

#### Task 3: Subtask A — Hook Registration

Register hooks in hooks/hooks.json pointing to handler scripts. Each hook
must declare its event type, handler path, and timeout.

#### Task 3: Subtask B — Event Schema

Define the JSONL event schema. Each line must include:
- `event_type`: string identifier
- `timestamp`: ISO 8601
- `session_id`: UUID
- `tool_name`: name of invoked tool (PostToolUse only)
- `metadata`: arbitrary key-value pairs

#### Task 3: Subtask C — Integration Tests

Write integration tests that fire mock hook events and assert workflow.jsonl
is written correctly.

### Task 4: Metrics Packager

Build `scripts/metrics-packager.py` to bundle workflow events for upload.

The packager must support:
- `--partial` flag for mid-workflow snapshots
- `--stage NAME` to label the current stage
- `--prune` to remove events older than 30 days

### Task 5: HUD Metrics Enrichment

Enrich captured metrics with HUD data: context percentage, tool invocation
counts, step progress (N of M), and total session duration.

Reference: https://github.com/jarrodwatts/claude-hud

#### Task 5: Subtask A — Context Tracking

Hook into the session context size API to capture context % at each tool call.

#### Task 5: Subtask B — Tool Count Aggregation

Aggregate tool call counts per session, broken down by tool name.

### Task 6: SDD Persona Dispatch

Refactor the SDD persona dispatch to batch small mechanical tasks instead of
spawning one agent per task.

Batching criteria:
- Task touches 1-2 files only
- Estimated token count < 20k
- No external tool calls required

### Task 7: Feedback Pipeline

Wire up `/stellar-powers:send-feedback` to file GitHub issues with structured
skill-feedback labels.

The issue body must include:
- Workflow summary (stage durations)
- Tool call histogram
- Context utilization curve
- Suggested improvement areas

### Task 8: Self-Improving Agent

Implement `/self-improving-agent` local skill that reads feedback issues,
proposes fixes on the `autoresearch` branch, and runs eval before/after.

#### Task 8: Subtask A — Issue Ingestion

Fetch all open issues with label `skill-feedback` from the GitHub API.
Parse the structured body into a Python dict for downstream processing.

#### Task 8: Subtask B — Proposal Generation

For each feedback item, prompt Claude to generate a skill patch. The patch
must be a valid unified diff applicable with `git apply`.

#### Task 8: Subtask C — Eval Harness

Run the existing test suite before and after applying each patch. Record
pass/fail counts and surface regressions.

### Task 9: Release Automation

Automate version bumping across all 5 manifest files using a single script.

The script takes `--bump patch|minor|major` and updates:
- `package.json`
- `gemini-extension.json`
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `.cursor-plugin/plugin.json`

### Task 10: Documentation Refresh

Update all user-facing documentation to reflect v2.0 changes.

### Task 10: Subsection — API Reference

Generate API reference docs from docstrings using pdoc3.

### Task 11: Performance Benchmarks

Establish baseline performance benchmarks for hook latency and packager throughput.

Target SLOs:
- Hook dispatch: < 50ms p99
- Packager run: < 2s for 10k events
- Section extraction: < 10ms per file

### Task 12: GA Release

Tag v2.0.0, publish GitHub release, clear plugin cache, announce in Discord.

Checklist:
- [ ] All tests green
- [ ] Docs updated
- [ ] Version bumped in all 5 manifests
- [ ] Release notes drafted
- [ ] Plugin cache cleared
