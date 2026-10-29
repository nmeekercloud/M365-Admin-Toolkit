@{
    SchemaVersion = 1
    # Sidecar metadata plus optional branches and child workflows.
    Tasks = @{
        'users.new-user' = @{
            GraphScopes=@('User.ReadWrite.All','LicenseAssignment.Read.All','Group.Read.All','GroupMember.ReadWrite.All')
            Services=@('Graph')
        }
        'users.invoke-bulkusermanagement' = @{
            GraphScopes=@('User.Read.All','User.ReadWrite.All','User.EnableDisableAccount.All','User.RevokeSessions.All')
            Services=@('Graph')
        }
        'users.disable-user' = @{
            # Optional account deletion must be declared before task dispatch.
            GraphScopes=@('User.ReadWrite.All')
            Dependencies=@('users.block-access','exchange.convert-shared','exchange.set-mailboxforwarding','exchange.set-mailboxautoreply','exchange.set-mailboxdelegates','users.remove-licenses','onedrive.backup-onedrive')
        }
        'users.remove-licenses' = @{
            GraphScopes=@('User.Read.All','LicenseAssignment.ReadWrite.All')
            Services=@('Graph','ExchangeOnline')
        }
        'users.block-access' = @{ GraphScopes=@('User.Read.All','User.EnableDisableAccount.All','User.RevokeSessions.All') }
        'users.copy-useraccess' = @{ GraphScopes=@('User.Read.All','Group.Read.All','GroupMember.ReadWrite.All') }
        'exchange.convert-shared' = @{ Services=@('Graph','ExchangeOnline'); GraphScopes=@('User.Read.All') }
        'exchange.set-mailboxforwarding' = @{ Services=@('Graph','ExchangeOnline'); GraphScopes=@('User.Read.All') }
        'exchange.set-mailboxautoreply' = @{ Services=@('Graph','ExchangeOnline'); GraphScopes=@('User.Read.All') }
        'exchange.set-mailboxdelegates' = @{ Services=@('Graph','ExchangeOnline'); GraphScopes=@('User.Read.All') }
    }
}
