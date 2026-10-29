@{
 Id='exchange.get-messagetracereport'
 Name='Message Trace'
 Description='Read-only message trace; CSV export and explicit coverage'
 Script='Get-MessageTraceReport.ps1'
 Order=40
 Status='Ready'
 Services=@('ExchangeOnline')
 GraphScopes=@()
 AccessMode='ReadOnly'
 PermissionReview='Unreviewed'
}
