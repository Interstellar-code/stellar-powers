---
name: feature-porting
description: Use when porting a feature from one project to another - scans source project, maps to target, produces extraction report for brainstorming
---

# Feature Porting

Port features between projects by dispatching a scan sub-agent and producing a mapping report. The report feeds into brainstorming for design.

## When to Use

- "Port X from /path"
- "Bring X from my other project"
- "Extract X from /path/to/project"
- "I have X working in another app, migrate it here"
- "Reuse X from /path"
- Any reference to using an existing feature from another local project

## Checklist

You MUST create a task for each of these items and complete them in order:

0. **Workflow setup** — Generate workflow ID and log invocation:
   ```bash
   WF_ID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
   mkdir -p .stellar-powers/reports
   echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"skill_invocation\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"skill\":\"feature-porting\",\"args\":\"feature=${FEATURE_NAME} source=${SOURCE_PATH}\"}}" >> .stellar-powers/workflow.jsonl
   ```
   Also check `.stellar-powers/workflow.jsonl` for incomplete feature-porting workflows (see Session Resumption section).

1. **Collect inputs** — Gather source path, feature name, and optional user context.
   - **Source project path:** Ask if not provided. Validate: run `test -d {path}`. If it doesn't exist, report error and ask again. If it looks like a URL or remote path, reject: "Feature porting requires a local filesystem path. Please clone or mount the project locally first."
   - **Feature name:** Ask if not provided: "What feature do you want to extract? (e.g., billing, document uploads, case management)"
   - **User context:** Ask if not provided: "Any notes about scope, things to skip, or how the feature works? (optional, press enter to skip)"
   - If none were provided inline, ask all three in a single message. If some were provided (e.g., "port billing from /path"), only ask for what's missing.

2. **Dispatch scanner sub-agent** — Read `./scanner-prompt.md` using the Read tool. Substitute the 5 variables:
   - `{{SOURCE_PATH}}` → the validated source path
   - `{{FEATURE_NAME}}` → the feature name
   - `{{TARGET_PATH}}` → current working directory
   - `{{USER_CONTEXT}}` → user context (or "None provided")
   - `{{REPORT_PATH}}` → `.stellar-powers/reports/YYYY-MM-DD-{feature}-extraction.md` (use actual date, kebab-case feature name)

   Before dispatching, check whether `${REPORT_PATH}` already exists. If so, resolve a unique path with counter suffix (`-2.md`, `-3.md`, etc.).

   Log scan_started BEFORE dispatching (so interrupted scans are recoverable):
   ```bash
   echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"scan_started\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"source\":\"${SOURCE_PATH}\",\"feature\":\"${FEATURE_NAME}\",\"report_path\":\"${REPORT_PATH}\"}}" >> .stellar-powers/workflow.jsonl
   ```

   Then dispatch via the Agent tool with `model=sonnet`.

3. **Process sub-agent results** — Check if the report contains an `## Incomplete` section. Set STATUS accordingly, then log:
   ```bash
   # Set STATUS to "partial" if report contains "## Incomplete", else "complete"
   STATUS="complete"
   grep -q "^## Incomplete" "${REPORT_PATH}" 2>/dev/null && STATUS="partial"
   echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"scan_completed\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"report_path\":\"${REPORT_PATH}\",\"status\":\"${STATUS}\"}}" >> .stellar-powers/workflow.jsonl
   ```

4. **Present approval summary** — Show the user:
   > "Feature extraction complete for {feature}. Report saved to {path}.
   > - Source stack: {summary}
   > - Target stack: {summary}
   > - {N} items already exist in target
   > - {N} items need porting
   > - {N} shared dependencies deferred
   >
   > Review the report and confirm before I proceed to design."

5. **Handle user response:**
   - If approved: log user_approved:
     ```bash
     echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"user_approved\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"report_path\":\"${REPORT_PATH}\"}}" >> .stellar-powers/workflow.jsonl
     ```
   - If changes requested: ask "Would you like me to re-run the full scan, or would you prefer to edit the report directly?" Full re-run goes back to step 2. Manual edit: user says "done" when finished, re-present summary.

6. **Commit report:**
   ```bash
   git add "${REPORT_PATH}"
   git commit -m "docs: add ${FEATURE_NAME} feature extraction report"
   ```

7. **Handoff to brainstorming** — Log handoff:
   ```bash
   echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"handoff_brainstorming\",\"workflow_id\":\"${WF_ID}\",\"session\":\"\",\"data\":{\"report_path\":\"${REPORT_PATH}\"}}" >> .stellar-powers/workflow.jsonl
   ```
   Invoke brainstorming: use the Skill tool with `skill: "stellar-powers:brainstorming"` and `args: "Design adaptation based on feature extraction report at {REPORT_PATH}"`.

## Session Resumption

On invocation, check `.stellar-powers/workflow.jsonl` for incomplete feature-porting workflows — a `skill_invocation` or `scan_started` event without a corresponding `user_approved` or `handoff_brainstorming`. If found:

1. Load the most recent incomplete workflow's context (source path, feature name, report path from event data)
2. Check if a report exists at the report path
3. If report exists: present it to the user for approval (skip re-scanning)
4. If no report exists: inform the user of the interrupted scan and ask whether to re-run
5. Do not re-prompt for inputs that were already collected

## Error Handling

| Failure | Handling |
|---|---|
| Source path doesn't exist | Validate with `test -d` before dispatching sub-agent. Report error, ask for correct path |
| Source path is empty / not a project | Sub-agent reports "no project indicators found" and returns. Skill surfaces this to user |
| Sub-agent hits context limits | Sub-agent saves partial report with `## Incomplete` section. Skill presents partial results, asks user whether to proceed with partial data or narrow scope |
| Report write fails | Report error to user, suggest checking disk space / permissions |
| Sub-agent returns no useful data | Report "scan produced no actionable findings", ask user for more context or narrower scope |

## Report Collision

If a report for the same feature and date already exists at the target path, append a counter suffix: `-2.md`, `-3.md`, etc. Check before dispatching the sub-agent.

## Scope Boundaries

- Include only what is exclusively owned by the target feature
- Shared dependencies (used by multiple features) are logged as "out of scope - port separately"
- When in doubt, defer — it's safer to port without a shared dependency and add it later
