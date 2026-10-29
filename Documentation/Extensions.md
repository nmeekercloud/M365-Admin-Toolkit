# Discoverable toolkit categories and tasks

Status: local testing required. No live Microsoft 365 or PowerShell tests were run in the build environment.

## Menus
The compact main menu shows category names only. Existing keys 1-6 and T are preserved; Intune uses I. Categories without a Key receive free numbers starting at 10, ordered by Order/Name. Use a unique explicit Key for a stable shortcut (7/8/9/0 and command keys are reserved). Submenus paginate at eight tasks. Press R on main menu to rediscover definitions. Refresh validates before replacing the current catalog.

The old Config/Menu.psd1 is retained as a migration reference but is no longer used at runtime. Change Category.psd1 / *.task.psd1 instead. Discovery reads data files and parses script syntax only: it never executes tasks, connects or installs anything.

## Add a category
From repository root:

    .\Tools\New-ToolkitCategory.ps1 -Folder Custom -Id custom -Name 'Custom Administration' -Order 100

## Add a task
Interactive naming/category prompts:

    .\Tools\New-ToolkitTask.ps1

Or explicit parameters (permissions are EXAMPLES and must match actual task logic):

    .\Tools\New-ToolkitTask.ps1 -Category groups -Name 'My Group Report' -Id groups.my-report -Script Get-MyGroupReport.ps1 -Description 'Custom group report' -Services Graph -GraphScopes Group.Read.All

The helper never overwrites existing scripts. It creates a scaffold and metadata as Planned. Implement and test the script, verify scopes/dependencies, then edit its metadata Status to Ready. -Changes flags the scaffold as a change task; you must implement confirmations, backups, and ShouldProcess yourself. No generator can certify arbitrary custom scripts safe.

The launcher requests the task metadata's services/scopes before executing Ready scripts. The template reads the SAME metadata for standalone use, so it does not independently invent a second permission list. Do not add a separate unconditional Connect-MgGraph. Ready scripts written outside the template remain your responsibility when run standalone.

Raw results should be displayed and passed separately to Export-M365Csv; do not pass Format-Table output. Do not use exit in a task; use return or throw. Do not store real tenant data/secrets in metadata or scripts.

## Definitions
Category.psd1: Id, Name, Order; optional unique Key.
Task .task.psd1: Id, Name, Description, Script, Order, Status, Services, GraphScopes.
Statuses: Planned (visible, cannot run), Disabled (visible, cannot run), Ready (can run if validation succeeds).
Services: Graph, ExchangeOnline, SharePoint. Scopes must be explicitly reviewed before Ready. Intune entries intentionally have no speculative scopes because they are Planned. They do not install Intune modules or request broad permissions.

## Migration
Existing menu entries with no script migrate as Planned. Existing scripts migrate as Disabled pending explicit metadata/permission review. Unknown existing files are not auto-registered or executed. All existing scripts/local settings/.git remain untouched. Definitions are generated once from the current menu, preserving descriptions.

## Validation

    .\Tools\Test-ToolkitCatalog.ps1
    Invoke-Pester -Path .\Tests -Output Detailed
    Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1

Catalog validator catches duplicate IDs/keys, unknown services/status, unsafe script names, missing Ready files and script syntax errors. This is not a secret scanner, API compatibility test, or security sandbox. Discovery is restricted to direct category folders and rejects linked category/task files, but arbitrary custom script actions are NOT sandboxed.

Intune placeholders are proposals, not commitments that every platform exposes every operation through the same API. API versions, licensing, RBAC, platform support and permissions must be verified when implemented. Remote destructive tasks remain Planned; no recovery keys or device credentials are collected by this update.

Duplicate authentication remains unresolved: this structural update retains foundation connection helpers. No assertion that it fixes Microsoft sign-in prompts.

## Manual acceptance tests
- Main menu stays compact; categories 1-6, T and I appear.
- Browse any submenu without sign-in; Intune page navigation works.
- Planned/Disabled options cannot launch.
- Run catalog validator.
- Add a temporary custom category and task via helpers, press R: both appear without editing launcher.
- Keep task Planned: it cannot run. Remove temporary files afterward.
- A malformed definition or duplicate ID makes refresh fail without replacing the last valid catalog.

## Rollback
Close PowerShell. Restore every replaced file from installer backup and remove only files recorded as Existed=false in restore-manifest.json. Removing new directories is optional once empty. No Git-history audit has been performed.
