# Stellar Powers — Claude Code Plugin

Enhanced skills library for Claude Code with multi-persona subagent dispatch.

## Project Structure

- `skills/` — Skill definitions (each has SKILL.md + optional references/)
- `skills/_shared/` — Shared reference docs (snippets.md)
- `hooks/` — Claude Code hooks (session-start, post-tool-use, etc.)
- `personas/` — Subagent persona definitions
- `personas/curated/` — 8 curated personas used by SDD persona injection
- `agents/` — Agent configurations
- `commands/` — CLI command definitions
- `.claude-plugin/` — Plugin manifest (plugin.json, marketplace.json)
- `tests/` — Test suites organized by feature
- `scripts/` — Utility scripts (metrics-packager.py)
- `.claude/skills/` — LOCAL skills (not shipped with plugin) — self-improving-agent
- `.claude/tests/` — Eval scenarios for self-improving system

## Testing

```bash
# Run all tests (42 tests + 7 scenarios)
bash tests/test-self-improving.sh
python3 .claude/tests/run-scenarios.py
```

## Release

Version must be bumped in ALL 5 manifest files:
- `package.json`
- `gemini-extension.json`
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `.cursor-plugin/plugin.json`

Then: `git push && git tag vX.Y.Z && git push origin vX.Y.Z && gh release create vX.Y.Z`
Clear plugin cache after release: `rm -rf ~/.claude/plugins/cache/stellar-powers/`

## Key Conventions

- Skills are defined in `skills/<name>/SKILL.md` with optional `references/` subdirectory
- Hooks use JSON config in `hooks/hooks.json` pointing to handler scripts in subdirectories
- Workflow metrics are tracked in `.stellar-powers/workflow.jsonl` (per-project, gitignored)
- When modifying skills, always run the relevant test suite before committing

## Gotchas

- `CLAUDE_PLUGIN_ROOT` env var is ONLY available in hooks, NOT in bash commands run by skills. Use `find ~/.claude/plugins/cache/stellar-powers -name "file" -maxdepth 5` instead.
- Agents skip long inline Python heredocs in skills. Use standalone scripts in `scripts/` with one-liner calls.
- Agents skip optional-looking instructions. Use HARD-GATE blocks and MANDATORY labels for enforcement.
- After plugin update, existing sessions have stale hook paths — start a new session.
- Run `bash tests/test-self-improving.sh && python3 .claude/tests/run-scenarios.py` before every release.

## Self-Improving System

- Hooks capture workflow events to `.stellar-powers/workflow.jsonl` on consumer repos
- `/stellar-powers:send-feedback` files metrics as GitHub issues on this repo
- `/self-improving-agent` (local skill) analyzes issues, proposes fixes on autoresearch branch, evals before/after
- `scripts/metrics-packager.py` — standalone packager (supports --partial --stage NAME and --prune)
- Feedback issues use `skill-feedback` label
