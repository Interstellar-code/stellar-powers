---
name: send-feedback
description: File accumulated skill feedback as GitHub issues on the stellar-powers repo. Use when you want to submit workflow metrics from this project back to stellar-powers for analysis.
---

## Step 1: Check Prerequisites

Run:

```bash
gh auth status 2>/dev/null
```

If this fails (non-zero exit), tell the user: "GitHub CLI not authenticated. Run `gh auth login` first." and stop.

## Step 2: Scan for Metrics Packages

Run:

```bash
ls .stellar-powers/metrics/*.json 2>/dev/null
```

If no files are found, report: "No pending feedback to send." and stop.

## Step 3: Process Each Package File

For each `.json` file found in `.stellar-powers/metrics/`, do the following:

### 3a. Read and Parse

Read the JSON file. Extract these fields:
- `workflow_id`
- `context.repo`
- `context.task_type`
- `context.skills_chain` (array)
- `context.sp_version`
- `context.topic`
- `timeline.duration_minutes`
- `completion_feedback`
- `skills` (object with per-skill corrections and violations)
- `artifacts`
- `outcome`

### 3b. Deduplication Check

Run (substituting the first 8 characters of `workflow_id` for `WORKFLOW_ID_SHORT`):

```bash
gh search issues --repo Interstellar-code/stellar-powers --match title "[skill-feedback]" "WORKFLOW_ID_SHORT" --json number --jq length
```

If the result is greater than 0, skip this file and report: "Already submitted: WORKFLOW_ID_SHORT". Move to the next file.

### 3c. Build Issue Title

Format:
```
[skill-feedback] {skills_chain joined by +}: {topic} ({repo}) [{workflow_id first 8 chars}]
```

Example: `[skill-feedback] writing-plans+subagent-driven-development: auth refactor (myorg/myrepo) [a1b2c3d4]`

### 3d. Build Issue Body

Collect all corrections across all skills. Each correction should come from `skills.{skill_name}.corrections[]` and include the skill name, step, and feedback text.

Collect pattern stats: review stats, violation counts from `skills.{skill_name}.violations`.

Build the body as:

```markdown
## Skill Feedback: {topic} workflow
**Repo:** {repo} | **Type:** {task_type} | **Version:** {sp_version}
**Duration:** {duration_minutes} min | **Skills:** {skills_chain joined by →}
**Outcome:** {outcome}

### Key Corrections
- {skill}/{step}: "{feedback}" (one bullet per correction across all skills)

### Patterns
- {review stats, violation counts, etc. — one bullet per notable pattern}

### User Feedback
"{completion_feedback}"

<details><summary>Raw Metrics</summary>

```json
{full metrics JSON, pretty-printed}
```

</details>

<details><summary>Raw Workflow Events</summary>

```jsonl
{Read the `raw_events` array from the metrics package JSON. Print each event as a single JSONL line.
The raw_events are preserved in the metrics package by the packager — they survive workflow.jsonl pruning.
If the package has no raw_events field (older package version), fall back to reading workflow.jsonl.}
```

</details>
```

### 3e. Create GitHub Issue

Use a heredoc to handle multiline body safely:

```bash
gh issue create \
  --repo Interstellar-code/stellar-powers \
  --label skill-feedback \
  --title "TITLE" \
  --body "$(cat <<'ISSUE_BODY'
BODY
ISSUE_BODY
)"
```

<HARD-GATE>
DATA VERIFICATION — Before proceeding to cleanup, verify the issue body contains BOTH `<details>` sections:
1. Check the created issue contains "Raw Metrics" — if missing, the metrics JSON was not included
2. Check the created issue contains "Raw Workflow Events" — if missing, the events were not included
If either is missing, update the issue with the missing data BEFORE proceeding. The cleanup step will permanently delete the source files.
</HARD-GATE>

### 3f. Handle Success or Failure

- On success: rename the file from `.json` to `.json.sent`
  ```bash
  mv .stellar-powers/metrics/FILENAME.json .stellar-powers/metrics/FILENAME.json.sent
  ```
- On failure: if the file was already renamed to `.sent`, rename it back to `.json`
  ```bash
  mv .stellar-powers/metrics/FILENAME.json.sent .stellar-powers/metrics/FILENAME.json
  ```

## Step 4: Cleanup

Delete all successfully sent files:

```bash
find .stellar-powers/metrics/ -name "*.json.sent" -delete 2>/dev/null
```

Also delete orphaned `.sent` files older than 1 hour:

```bash
find .stellar-powers/metrics/ -name "*.sent" -mmin +60 -delete 2>/dev/null
```

## Step 5: Log the Event

Append a log entry to `.stellar-powers/workflow.jsonl`. Substitute real values for TIMESTAMP, workflow IDs, session, issue URLs, and count:

```bash
echo '{"ts":"TIMESTAMP","event":"feedback_sent","workflow_id":"","session":"","data":{"issue_urls":["URL1","URL2"],"packages_sent":N}}' >> .stellar-powers/workflow.jsonl
```

Use `date -u +%Y-%m-%dT%H:%M:%SZ` to generate the timestamp.

## Step 6: Report

Report to the user:

```
N issues created on stellar-powers: [URL1, URL2, ...]. M failed (files retained).
```

If all failed: "All N packages failed to submit. Files retained for retry."
If none failed: omit the failure clause.
