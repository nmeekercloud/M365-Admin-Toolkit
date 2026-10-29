# Offboarding validation — phases 6 and 7

## Evidence and limitations

The inspected GitHub main baseline includes 6A–6D and 7A/7B implementation.
The 7C installer runs the pinned regression suite before installing these documents.
A successful installation records local offline checks as passed, not live validation.
No Microsoft 365 tenant tests were run by the assistant. This is not production certification.

## Offline coverage

- Real deletion task body executed with its five imports removed and tenant/SDK boundaries mocked.
- Successful single deletion request, immutable endpoint, read verification and SDK context restoration.
- Runtime shared-mailbox, forwarding, unsupported/unknown mailbox and lookup-failure exclusions.
- Failed, unverified, cancelled, missing, duplicate and live-Planned prerequisites.
- Preservation acknowledgement, approval expiry/tenant/target/settings and standalone gating.
- Blocked sign-in, synchronized/guest/self protections and identity drift before deletion.
- WhatIf: no deletion or backup writes.
- Uncertain response: one delete only. Verification failure: retry reads, never delete again.
- Default-No, invalid-choice retry, cancellation, conversion-skips-deletion and planned forwarding.
- Dispatcher approval/result handoff and failure-stop structural contracts.

The dispatcher is checked structurally, NOT executed end-to-end by this suite.
Mailbox snapshot retrieval is mocked for deletion-task tests; live Graph/Exchange permission,
recipient lookup and timing behavior remain unverified. The tests do not authenticate/import SDK.
Pinned hashes deliberately require review when baseline source changes.

## Run installed offline suite

```powershell
& '.\Tests\Offboarding7C\Test-Offboarding7C.ps1' -RepoRoot (Get-Location).Path
```

Run from repo root in a fresh PowerShell 7.4+ session. All tenant command boundaries in the
suite are mocks; never substitute the production task for the suite command.

## Disposable test-tenant checklist — pending until actual operator evidence

| Check | Expected result | Status |
|---|---|---|
| Conversion selected | Blocking/revocation included; deletion prompt absent; account retained | Pending |
| Existing shared mailbox | Deletion excluded | Pending |
| Existing or planned forwarding | Deletion excluded, reason displayed | Pending |
| Mailbox lookup failure | No deletion offered/executed | Pending |
| Default blank/No deletion | Account retained | Pending |
| Cancel initial/final planning | No offboarding mutations | Pending |
| Final plan with deletion Yes | Correct tenant, account/ID, prerequisites and deletion-last warning | Pending |
| Changed eligibility after approval | Deletion stopped | Pending |
| Failed/unverified prerequisite | All dependent work/deletion stopped | Pending |
| WhatIf | Reads/auth allowed, no tenant writes | Pending |
| Single workflow CONFIRM | No duplicate child gate; standalone gates preserved | Pending |
| Approved disposable-account deletion | Same immutable ID verified in Deleted users | Pending |
| Graph failure/uncertain result | Stop, inspect manually; no blind retry | Pending |

Record date, source commit, scenario and actual result; do not record credentials, tokens or
customer-identifying test data in repository history. Do not claim a live pass from a mock.
Code rollback does not undo tenant changes or restore deleted accounts.
