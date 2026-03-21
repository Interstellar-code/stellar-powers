---
name: self-improving-agent
description: Use when working on the stellar-powers repo to analyze skill-feedback GitHub issues, identify improvement patterns, evaluate current skill quality via test scenarios, propose and apply fixes, then verify improvements
---

## Self-Improving Agent

Analyze feedback from skill usage across repos, evaluate current skill quality, propose improvements, and verify they work. Inspired by Karpathy's autoresearch — a modify → evaluate → keep/discard loop on a dedicated branch.

### Architecture (autoresearch mapping)

| Autoresearch | This Skill |
|---|---|
| `prepare.py` (read-only eval) | `tests/test-self-improving.sh` + `.claude/tests/run-scenarios.py` |
| `train.py` (agent modifies) | Skill SKILL.md files in `skills/` |
| `program.md` (instructions) | This file |
| `results.tsv` (experiment log) | GitHub issues (input) + eval scores (output) |
| `val_bpb` (metric) | Eval score: event completeness + context resolution + packaging |
| `git reset` on failure | Discard branch if eval regresses |
| Dedicated branch | `autoresearch/<date>` branch |

### The Loop

**Setup:** Create a dedicated branch before making changes.
```bash
git checkout -b autoresearch/$(date +%Y%m%d)
```

1. **Gather feedback**
   ```bash
   gh issue list --repo Interstellar-code/stellar-powers --label skill-feedback --state open --json number,title,body --limit 50
   ```
   Parse each issue: extract Key Corrections, Patterns, User Feedback, Raw Metrics JSON. Group by skill.

2. **Run baseline eval**
   ```bash
   bash tests/test-self-improving.sh
   python3 .claude/tests/run-scenarios.py
   ```
   Record scores. This is your `val_bpb` baseline.

3. **Analyze patterns**
   For each skill, identify:
   - Recurring corrections (same feedback across multiple issues)
   - Tool failure patterns
   - Step coverage gaps (steps_completed = 0)
   - Context field resolution failures ("unknown" values)

   Rank by frequency x severity.

4. **Propose changes**
   For each finding, propose a specific edit:
   - File path and section
   - What to change and why
   - Confidence level (high/medium/low based on data points)

   Present all proposals. Wait for approval.

5. **Apply and verify** (the autoresearch loop)
   For each approved change:
   a. Make the edit
   b. `git commit`
   c. Re-run eval:
      ```bash
      bash tests/test-self-improving.sh
      python3 .claude/tests/run-scenarios.py
      ```
   d. Compare to baseline:
      - **Improved or equal** → keep (advance branch)
      - **Regressed** → `git revert HEAD` (discard change)
   e. Report: "Change X: Baseline Y% → After Z%. KEPT/DISCARDED."

   **Simplicity criterion** (from autoresearch): A small improvement that adds ugly complexity is not worth it. Removing something and getting equal or better results is a great outcome.

6. **Merge and close**
   After all changes are applied and verified:
   ```bash
   git checkout main
   git merge autoresearch/$(date +%Y%m%d)
   ```
   Close processed issues:
   ```bash
   gh issue close NUMBER --repo Interstellar-code/stellar-powers --comment "Incorporated in vX.Y.Z"
   ```

### NEVER STOP

Once the loop begins, do NOT pause to ask "should I continue?" The loop runs until all feedback is processed or the human interrupts. If you run out of feedback-driven changes, look at eval failures for opportunities.

### When NOT to use
- Not on consumer repos (nyayasathi-app, appsfomo) — only on stellar-powers itself
- Not without at least 1 open skill-feedback issue
