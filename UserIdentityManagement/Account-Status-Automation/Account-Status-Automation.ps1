[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\AccountStatusAutomation-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("User.ReadWrite.All", "Directory.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$accounts = Import-Csv -Path $CsvPath

foreach ($row in $accounts) {

    $action = $row.Action.Trim().ToLower()
    $upn = $row.UserPrincipalName.Trim()
    $status = "Unknown"
    $message = ""

    try {
        switch ($action) {

            "enable" {
                $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
                Update-MgUser -UserId $user.Id -AccountEnabled:$true
                $status = "Success"
                $message = "Account enabled."
            }

            "disable" {
                $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
                Update-MgUser -UserId $user.Id -AccountEnabled:$false
                Revoke-MgUserSignInSession -UserId $user.Id | Out-Null
                $status = "Success"
                $message = "Account disabled and sessions revoked."
            }

            "lock" {
                $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop

                $randomPassword = [System.Guid]::NewGuid().ToString("N").Substring(0, 20) + "!Aa1"
                $passwordProfile = @{
                    Password = $randomPassword
                    ForceChangePasswordNextSignIn = $true
                }

                Update-MgUser -UserId $user.Id -AccountEnabled:$false -PasswordProfile $passwordProfile
                Revoke-MgUserSignInSession -UserId $user.Id | Out-Null

                $status = "Success"
                $message = "Account locked: disabled, password randomized, sessions revoked."
            }

            "softdelete" {
                $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
                Remove-MgUser -UserId $user.Id
                $status = "Success"
                $message = "Account soft-deleted. Recoverable for 30 days."
            }

            "restore" {
                $deletedUser = Get-MgDirectoryDeletedItemAsUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop

                if (-not $deletedUser) {
                    throw "No soft-deleted account found with UPN $upn."
                }

                Restore-MgDirectoryDeletedItem -DirectoryObjectId $deletedUser.Id | Out-Null
                $status = "Success"
                $message = "Account restored from soft-delete."
            }

            "harddelete" {
                $deletedUser = Get-MgDirectoryDeletedItemAsUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop

                if (-not $deletedUser) {
                    throw "No soft-deleted account found with UPN $upn — nothing to permanently delete."
                }

                Remove-MgDirectoryDeletedItem -DirectoryObjectId $deletedUser.Id
                $status = "Success"
                $message = "Account permanently deleted. This cannot be undone."
            }

            default {
                $status = "Skipped"
                $message = "Unrecognized action value: $($row.Action)"
            }
        }
    }
    catch {
        $status = "Failed"
        $message = $_.Exception.Message
    }

    $results.Add([PSCustomObject]@{
        UserPrincipalName = $upn
        Action            = $row.Action
        Status            = $status
        Message           = $message
        Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
