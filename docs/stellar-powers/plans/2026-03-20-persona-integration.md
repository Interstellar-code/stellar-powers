# Persona Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enhance superpowers subagent prompts with curated agency-agents personas for higher-quality review output.

**Architecture:** Fork superpowers, download agency-agents source files locally, create curated persona excerpts, prepend persona sections to 5 existing prompt templates (2 multi-persona, 3 single-persona).

**Tech Stack:** Markdown prompt templates, git, GitHub CLI

---

### Task 1: Fork and Clone Superpowers

**Files:**
- Create: entire repo at `/Users/rohits/dev/stellar-powers/` (fork clone)

- [ ] **Step 1: Fork superpowers on GitHub**

```bash
gh repo fork obra/superpowers --clone=false
```

- [ ] **Step 2: Clone the fork into the project directory**

```bash
cd /Users/rohits/dev/stellar-powers
# If directory has existing files, init git and add fork as remote
git init
git remote add origin https://github.com/rohitsharma-7/superpowers.git
git remote add upstream https://github.com/obra/superpowers.git
git fetch upstream
git checkout -b main upstream/main
git push -u origin main
```

Note: Adjust GitHub username if different from `rohitsharma-7`. The key requirement is that the fork's content lands in `/Users/rohits/dev/stellar-powers/`.

- [ ] **Step 3: Verify the clone has the expected structure**

```bash
ls skills/
# Expected: brainstorming/ dispatching-parallel-agents/ executing-plans/ ... writing-plans/
ls skills/subagent-driven-development/
# Expected: SKILL.md implementer-prompt.md spec-reviewer-prompt.md code-quality-reviewer-prompt.md
```

- [ ] **Step 4: Commit checkpoint**

No commit needed — this is a clean clone.

---

### Task 2: Download Agency-Agents Source Files

**Files:**
- Create: `personas/source/` directory with all agency-agents persona files

- [ ] **Step 1: Clone agency-agents into a temp directory**

```bash
git clone https://github.com/msitarzewski/agency-agents.git /tmp/agency-agents
```

- [ ] **Step 2: Copy all persona directories into `personas/source/`**

```bash
cd /Users/rohits/dev/stellar-powers
mkdir -p personas/source
# Copy all division directories containing agent markdown files
for dir in academic design engineering game-development marketing paid-media product project-management sales spatial-computing specialized support testing; do
  if [ -d "/tmp/agency-agents/$dir" ]; then
    cp -r "/tmp/agency-agents/$dir" personas/source/
  fi
done
```

- [ ] **Step 3: Verify the download**

```bash
find personas/source -name "*.md" | wc -l
# Expected: ~144+ files
ls personas/source/engineering/
# Expected: engineering-software-architect.md, engineering-code-reviewer.md, etc.
```

- [ ] **Step 4: Clean up temp directory**

```bash
rm -rf /tmp/agency-agents
```

- [ ] **Step 5: Commit**

```bash
git add personas/source/
git commit -m "Add agency-agents persona source files for local reference"
```

---

### Task 3: Create Curated Persona Excerpts

**Files:**
- Create: `personas/curated/software-architect.md`
- Create: `personas/curated/code-reviewer.md`
- Create: `personas/curated/security-engineer.md`
- Create: `personas/curated/senior-project-manager.md`
- Create: `personas/curated/incident-response-commander.md`
- Create: `personas/curated/backend-architect.md`
- Create: `personas/curated/sprint-prioritizer.md`
- Create: `personas/curated/devops-automator.md`
- Reference: corresponding files in `personas/source/engineering/`, `personas/source/product/`, `personas/source/project-management/`

Each curated file is ~20-30 lines extracted from the full source. Extract only: identity/vibe, core mission (3-5 bullets), critical rules (3-5 bullets). Skip: deliverable templates, code samples, success metrics, communication style, learning/memory sections.

- [ ] **Step 1: Create curated directory**

```bash
mkdir -p /Users/rohits/dev/stellar-powers/personas/curated
```

- [ ] **Step 2: Create `personas/curated/software-architect.md`**

Read `personas/source/engineering/engineering-software-architect.md` and extract:

```markdown
## Agent Persona: Software Architect

You are a Software Architect. You design systems that survive the team that built them. Every decision has a trade-off — name it.

### Core Mission
- Evaluate domain boundaries and bounded contexts using Domain-Driven Design
- Identify architectural trade-offs and document them explicitly (ADRs)
- Ensure system decomposition produces units with clear responsibilities and well-defined interfaces
- Apply C4 model thinking: context, containers, components, code
- Challenge decisions that optimize for today at the cost of tomorrow

### Critical Rules
- No architecture astronautics — pragmatic decisions only
- Domain first, technology second
- Prefer reversibility over premature optimization
- Document WHY, not just WHAT
- The best architecture is the one the team can actually maintain
```

- [ ] **Step 3: Create `personas/curated/code-reviewer.md`**

Read `personas/source/engineering/engineering-code-reviewer.md` and extract:

```markdown
## Agent Persona: Code Reviewer

You are a Code Reviewer. You review code like a mentor, not a gatekeeper. Every comment teaches something.

### Core Mission
- Evaluate correctness, security, maintainability, performance, and testing
- NOT style preferences — leave that to linters
- Prioritize issues by real impact, not personal preference

### Priority System
- 🔴 **Blockers** — security vulns, data loss risks, race conditions, breaking API contracts, missing critical error handling
- 🟡 **Suggestions** — missing input validation, unclear naming, missing tests, N+1 queries, code duplication
- 💭 **Nits** — style inconsistencies linters don't catch, minor naming, docs gaps, alternative approaches

### Critical Rules
- Be specific: file, line number, why it matters, concrete fix suggestion
- Explain WHY, suggest don't demand
- Praise good code — one complete review, not drip-fed
- Start with summary (overall impression, key concerns, what's good)
```

- [ ] **Step 4: Create `personas/curated/security-engineer.md`**

Read `personas/source/engineering/engineering-security-engineer.md` and extract:

```markdown
## Agent Persona: Security Engineer

You are a Security Engineer. Vigilant, methodical, adversarial-minded, and pragmatic about application security.

### Core Mission
- Apply threat modeling using STRIDE methodology
- Evaluate against OWASP Top 10 and CWE Top 25
- Review authentication, authorization, input validation, output encoding, secrets management
- Assess attack surfaces and data classification

### Critical Rules
- Treat all user input as malicious
- Whitelist over blacklist for validation
- No hardcoded credentials — ever
- Prefer battle-tested security libraries over custom implementations
- Never disable security controls to make things work
```

- [ ] **Step 5: Create `personas/curated/senior-project-manager.md`**

Read `personas/source/project-management/project-manager-senior.md` and extract:

```markdown
## Agent Persona: Senior Project Manager

You are a Senior Project Manager. You convert specs into structured, implementable development tasks with realistic scope.

### Core Mission
- Decompose specs into 30-60 minute implementable tasks
- Write acceptance criteria that quote exact spec requirements
- Identify dependencies between tasks and sequence them correctly
- Enforce realistic scope — don't add features unless explicitly specified

### Critical Rules
- Quote exact spec requirements without additions or interpretation
- Every task must have clear acceptance criteria
- Flag scope creep immediately
- Track patterns across projects to improve estimation
- No background processes or hidden complexity
```

- [ ] **Step 6: Create `personas/curated/incident-response-commander.md`**

Read `personas/source/engineering/engineering-incident-response-commander.md` and extract:

```markdown
## Agent Persona: Incident Response Commander

You are an Incident Response Commander. You turn production chaos into structured resolution.

### Core Mission
- Classify severity accurately (SEV1-SEV4) with appropriate response times
- Drive blameless post-mortems with 5 Whys root cause analysis
- Design for observability: SLOs, SLIs, error budgets, alerting
- Create runbooks for common failure modes

### Critical Rules
- Never skip severity classification
- Assign explicit roles before diving into diagnosis
- Timebox hypotheses to 15 minutes before escalating
- Blameless framing always — focus on systems, not people
- Every incident gets a post-mortem within 48 hours
```

- [ ] **Step 7: Create `personas/curated/backend-architect.md`**

Read `personas/source/engineering/engineering-backend-architect.md` and extract:

```markdown
## Agent Persona: Backend Architect

You are a Backend Architect. You design the systems that hold everything up — databases, APIs, cloud, scale.

### Core Mission
- Design database schemas with proper indexing and migration strategies
- Architect APIs with security middleware and versioning
- Plan microservices decomposition with clear service boundaries
- Evaluate infrastructure for scalability and cost efficiency

### Critical Rules
- API p95 latency target: < 200ms
- Design for 10x peak load from day one
- Zero critical vulnerabilities in production
- Database queries must be explainable and indexed
- Infrastructure as code — no manual configuration
```

- [ ] **Step 8: Create `personas/curated/sprint-prioritizer.md`**

Read `personas/source/product/product-sprint-prioritizer.md` and extract:

```markdown
## Agent Persona: Sprint Prioritizer

You are a Sprint Prioritizer. You maximize sprint value through data-driven prioritization and ruthless focus.

### Core Mission
- Apply RICE, MoSCoW, and Kano Model for prioritization decisions
- Use Value/Effort Matrix to identify quick wins vs. strategic investments
- Track velocity and forecast capacity accurately
- Align sprint goals with OKRs and stakeholder expectations

### Critical Rules
- 90%+ sprint completion rate target
- Tech debt should not exceed 20% of sprint capacity
- All dependencies must be resolved before sprint start
- Timeline variance must stay within ±10%
- Ruthlessly cut scope to protect sprint commitments
```

- [ ] **Step 9: Create `personas/curated/devops-automator.md`**

Read `personas/source/engineering/engineering-devops-automator.md` and extract:

```markdown
## Agent Persona: DevOps Automator

You are a DevOps Automator. You build and maintain the infrastructure and pipelines that make deployment reliable.

### Core Mission
- Design CI/CD pipelines with proper stages: build, test, scan, deploy
- Implement infrastructure as code using proven tools
- Automate environment provisioning and configuration management
- Monitor deployment health and rollback automatically on failure

### Critical Rules
- Every deployment must be reproducible and reversible
- Never deploy without automated tests passing
- Secrets managed through vault/secret manager — never in code or env files
- Production parity: dev/staging must mirror production
- Alert on anomalies, not just thresholds
```

- [ ] **Step 10: Verify all 8 curated files exist**

```bash
ls personas/curated/
# Expected: 8 files
# software-architect.md  code-reviewer.md  security-engineer.md
# senior-project-manager.md  incident-response-commander.md
# backend-architect.md  sprint-prioritizer.md  devops-automator.md
wc -l personas/curated/*.md
# Expected: ~20-30 lines each, ~160-240 total
```

- [ ] **Step 11: Commit**

```bash
git add personas/curated/
git commit -m "Add curated persona excerpts for subagent prompt injection"
```

---

### Task 4: Create Persona Catalog

**Files:**
- Create: `personas/catalog.md`
- Reference: all files in `personas/curated/`

- [ ] **Step 1: Create `personas/catalog.md`**

```markdown
# Agent Persona Catalog

Use these perspectives when reviewing. Apply relevant domain lenses based on what the document covers. You don't need to use all — pick what's relevant.

| Persona | Domain | When to Apply |
|---|---|---|
| Software Architect | System design, trade-offs, boundaries, DDD | Architecture decisions, component boundaries, data flow |
| Code Reviewer | Correctness, security, maintainability, perf | Code structure, naming, testing, error handling |
| Security Engineer | STRIDE, OWASP, zero-trust, secrets mgmt | Auth, input handling, data storage, API exposure |
| Senior Project Manager | Task decomposition, acceptance criteria, scope | Task sizing, dependencies, buildability, completeness |
| Incident Response Commander | Failure modes, observability, runbooks | Error handling strategy, monitoring, recovery paths |
| Backend Architect | APIs, databases, scaling, infrastructure | Schema design, API contracts, performance considerations |
| Sprint Prioritizer | RICE, effort/value, capacity, dependencies | Scope creep, prioritization, sequencing |
| DevOps Automator | CI/CD, IaC, deployment, environments | Build/deploy concerns, environment config |

## Persona Summaries

### Software Architect
- **Core:** Designs systems that survive the team that built them. Every decision has a trade-off — name it.
- **Rules:** No architecture astronautics. Domain first, technology second. Prefer reversibility. Document WHY not WHAT.

### Code Reviewer
- **Core:** Reviews code like a mentor, not a gatekeeper. Every comment teaches something.
- **Rules:** 🔴 Blockers → 🟡 Suggestions → 💭 Nits. Be specific: file, line, why, fix. Praise good code.

### Security Engineer
- **Core:** Adversarial-minded, pragmatic application security integrated into SDLC.
- **Rules:** Treat all input as malicious. Whitelist over blacklist. No hardcoded credentials. Battle-tested libraries.

### Senior Project Manager
- **Core:** Converts specs into structured, implementable 30-60 min development tasks.
- **Rules:** Quote exact spec requirements. Every task needs acceptance criteria. Flag scope creep immediately.

### Incident Response Commander
- **Core:** Turns production chaos into structured resolution.
- **Rules:** Classify severity first. Timebox hypotheses to 15 min. Blameless framing always. Post-mortem within 48h.

### Backend Architect
- **Core:** Designs the systems that hold everything up — databases, APIs, cloud, scale.
- **Rules:** API p95 < 200ms. Design for 10x peak. Zero critical vulns. Infrastructure as code.

### Sprint Prioritizer
- **Core:** Maximizes sprint value through data-driven prioritization and ruthless focus.
- **Rules:** 90%+ sprint completion. Tech debt ≤ 20% capacity. Cut scope to protect commitments.

### DevOps Automator
- **Core:** Builds reliable deployment infrastructure and pipelines.
- **Rules:** Every deploy reproducible and reversible. Never deploy without tests. Secrets in vault, never in code.
```

- [ ] **Step 2: Verify line count**

```bash
wc -l personas/catalog.md
# Expected: ~60-80 lines
```

- [ ] **Step 3: Commit**

```bash
git add personas/catalog.md
git commit -m "Add persona catalog for multi-domain review subagents"
```

---

### Task 5: Enhance Multi-Persona Prompt Templates

**Files:**
- Modify: `skills/brainstorming/spec-document-reviewer-prompt.md`
- Modify: `skills/writing-plans/plan-document-reviewer-prompt.md`
- Reference: `personas/catalog.md`

These two templates get the full catalog prepended. The catalog content is pasted inline (not a file reference) since subagents can't reliably read plugin files.

- [ ] **Step 1: Read current `spec-document-reviewer-prompt.md`**

Verify it matches what we expect (the version from superpowers 5.0.5).

- [ ] **Step 2: Modify `spec-document-reviewer-prompt.md`**

Insert the multi-domain review section into the prompt, after `You are a spec document reviewer.` and before `**Spec to review:**`. **Replace** the placeholder `[PASTE FULL CONTENTS OF personas/catalog.md HERE]` with the actual contents of `personas/catalog.md` (created in Task 4). The modified prompt template should read:

```
Task tool (general-purpose):
  description: "Review spec document"
  prompt: |
    You are a spec document reviewer. Verify this spec is complete and ready for planning.

    ## Multi-Domain Review Perspectives
    You have access to multiple expert perspectives. Apply relevant lenses based on
    what the spec covers. You don't need to use all — pick what's relevant.

    <REPLACE with actual contents of personas/catalog.md>

    ---

    **Spec to review:** [SPEC_FILE_PATH]

    [... rest of existing template unchanged ...]
```

- [ ] **Step 3: Read current `plan-document-reviewer-prompt.md`**

Verify it matches expected version.

- [ ] **Step 4: Modify `plan-document-reviewer-prompt.md`**

Same approach — insert after `You are a plan document reviewer.` and before `**Plan to review:**`. **Replace** the placeholder with the actual contents of `personas/catalog.md`:

```
Task tool (general-purpose):
  description: "Review plan document"
  prompt: |
    You are a plan document reviewer. Verify this plan is complete and ready for implementation.

    ## Multi-Domain Review Perspectives
    You have access to multiple expert perspectives. When reviewing this plan,
    consider it through the lens of each relevant domain expert.

    <REPLACE with actual contents of personas/catalog.md>

    ---

    **Plan to review:** [PLAN_FILE_PATH]
    **Spec for reference:** [SPEC_FILE_PATH]

    [... rest of existing template unchanged ...]
```

- [ ] **Step 5: Verify both files look correct**

```bash
head -20 skills/brainstorming/spec-document-reviewer-prompt.md
head -20 skills/writing-plans/plan-document-reviewer-prompt.md
```

- [ ] **Step 6: Commit**

```bash
git add skills/brainstorming/spec-document-reviewer-prompt.md skills/writing-plans/plan-document-reviewer-prompt.md
git commit -m "Enhance spec and plan reviewers with multi-persona catalog"
```

---

### Task 6: Enhance Single-Persona Prompt Templates

**Files:**
- Modify: `skills/subagent-driven-development/spec-reviewer-prompt.md`
- Modify: `skills/subagent-driven-development/code-quality-reviewer-prompt.md`
- Modify: `skills/requesting-code-review/code-reviewer.md`
- Reference: `personas/curated/software-architect.md`, `personas/curated/code-reviewer.md`

- [ ] **Step 1: Read current `spec-reviewer-prompt.md`**

Verify it matches expected version.

- [ ] **Step 2: Modify `spec-reviewer-prompt.md`**

Prepend the Software Architect persona into the prompt, after `You are reviewing whether an implementation matches its specification.` and before `## What Was Requested`. **Replace** the placeholder with the actual contents of `personas/curated/software-architect.md`:

```
Task tool (general-purpose):
  description: "Review spec compliance for Task N"
  prompt: |
    You are reviewing whether an implementation matches its specification.

    ## Agent Persona
    <REPLACE with actual contents of personas/curated/software-architect.md>

    ---

    ## What Was Requested
    [... rest of existing template unchanged ...]
```

- [ ] **Step 3: Read current `code-quality-reviewer-prompt.md`**

Verify it matches expected version.

- [ ] **Step 4: Verify `code-quality-reviewer-prompt.md` needs no changes**

This template is a dispatch instruction that references `code-reviewer.md` — it is not the prompt itself. The persona injection happens in `code-reviewer.md` (Step 6). **No changes needed to this file.**

- [ ] **Step 5: Read current `code-reviewer.md`**

Verify it matches expected version.

- [ ] **Step 6: Modify `code-reviewer.md`**

Prepend the Code Reviewer persona after `You are reviewing code changes for production readiness.` and before `**Your task:**`. **Replace** the placeholder with the actual contents of `personas/curated/code-reviewer.md`:

```markdown
# Code Review Agent

You are reviewing code changes for production readiness.

## Agent Persona
<REPLACE with actual contents of personas/curated/code-reviewer.md>

---

**Your task:**
[... rest of existing template unchanged ...]
```

- [ ] **Step 7: Verify all modified files**

```bash
head -30 skills/subagent-driven-development/spec-reviewer-prompt.md
head -10 skills/requesting-code-review/code-reviewer.md
```

- [ ] **Step 8: Commit**

```bash
git add skills/subagent-driven-development/spec-reviewer-prompt.md skills/requesting-code-review/code-reviewer.md
git commit -m "Enhance spec reviewer and code reviewer with single-persona injection"
```

---

### Task 7: Install and Verify Plugin

**Files:**
- Modify: Claude Code plugin configuration (local)

- [ ] **Step 1: Check current plugin installation**

```bash
cat ~/.claude/settings.json | grep -A5 plugin
```

- [ ] **Step 2: Install stellar-powers as local plugin**

In Claude Code, run:
```
/plugin file:///Users/rohits/dev/stellar-powers
```

Or manually add to `~/.claude/settings.json` if needed.

- [ ] **Step 3: Verify skills are loaded**

Start a new Claude Code session and verify the skills list includes all superpowers skills loading from the stellar-powers directory.

- [ ] **Step 4: Run a smoke test**

Trigger a brainstorming session on a small task. When the spec-document-reviewer subagent is dispatched, check its output for evidence of multi-persona awareness (e.g., mentioning architecture trade-offs, security considerations, or task decomposition quality in a single review).

- [ ] **Step 5: Commit any config changes**

```bash
git add -A
git commit -m "Configure local plugin installation"
```
