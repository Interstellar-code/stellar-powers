# Stellar Powers MVP: Agency-Agents Persona Integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans

## Summary

Enhance superpowers' existing subagent prompts with curated persona content from the [agency-agents](https://github.com/msitarzewski/agency-agents) library. No rebrand, no new roles, no structural changes to superpowers — just higher-quality subagent output through richer persona definitions.

## Goals

1. Improve subagent review quality by injecting domain-expert personas into existing prompt templates
2. Download and maintain the full agency-agents library locally for future expansion
3. Keep all existing superpowers mechanisms and dispatch logic unchanged

## Non-Goals (MVP)

- Rebranding (`superpowers:` prefix stays)
- Adding new subagent roles
- Changing SKILL.md dispatch logic
- Modifying the implementer prompt
- Changing the plugin manifest

## Architecture

### Repository Setup

- Git fork of `obra/superpowers` on GitHub
- Clone into `/Users/rohits/dev/stellar-powers/`
- Install as local Claude Code plugin for testing

### File Structure

```
stellar-powers/
├── personas/
│   ├── catalog.md                          # curated master table (~8-10 personas, ~60-80 lines)
│   ├── curated/                            # trimmed excerpts for prompt injection
│   │   ├── software-architect.md           # ~20-30 lines each
│   │   ├── code-reviewer.md
│   │   ├── security-engineer.md
│   │   ├── senior-project-manager.md
│   │   ├── incident-response-commander.md
│   │   ├── backend-architect.md
│   │   ├── sprint-prioritizer.md
│   │   └── devops-automator.md
│   └── source/                             # full agency-agents library (all 144+ agents)
│       ├── academic/
│       ├── design/
│       ├── engineering/
│       ├── game-development/
│       ├── marketing/
│       ├── paid-media/
│       ├── product/
│       ├── project-management/
│       ├── sales/
│       ├── spatial-computing/
│       ├── specialized/
│       ├── support/
│       └── testing/
├── skills/                                 # 5 prompt templates modified
│   ├── brainstorming/
│   │   └── spec-document-reviewer-prompt.md
│   ├── writing-plans/
│   │   └── plan-document-reviewer-prompt.md
│   ├── subagent-driven-development/
│   │   ├── implementer-prompt.md              # UNCHANGED
│   │   ├── spec-reviewer-prompt.md
│   │   └── code-quality-reviewer-prompt.md
│   └── requesting-code-review/
│       └── code-reviewer.md
└── ... (everything else unchanged)
```

## Two Enhancement Strategies

### Strategy 1: Multi-Persona Catalog (Review/Planning Subagents)

**Applies to:**
- `spec-document-reviewer-prompt.md` (brainstorming)
- `plan-document-reviewer-prompt.md` (writing-plans)

**Approach:** Prepend the full `personas/catalog.md` content with a framing instruction:

```markdown
## Multi-Domain Review Perspectives
You have access to multiple expert perspectives. Apply relevant lenses based on
what the spec/plan covers. You don't need to use all — pick what's relevant.

[catalog.md content: table + 2-3 line summaries per persona]
---
[existing superpowers prompt unchanged]
```

**Rationale:** These subagents review broad documents (specs, plans) that span multiple domains. A multi-persona lens lets them catch architecture issues, security gaps, scope creep, and task decomposition problems in a single pass.

### Strategy 2: Single-Persona Injection (Technical Subagents)

**Applies to:**
- `spec-reviewer-prompt.md` → Software Architect persona
- `code-quality-reviewer-prompt.md` → Code Reviewer persona
- `code-reviewer.md` → Code Reviewer persona

**Approach:** Prepend a curated ~20-30 line excerpt from the matching `personas/curated/*.md` file:

```markdown
## Agent Persona
You are a [Role]. [Vibe line].

### Core Mission
- [3-5 bullets]

### Critical Rules
- [3-5 bullets]
---
[existing superpowers prompt unchanged]
```

**Rationale:** These subagents have a focused, single-domain task. One strong persona sets the right mindset without diluting focus. The existing superpowers prompt handles task structure, report format, and escalation criteria.

## Persona-to-Subagent Mapping

| Subagent | Strategy | Persona Source | Agency-Agents File |
|---|---|---|---|
| Spec Document Reviewer | Multi-Persona Catalog | All ~8-10 | catalog.md |
| Plan Document Reviewer | Multi-Persona Catalog | All ~8-10 | catalog.md |
| Spec Reviewer | Single Persona | Software Architect | engineering-software-architect.md |
| Code Quality Reviewer | Single Persona | Code Reviewer | engineering-code-reviewer.md |
| Code Reviewer | Single Persona | Code Reviewer | engineering-code-reviewer.md |
| Implementer | SKIP | — | — |

## Curated Persona Catalog Contents

The catalog includes these ~8-10 personas with a routing table and 2-3 line summaries:

| Persona | Source File | Domain Coverage |
|---|---|---|
| Software Architect | engineering-software-architect.md | System design, trade-offs, DDD, C4, ADRs |
| Code Reviewer | engineering-code-reviewer.md | Correctness, security, maintainability, perf |
| Security Engineer | engineering-security-engineer.md | STRIDE, OWASP, zero-trust, secrets mgmt |
| Senior Project Manager | project-manager-senior.md | Task decomposition, acceptance criteria, scope |
| Incident Response Commander | engineering-incident-response-commander.md | Failure modes, observability, runbooks |
| Backend Architect | engineering-backend-architect.md | APIs, databases, scaling, infrastructure |
| Sprint Prioritizer | product-sprint-prioritizer.md | RICE, effort/value, capacity, dependencies |
| DevOps Automator | engineering-devops-automator.md | CI/CD, IaC, deployment, environments |

## Prompt Size Budget

- Single-persona injection: ~20-30 lines prepended
- Multi-persona catalog: ~60-80 lines prepended
- Existing prompt templates: ~40-80 lines each
- Total prompt size after enhancement: ~60-160 lines per subagent

This stays well within subagent context limits and avoids the confusion risk of very long prompts.

## Testing Plan

1. Install stellar-powers as a local Claude Code plugin
2. Run a brainstorming → writing-plans cycle on a real task
3. Observe subagent output for evidence of persona influence (e.g., code reviewer using 🔴/🟡/💭 priority system, spec reviewer evaluating architectural trade-offs)
4. Compare subjective quality before/after

## Future Expansion (Post-MVP)

- Rebrand to `stellar-powers:` prefix
- Add new subagent roles (e.g., Security Reviewer as post-implementation step)
- Curate more personas from the full local library
- Add persona selection logic (dispatch different personas based on task domain)
