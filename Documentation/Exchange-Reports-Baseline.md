# Exchange Online menu items 4-5: reporting baseline

Scope: Search Inbox Rules and Message Trace. The independent Convert Existing
Mailbox to Shared task has Order=25, between Shared Mailbox Management (20) and
Search Inbox Rules (30). Message Trace follows at 40. Mailbox Delegates is already
implemented separately and is NOT replaced by this package.

This is a standard local patch: extract outside the repository; unblock trusted
files; run Install-Patch.ps1 -ToolkitPath <repo>. -WhatIf remains available but is
optional. Apply still validates first, prompts, backs up changed existing files,
merges only the listed files, then verifies hashes/syntax and isolated helper checks.
This is a file overlay, not a Git branch merge. No commit/push/reset/fetch is done.

## Search Inbox Rules

- Select one/multiple user/shared mailboxes, or explicitly choose ALL.
- Requests hidden rules. Hidden state is Unknown if Exchange does not report it;
  the report does not infer hidden status from rule names.
- Default: enabled rules with review signals (forward/redirect/delete/move/read/
  stop-processing). These are heuristics, not proof of malicious behavior.
- IncludeDisabled and IncludeNonSuspicious expand the report. SearchText is a
  literal case-insensitive filter on inbox-rule name/description/actions, not regex.
- Mailbox-level forwarding is included as a separate Scope, regardless of rule
  text filtering, and is not mislabeled as an inbox rule. External/internal targets
  are not classified by this baseline. No rules or forwarding settings are changed.
- CSV plus coverage JSON; failures are tracked by mailbox. Successfully read rows
  survive other mailbox failures. A filtered empty report is not proof of safety.
- Does not audit transport rules, effective permissions, malware or message content.

```powershell
.\Scripts\Exchange\Search-InboxRules.ps1 -MailboxIdentity user@contoso.com
.\Scripts\Exchange\Search-InboxRules.ps1 -MailboxIdentity user@contoso.com `
  -IncludeDisabled -IncludeNonSuspicious -SearchText invoice
.\Scripts\Exchange\Search-InboxRules.ps1 -AllMailboxes -PassThru
```

## Message Trace

- Uses Get-MessageTraceV2. No deprecated legacy cmdlet fallback.
- Default last 48 hours; interactive menu also offers last 24 hours or custom UTC.
- One query window <=10 days, Start within last 90 days. No automatic 90-day sweep.
- Filter by sender, recipient, full internet MessageId, MessageTraceId, and status.
- Continuation uses the last response row's Received and RecipientAddress with
  EndDate and StartingRecipientAddress. Deduplicates overlapping rows; stops on
  repeated/non-progressing/out-of-window cursors and reports partial coverage.
- Bounded by MaxResults (default 50,000) and MaxRequests (default 30). Fetches up
  to 5,000 rows per request, pacing subsequent requests by 3.1 seconds. This is
  not a guarantee against throttling across other tools/administrators.
- Service errors preserve prior rows with Complete=false and Issue in coverage
  JSON; they are not exported as a misleading complete result. No trace-query
  automatic retry in this baseline; narrow/rerun after addressing the error.
- Console displays up to 100 rows, CSV holds the collected rows. Zero-row results
  still produce a header and coverage metadata. CSV formula-like strings receive
  an apostrophe prefix; PassThru retains original values.
- Event-detail drilldown (Get-MessageTraceDetailV2) is NOT included in this baseline.
  Trace results are not a message-content/compliance archive.

```powershell
.\Scripts\Exchange\Get-MessageTraceReport.ps1 -SenderAddress user@contoso.com
.\Scripts\Exchange\Get-MessageTraceReport.ps1 -RecipientAddress accounts@contoso.com `
  -StartDate '2026-10-19T00:00:00Z' -EndDate '2026-10-20T00:00:00Z' -PassThru
```

Both scripts use existing Core connection assertion, logging and tenant report
paths. Both tasks are Ready/ReadOnly/PermissionReview=Unreviewed, with only
ExchangeOnline declared and no Graph scopes. Unreviewed prevents opportunistic
permission bundling; it is not a claim of completed production testing.

## What the installer changes

Only the two reporting scripts, matching task manifests, shared report helper,
isolated check script, Pester wrapper and this document. Existing Exchange12
permission helper/fix, mailbox-management/delegation scripts, launcher, settings,
Core and other work are untouched. Listed existing files are backed up then fully
replaced; this is not a three-way text merge. Review local edits in those files.

Backups: %LOCALAPPDATA%\M365AdminToolkit\PatchBackups\ExchangeReports-<unique-id>\
Before/ holds original bytes; Install-Record.json lists added/replaced files.
On copy/post-check failure, rollback is attempted for touched paths; interrupted
processes cannot run rollback. Keep the repo idle during installation. Hashes
check consistency/corruption, not provenance; the package is not digitally signed.

## Validation status

Build environment has no PowerShell. ZIP integrity, manifest hashes and static
packaging checks were verified here. PowerShell parsing, isolated helper checks,
Pester and live tenant behavior were NOT executed here. The installer runs real
PowerShell syntax and isolated helper checks locally before and after copying.
Full regression/live checks are deferred per the baseline-first workflow.

Optional later targeted tests:
Invoke-Pester -Path .\Tests\ExchangeReports.Tests.ps1 -Output Detailed

Public API references used for implementation:
https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-messagetracev2
https://learn.microsoft.com/en-us/defender-office-365/responding-to-a-compromised-email-account
