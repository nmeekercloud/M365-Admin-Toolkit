# Archive-only identity guard. No network calls or changes on dot-source.
function Assert-ODArchiveMember {
    <#
    .SYNOPSIS
    Validate the archive subject without applying directory-write restrictions.
    .DESCRIPTION
    Both cloud-only and directory-synchronized Member accounts may own OneDrive
    content. This task moves cloud content; it does not update the AD identity.
    Shared Member eligibility is separate; neither guard rejects sync status alone.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$User,
        [Parameter(Mandatory)][object]$Tenant
    )
    $tenantId=[guid]::Empty
    if (-not [guid]::TryParse([string]$Tenant.TenantId,[ref]$tenantId) -or
        $tenantId -eq [guid]::Empty -or
        [string]::IsNullOrWhiteSpace([string]$Tenant.Account)) {
        throw 'A verified tenant and signed-in account are required for OneDrive archive.'
    }
    if ([string]$User['userType'] -ine 'Member') {
        throw 'OneDrive archive supports tenant Member accounts only, not guests or unknown user types.'
    }
    $userId=[guid]::Empty
    if (-not [guid]::TryParse([string]$User['id'],[ref]$userId) -or
        $userId -eq [guid]::Empty -or
        [string]::IsNullOrWhiteSpace([string]$User['userPrincipalName'])) {
        throw 'OneDrive archive requires a resolved user object ID and canonical UPN.'
    }
    if ([string]$User['userPrincipalName'] -ieq [string]$Tenant.Account) {
        throw 'Archiving the signed-in account through this task is blocked.'
    }
    # onPremisesSyncEnabled deliberately does not decide eligibility here.
    # OneDrive/site permissions and archive-specific preflight still apply.
}
