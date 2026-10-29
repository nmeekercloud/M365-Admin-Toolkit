# Testing the toolkit

## Scope and safety

Keep automated/offline results separate from live tenant validation. A successful
patch installation or passing offline suite does not prove live tenant behavior.
Use a dedicated test tenant and disposable objects for functional testing. A Git
branch is a code boundary, not a tenant isolation boundary.

No spreadsheet or catalog inventory snapshot is required. Record sanitized test
results in a GitHub issue or private test record. Identify the exact commit, date,
scenario, expected result, actual result, and any skipped or blocked coverage.
If the working tree is modified, record that fact and the corresponding diff.
Never commit customer data, real tenant identifiers, credentials, tokens, or
unredacted runtime artifacts. Keep sensitive evidence outside the repository.

## Offline validation

Use a fresh PowerShell 7 console. Inspect the build and working tree first.
Use already-installed Pester 5 to run the relevant suites in Tests. Use
PSScriptAnalyzer with PSScriptAnalyzerSettings.psd1 when available. Do not install
or update modules as part of a test without explicit approval. Record unavailable
tooling, skipped tests and failures honestly. Automated tests must stay offline
and non-destructive.

The maintained output-regression runner in Tools can validate its supported
suites independently. Read the runner's parameters and coverage before using it;
its success is not evidence that every toolkit workflow was exercised.

## Live validation order

1. Startup, dependency inspection, authentication and tenant identity guards.
2. Menus, output paths, activity logging and cancellation.
3. Read-only reports against small fixtures with known expected results.
4. Reversible membership and settings changes on disposable test objects.
5. OneDrive archive, collision and failure paths using disposable files.
6. Offboarding and deletion last, with retention and recovery understood.
7. Repeat relevant tests after each fix against the exact candidate build.

Inspect partial-coverage reports and actual tenant state, not only success text.
Record blocked cases with a reason. Preserve older evidence without implying it
covers newer builds. A historical sign-off applies only to its recorded scope.
