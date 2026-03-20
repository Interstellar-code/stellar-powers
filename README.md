# Stellar Powers

Stellar Powers is an enhanced fork of [Superpowers](https://github.com/obra/superpowers) that integrates multi-persona subagent dispatch from [Agency-Agents](https://github.com/msitarzewski/agency-agents) into Claude Code's skills workflow.

## What's Different from Superpowers

Superpowers dispatches generic subagents for code review, spec review, and plan review. Stellar Powers enhances these subagents with curated expert personas — giving each reviewer a domain-specific mindset, concrete review criteria, and structured output formats.

**Multi-persona review subagents** (spec-document-reviewer, plan-document-reviewer) receive a catalog of 8 expert perspectives and systematically apply relevant domain lenses:

| Persona | Domain |
|---|---|
| Software Architect | System design, trade-offs, boundaries, DDD |
| Code Reviewer | Correctness, security, maintainability, performance |
| Security Engineer | STRIDE, OWASP, zero-trust, secrets management |
| Senior Project Manager | Task decomposition, acceptance criteria, scope |
| Incident Response Commander | Failure modes, observability, runbooks |
| Backend Architect | APIs, databases, scaling, infrastructure |
| Sprint Prioritizer | RICE, effort/value, capacity, dependencies |
| DevOps Automator | CI/CD, IaC, deployment, environments |

**Single-persona technical subagents** (spec-reviewer, code-reviewer) receive a focused persona injection that shapes their review approach — for example, the code reviewer uses a priority system with Blockers, Suggestions, and Nits, and includes Security Engineer and Software Architect as supporting lenses.

## How It Works

The core Superpowers workflow is unchanged:

1. **brainstorming** — Refines ideas through questions, explores alternatives, presents design
2. **using-git-worktrees** — Creates isolated workspace on new branch
3. **writing-plans** — Breaks work into bite-sized tasks with exact file paths and code
4. **subagent-driven-development** — Dispatches fresh subagent per task with two-stage review
5. **test-driven-development** — Enforces RED-GREEN-REFACTOR cycle
6. **requesting-code-review** — Reviews against plan, reports issues by severity
7. **finishing-a-development-branch** — Verifies tests, presents merge/PR options

Stellar Powers enhances step 1, 3, and 4 by injecting expert personas into the review subagents dispatched during those steps.

## Installation

### Claude Code

```bash
/plugin https://github.com/Interstellar-code/stellar-powers
```

### Updating

```bash
/plugin update stellar-powers
```

## Project Structure

```
stellar-powers/
├── personas/
│   ├── catalog.md              # Master persona table for multi-domain reviews
│   ├── curated/                # Trimmed persona excerpts (~20-30 lines each)
│   └── source/                 # Full agency-agents library (156 agents)
├── skills/                     # All superpowers skills (enhanced)
├── .claude-plugin/             # Plugin manifest
└── docs/stellar-powers/        # Specs and plans
```

## Credits

- **Superpowers** by [Jesse Vincent](https://github.com/obra/superpowers) — the foundational skills workflow
- **Agency-Agents** by [Mike Sitarzewski](https://github.com/msitarzewski/agency-agents) — the expert persona library
- **Stellar Powers** by [Rohit Sharma](https://github.com/Interstellar-code) at [Interstellar Consulting](https://interstellarconsulting.com)

## License

MIT License — see LICENSE file for details
