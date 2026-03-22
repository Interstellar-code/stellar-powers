#!/usr/bin/env bash
# Tests for scripts/md-extract-section.py
# Run from any directory — uses absolute paths throughout.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/md-extract-section.py"
FIXTURE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixture-plan.md"
TMPFILE="$(mktemp /tmp/fixture-XXXXXX).md"

PASS=0
FAIL=0

pass() { echo "PASS — $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL — $1"; FAIL=$((FAIL + 1)); }

# Reset temp file to a fresh copy of the fixture before each write test.
reset_tmp() { cp "$FIXTURE" "$TMPFILE"; }

# ---------------------------------------------------------------------------
# 1. Basic read — substring match
# ---------------------------------------------------------------------------
out=$(python3 "$SCRIPT" "$FIXTURE" "Task 4")
if echo "$out" | grep -q "### Task 4: Metrics Packager" && echo "$out" | grep -q "metrics-packager.py"; then
  pass "1. Basic read: substring match returns correct section"
else
  fail "1. Basic read: substring match returned unexpected output"
fi

# ---------------------------------------------------------------------------
# 2. Regex read — "Task 1:" should NOT match "Task 10:" or "Task 11:" etc.
# ---------------------------------------------------------------------------
out=$(python3 "$SCRIPT" "$FIXTURE" --pattern "^Task 1:")
if echo "$out" | grep -q "### Task 1:" && ! echo "$out" | grep -q "### Task 10:" && ! echo "$out" | grep -q "### Task 11:"; then
  pass "2. Regex read: --pattern anchored to Task 1: only, not Task 10/11"
else
  fail "2. Regex read: --pattern matched wrong sections"
fi

# ---------------------------------------------------------------------------
# 3. Multi-section read — two sections at once
# ---------------------------------------------------------------------------
out=$(python3 "$SCRIPT" "$FIXTURE" "Task 6" "Task 7")
has_6=$(echo "$out" | grep -c "### Task 6:" || true)
has_7=$(echo "$out" | grep -c "### Task 7:" || true)
if [[ "$has_6" -ge 1 && "$has_7" -ge 1 ]]; then
  pass "3. Multi-section read: both Task 6 and Task 7 returned"
else
  fail "3. Multi-section read: missing one or both sections"
fi

# ---------------------------------------------------------------------------
# 4. Overview read — content before first ## heading
# ---------------------------------------------------------------------------
out=$(python3 "$SCRIPT" "$FIXTURE" --overview)
if echo "$out" | grep -q "Implementation Plan" && ! echo "$out" | grep -q "^## "; then
  pass "4. Overview read: returns pre-heading content, no ## headings"
else
  fail "4. Overview read: unexpected output"
fi

# ---------------------------------------------------------------------------
# 5. Write mode — replace body, preserve heading, other sections untouched
# ---------------------------------------------------------------------------
reset_tmp
echo "Updated dependency audit content." | python3 "$SCRIPT" "$TMPFILE" --write "Task 2" > /dev/null
updated=$(python3 "$SCRIPT" "$TMPFILE" "Task 2")
task1=$(python3 "$SCRIPT" "$TMPFILE" "Task 1")

heading_ok=false; echo "$updated" | grep -q "### Task 2:" && heading_ok=true
body_ok=false;    echo "$updated" | grep -q "Updated dependency audit content." && body_ok=true
old_gone=false;   ! echo "$updated" | grep -q "npm audit" && old_gone=true
task1_ok=false;   echo "$task1"   | grep -q "Initialize the repository" && task1_ok=true

if $heading_ok && $body_ok && $old_gone && $task1_ok; then
  pass "5. Write mode: heading preserved, body replaced, other section untouched"
else
  fail "5. Write mode: heading_ok=$heading_ok body_ok=$body_ok old_gone=$old_gone task1_ok=$task1_ok"
fi

# ---------------------------------------------------------------------------
# 6. Write with regex — same but using --pattern
# ---------------------------------------------------------------------------
reset_tmp
echo "GA release steps updated." | python3 "$SCRIPT" "$TMPFILE" --write --pattern "^Task 12:" > /dev/null
updated=$(python3 "$SCRIPT" "$TMPFILE" --pattern "^Task 12:")
heading_ok=false; echo "$updated" | grep -q "### Task 12:" && heading_ok=true
body_ok=false;    echo "$updated" | grep -q "GA release steps updated." && body_ok=true
old_gone=false;   ! echo "$updated" | grep -q "Tag v2.0.0" && old_gone=true

if $heading_ok && $body_ok && $old_gone; then
  pass "6. Write with regex: heading preserved, body replaced"
else
  fail "6. Write with regex: heading_ok=$heading_ok body_ok=$body_ok old_gone=$old_gone"
fi

# ---------------------------------------------------------------------------
# 7a. Edge case — section not found exits with code 1
# ---------------------------------------------------------------------------
set +e
python3 "$SCRIPT" "$FIXTURE" "Nonexistent Section XYZ" > /dev/null 2>&1
exit_code=$?
set -e
if [[ "$exit_code" -eq 1 ]]; then
  pass "7a. Edge case: section not found exits with code 1"
else
  fail "7a. Edge case: expected exit 1, got $exit_code"
fi

# ---------------------------------------------------------------------------
# 7b. Edge case — nested headings (### inside ###) included in parent extract
# ---------------------------------------------------------------------------
out=$(python3 "$SCRIPT" "$FIXTURE" "Task 3")
has_parent=$(echo "$out" | grep -c "### Task 3: Core Hook Infrastructure" || true)
has_subtask_a=$(echo "$out" | grep -c "Subtask A" || true)
has_subtask_b=$(echo "$out" | grep -c "Subtask B" || true)
has_subtask_c=$(echo "$out" | grep -c "Subtask C" || true)
if [[ "$has_parent" -ge 1 && "$has_subtask_a" -ge 1 && "$has_subtask_b" -ge 1 && "$has_subtask_c" -ge 1 ]]; then
  pass "7b. Edge case: nested sub-headings included in parent section extract"
else
  fail "7b. Edge case: nested headings missing — parent=$has_parent a=$has_subtask_a b=$has_subtask_b c=$has_subtask_c"
fi

# ---------------------------------------------------------------------------
# 7c. Edge case — empty section (add one to a temp file and extract it)
# ---------------------------------------------------------------------------
TMPFILE2="$(mktemp /tmp/fixture-empty-XXXXXX.md)"
cat > "$TMPFILE2" <<'MDEOF'
# Doc

## Section A

Some content here.

## Empty Section

## Section C

More content.
MDEOF

out=$(python3 "$SCRIPT" "$TMPFILE2" "Empty Section")
# Should return just the heading line (no body)
heading_present=$(echo "$out" | grep -c "## Empty Section" || true)
if [[ "$heading_present" -ge 1 ]]; then
  pass "7c. Edge case: empty section returns heading with no body"
else
  fail "7c. Edge case: empty section extraction failed"
fi
rm -f "$TMPFILE2"

# ---------------------------------------------------------------------------
# 7d. Edge case — last section in file (no following heading)
# ---------------------------------------------------------------------------
out=$(python3 "$SCRIPT" "$FIXTURE" "Task 12")
if echo "$out" | grep -q "### Task 12:" && echo "$out" | grep -q "Tag v2.0.0"; then
  pass "7d. Edge case: last section extracted correctly (no following heading)"
else
  fail "7d. Edge case: last section extraction failed"
fi

# ---------------------------------------------------------------------------
# 8. Token efficiency — specific section vs full file
# ---------------------------------------------------------------------------
full_words=$(wc -w < "$FIXTURE")
task5_out=$(python3 "$SCRIPT" "$FIXTURE" "Task 5")
task5_words=$(echo "$task5_out" | wc -w)

if [[ "$full_words" -gt 0 && "$task5_words" -gt 0 ]]; then
  # Calculate percentage reduction: (full - section) / full * 100
  reduction=$(awk "BEGIN { printf \"%d\", (($full_words - $task5_words) / $full_words) * 100 }")
  if [[ "$reduction" -ge 80 ]]; then
    pass "8. Token efficiency: Task 5 extract is ${reduction}% smaller than full file (>= 80% required)"
  else
    fail "8. Token efficiency: only ${reduction}% reduction (need >= 80%). full=$full_words task5=$task5_words"
  fi
else
  fail "8. Token efficiency: word count calculation failed"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
rm -f "$TMPFILE"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
