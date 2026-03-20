# Stellar Powers Release Notes

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
