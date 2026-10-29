# Early bundled-package prerequisites - 2026-10-21

## Evidence and root cause boundary

On the work computer, PowerShell 7.6.7 x64 had both the old user-scoped
PackageManagement 1.1.0.0 and bundled 1.4.8.1 available. The toolkit rejected an
incompatible module at connection time. Explicitly importing PSHOME's bundled
PackageManagement 1.4.8.1 then PowerShellGet 2.2.5 in a fresh process allowed the
connection test to succeed, as reported by Nathan. This is a module-loading issue,
not established evidence of Windows Home versus Pro or toolkit-folder placement.
The exact earlier loader of the old module has not been proven.

The inspected main launcher did not invoke bundled-package preparation before its
installed-dependency inventory. Existing service compatibility preparation occurred
later at a service boundary. This patch moves PACKAGE-TOOL preparation early;
it does not preload Graph, Exchange or PnP SDKs into the startup prerequisite step.

## Behavior

- After existing Windows/x64/version gates but BEFORE Core import, dependency
  inventory, provider discovery or authentication: validate the two PSHOME manifests.
- Explicitly import bundled PackageManagement 1.4.8.1, then PowerShellGet 2.2.5,
  by absolute manifest path with Global scope; verify loaded versions/roots.
- Detect already loaded incompatible versions/locations and stale package DLLs.
  Stop with fresh 64-bit pwsh -NoProfile guidance; no attempted DLL unload,
  Remove-Module workaround, profile editing, PSModulePath editing or uninstall.
- If already correct, preparation is idempotent. Older copies may remain installed
  but unused. Missing/mismatched bundled manifests fail before either import.
- -SkipDependencyCheck still performs this process-safety preparation; only the
  optional installed-module inventory is skipped.
- Install-M365Dependencies also prepares package tools before installation-provider
  discovery. -CheckOnly remains inspection-only. -WhatIf does not discover/load the
  installation provider or preload package tools from that installer function.
- Core import remains definition-only for the new helper; no package tools or SDKs
  are loaded merely by importing M365Toolkit.Core. Existing compatibility profile
  versions, SDK selection, authentication and task approvals are unchanged.
- Standalone service calls retain the existing compatibility guard. Already dirty
  sessions cannot be repaired by unloading DLLs; use a fresh process.

## Standard local patch installation

Extract separately, open 64-bit PowerShell 7 in the extracted patch folder, unblock
trusted files, run Install-Patch.ps1 -ToolkitPath <actual toolkit root>, answer Y.
-WhatIf is optional. Baseline checks, syntax, backup hashes and post-checks run.
No module import/install/login or tenant action occurs DURING PATCH INSTALLATION.
The package bootstrap runs when the patched toolkit is launched later.

This patch transforms the two exact baseline files rather than replacing a whole
repository. Baseline mismatch blocks it. New helper/tests/doc files must be absent
or byte-identical; unexpected local edits are not overwritten. The changelog entry
is inserted under Unreleased while preserving all prior content. No Git action,
version bump or release tag occurs. Backups are under LOCALAPPDATA/M365AdminToolkit/
PatchBackups/EarlyPackagePrerequisites-<unique-id>; failed installs attempt rollback.
Interrupted processes cannot run rollback; inspect Install-Record.json and originals.

## Validate without manual preparation

1. Apply the patch, then exit the currently prepared toolkit/session.
2. Start a NEW 64-bit PowerShell 7 process with -NoProfile. Do NOT manually import
   PackageManagement/PowerShellGet. Launch the patched Start-M365Toolkit.ps1 normally.
3. Expect the bundled-prerequisite readiness message BEFORE the menu; check a
   Graph-only connection through Tenant/Connection Options. Do not use offboarding
   as the connection test. Record the exact output/build in the testing tracker.
4. Repeat fresh with -SkipDependencyCheck: safety preparation must still occur.
5. Later run targeted Pester, then the existing compatibility/regression suites:

Invoke-Pester -Path .\Tests\PackagePrerequisites.Tests.ps1 -Output Detailed

A controlled dirty-session test must stop early rather than proceed with old DLLs;
do not contaminate a production working session just to test that scenario.

## Validation status

Authoring environment has no PowerShell. ZIP/hash/anchor/payload checks were run,
not PowerShell parser, Pester, actual module imports or fresh-launch authentication.
Installer runs real parsing and isolated synthetic guard/wiring checks locally;
it does not run live imports or launch the toolkit to claim connection success.
Mock tests cover ordering, idempotency, missing/mismatched manifests and dirty-state
refusal. Live confirmation of automatic preparation remains pending after apply.
The manual preload plus connection succeeded before this patch; keep that result
separate from the untested automatic startup path. Package hashes are not signatures.
