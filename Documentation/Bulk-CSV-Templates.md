# Bulk CSV templates

The bundled templates for the three supported bulk-change workflows are in
Templates/CSV. They contain column headers only, with no customer rows.

| Workflow | Template | Columns |
|---|---|---|
| Bulk User Updates | Templates/CSV/Bulk-User-Edits-Template.csv | Action,UserPrincipalName,DisplayName,Department,JobTitle,OfficeLocation |
| Bulk Add Group Members | Templates/CSV/Bulk-Group-Members-Template.csv | GroupId,UserPrincipalName |
| Bulk Grant SharePoint Site Access | Templates/CSV/Bulk-SharePoint-Access-Template.csv | SiteUrl,SharePointGroupId,UserPrincipalName |

## Using a template

Each supported task displays its template path, required columns and input rules
before requesting a CSV path. At the prompt, enter T to save a blank working copy.
Choose a full destination filename.csv outside the toolkit repository. Missing
parent directories and overwriting an existing file require explicit approval.
Cancelling template saving returns to the input prompt; cancelling input stops
before the task imports CSV data. No working copy is written automatically.

Populate the separate working copy, not the bundled template. Keep real customer
CSV files outside the repository and never commit them. The template saver rejects
bundled templates that are missing or no longer match their registered header.
Header-only files are not populated bulk input.

## Input rules

- Users: Action is Update, Enable or Disable. Blank profile cells leave existing
  values unchanged; Enable/Disable rows must leave profile fields blank. No bulk
  creation, deletion, licensing or password-reset actions are added by this task.
- Groups: GroupId is an Entra group object GUID. Use canonical user sign-in UPNs.
  Existing restrictions on group types, membership and eligible users still apply.
- SharePoint: use a site-collection URL, an existing positive site-local SharePoint
  group ID and a supported individual user's canonical UPN. An Entra group GUID
  is not a SharePointGroupId. This task does not add Entra security-group support.

The registry is Config/BulkCsvTemplates.psd1. Moving a shipped template requires
updating that registry so prompts and blank-copy saving find the correct file.
Existing approval, preflight, backup and mutation safeguards remain in effect.

## Noninteractive use

For the supported tasks, NoInteractive requires an explicit populated CsvPath;
it does not create a template or prompt for input. Review each task's parameters
and validate data before running against a tenant.
