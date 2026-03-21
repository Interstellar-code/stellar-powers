#!/usr/bin/env bash
# Test: Context7 integration across all skill files
# Static validation — no Claude CLI needed, runs instantly
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; echo "  $2"; FAIL=$((FAIL+1)); }

echo "=== Test: Context7 Integration Validation ==="
echo ""

# ============================================================
# Test 1: All 6 files reference Context7 or Library References
# ============================================================
echo "Test 1: Context7/Library References present in all 6 files..."

files=(
    "skills/writing-plans/SKILL.md"
    "skills/brainstorming/SKILL.md"
    "skills/subagent-driven-development/SKILL.md"
    "skills/subagent-driven-development/implementer-prompt.md"
    "skills/requesting-code-review/code-reviewer.md"
    "skills/feature-porting/scanner-prompt.md"
)

for f in "${files[@]}"; do
    filepath="$REPO_ROOT/$f"
    if grep -q "Context7\|context7\|Library References" "$filepath" 2>/dev/null; then
        pass "$f references Context7 or Library References"
    else
        fail "$f missing Context7 reference" "Expected Context7 or Library References mention"
    fi
done

echo ""

# ============================================================
# Test 2: --max-time 10 on all curl commands (5 files with curl)
# ============================================================
echo "Test 2: --max-time 10 present in curl files..."

curl_files=(
    "skills/writing-plans/SKILL.md"
    "skills/brainstorming/SKILL.md"
    "skills/subagent-driven-development/SKILL.md"
    "skills/requesting-code-review/code-reviewer.md"
    "skills/feature-porting/scanner-prompt.md"
)

for f in "${curl_files[@]}"; do
    filepath="$REPO_ROOT/$f"
    count=$(grep -c "max-time 10" "$filepath" 2>/dev/null || echo 0)
    if [ "$count" -ge 1 ]; then
        pass "$f has --max-time 10 ($count occurrences)"
    else
        fail "$f missing --max-time 10" "curl commands must include --max-time 10"
    fi
done

echo ""

# ============================================================
# Test 3: tokens=5000 on all context fetch calls
# ============================================================
echo "Test 3: tokens=5000 present in curl files..."

for f in "${curl_files[@]}"; do
    filepath="$REPO_ROOT/$f"
    count=$(grep -c "tokens=5000" "$filepath" 2>/dev/null || echo 0)
    if [ "$count" -ge 1 ]; then
        pass "$f has tokens=5000 ($count occurrences)"
    else
        fail "$f missing tokens=5000" "Context fetch must include tokens=5000 to cap response size"
    fi
done

echo ""

# ============================================================
# Test 4: trustScore selection (no r[0] usage)
# ============================================================
echo "Test 4: trustScore selection used (no r[0])..."

for f in "${curl_files[@]}"; do
    filepath="$REPO_ROOT/$f"
    if grep -q "trustScore" "$filepath" 2>/dev/null; then
        pass "$f uses trustScore selection"
    else
        fail "$f missing trustScore" "Library selection must use trustScore, not r[0]"
    fi
done

# Check no r[0] usage
r0_hits=$(grep -rn "r\[0\]" "${curl_files[@]/#/$REPO_ROOT/}" 2>/dev/null || true)
if [ -z "$r0_hits" ]; then
    pass "No r[0] usage found (trustScore used consistently)"
else
    fail "r[0] usage found" "$r0_hits"
fi

echo ""

# ============================================================
# Test 5: Graceful degradation (CONTEXT7_API_KEY referenced 2+ times)
# ============================================================
echo "Test 5: Graceful degradation (CONTEXT7_API_KEY 2+ refs per file)..."

for f in "${curl_files[@]}"; do
    filepath="$REPO_ROOT/$f"
    count=$(grep -c "CONTEXT7_API_KEY" "$filepath" 2>/dev/null || echo 0)
    if [ "$count" -ge 2 ]; then
        pass "$f has CONTEXT7_API_KEY $count times (curl + degradation)"
    else
        fail "$f has only $count CONTEXT7_API_KEY refs" "Need 2+: once in curl, once in degradation note"
    fi
done

echo ""

# ============================================================
# Test 6: Feature-porting scanner has Phase 4.5
# ============================================================
echo "Test 6: Feature-porting scanner has Phase 4.5..."

scanner="$REPO_ROOT/skills/feature-porting/scanner-prompt.md"
if grep -q "Phase 4.5" "$scanner" 2>/dev/null; then
    pass "scanner-prompt.md has Phase 4.5"
else
    fail "scanner-prompt.md missing Phase 4.5" "Expected Phase 4.5: API Currency Check"
fi

# Verify Phase 4.5 is between Phase 4 and Phase 5
phase4_line=$(grep -n "^## Phase 4:" "$scanner" | head -1 | cut -d: -f1)
phase45_line=$(grep -n "Phase 4.5" "$scanner" | head -1 | cut -d: -f1)
phase5_line=$(grep -n "^## Phase 5:" "$scanner" | head -1 | cut -d: -f1)

if [ -n "$phase4_line" ] && [ -n "$phase45_line" ] && [ -n "$phase5_line" ]; then
    if [ "$phase4_line" -lt "$phase45_line" ] && [ "$phase45_line" -lt "$phase5_line" ]; then
        pass "Phase 4.5 is between Phase 4 (line $phase4_line) and Phase 5 (line $phase5_line)"
    else
        fail "Phase 4.5 ordering wrong" "4=$phase4_line, 4.5=$phase45_line, 5=$phase5_line"
    fi
else
    fail "Could not find all phase markers" "4=$phase4_line 4.5=$phase45_line 5=$phase5_line"
fi

echo ""

# ============================================================
# Test 7: implementer-prompt.md has Library References section
# ============================================================
echo "Test 7: implementer-prompt.md has Library References..."

impl_prompt="$REPO_ROOT/skills/subagent-driven-development/implementer-prompt.md"
if grep -q "Library References" "$impl_prompt" 2>/dev/null; then
    pass "implementer-prompt.md has Library References section"
else
    fail "implementer-prompt.md missing Library References" "Expected ## Library References section"
fi

if grep -q "authoritative API reference" "$impl_prompt" 2>/dev/null; then
    pass "implementer-prompt.md has authoritative reference instruction"
else
    fail "implementer-prompt.md missing authoritative instruction" "Should tell implementer to use docs as authoritative"
fi

echo ""

# ============================================================
# Test 8: writing-plans has Library References appendix template
# ============================================================
echo "Test 8: writing-plans has Library References appendix..."

wp="$REPO_ROOT/skills/writing-plans/SKILL.md"
if grep -q "Library References" "$wp" 2>/dev/null; then
    pass "writing-plans has Library References appendix"
else
    fail "writing-plans missing Library References appendix" "Plans should include a Library References appendix"
fi

if grep -q "200 tokens" "$wp" 2>/dev/null; then
    pass "writing-plans has 200 token limit guidance"
else
    fail "writing-plans missing token limit" "Library References should be max ~200 tokens per library"
fi

echo ""

# ============================================================
# Test 9: code-reviewer has API Currency lens
# ============================================================
echo "Test 9: code-reviewer has API Currency lens..."

cr="$REPO_ROOT/skills/requesting-code-review/code-reviewer.md"
if grep -q "API Currency" "$cr" 2>/dev/null; then
    pass "code-reviewer has API Currency lens"
else
    fail "code-reviewer missing API Currency" "Expected API Currency supporting lens"
fi

if grep -q "not optional" "$cr" 2>/dev/null; then
    pass "API Currency check is non-optional"
else
    fail "API Currency check is not marked non-optional" "Should say 'not optional'"
fi

echo ""

# ============================================================
# Test 10: brainstorming has Context7 verification
# ============================================================
echo "Test 10: brainstorming has Context7 verification..."

bs="$REPO_ROOT/skills/brainstorming/SKILL.md"
if grep -q "Library verification (Context7)" "$bs" 2>/dev/null; then
    pass "brainstorming has Library verification section"
else
    fail "brainstorming missing Library verification" "Expected Library verification (Context7) section"
fi

if grep -q "pinned version" "$bs" 2>/dev/null; then
    pass "brainstorming has version pinning guidance"
else
    fail "brainstorming missing version pinning" "Should check project's pinned version"
fi

echo ""

# ============================================================
# Test 11: Skill catalog includes feature-porting
# ============================================================
echo "Test 11: using-stellarpowers skill catalog..."

usp="$REPO_ROOT/skills/using-stellarpowers/SKILL.md"
if grep -q "feature-porting" "$usp" 2>/dev/null; then
    pass "Skill catalog lists feature-porting"
else
    fail "Skill catalog missing feature-porting" "Expected feature-porting in Available Skills table"
fi

skill_count=$(grep -c "^\| \`" "$usp" 2>/dev/null || echo 0)
if [ "$skill_count" -ge 15 ]; then
    pass "Skill catalog has $skill_count entries (expected 15+)"
else
    fail "Skill catalog has only $skill_count entries" "Expected 15+ skills listed"
fi

echo ""

# ============================================================
# Test 12: Opus prohibition
# ============================================================
echo "Test 12: Opus prohibition in subagent skills..."

sdd="$REPO_ROOT/skills/subagent-driven-development/SKILL.md"
if grep -qi "never use opus" "$sdd" 2>/dev/null; then
    pass "subagent-driven-development prohibits opus"
else
    fail "subagent-driven-development missing opus prohibition" "Should say 'Never use opus for subagents'"
fi

if grep -q "model=sonnet" "$REPO_ROOT/skills/brainstorming/SKILL.md" 2>/dev/null; then
    pass "brainstorming specifies model=sonnet for reviewers"
else
    fail "brainstorming missing model=sonnet" "Reviewer dispatch should specify model=sonnet"
fi

echo ""

# ============================================================
# Test 13: Loop guard in brainstorming
# ============================================================
echo "Test 13: Feature-porting loop guard..."

if grep -q "Loop guard" "$bs" 2>/dev/null; then
    pass "brainstorming has loop guard"
else
    fail "brainstorming missing loop guard" "Expected loop guard for feature-porting re-invocation"
fi

echo ""

# ============================================================
# Summary
# ============================================================
echo "========================================"
echo " Results: $PASS passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
