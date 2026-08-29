[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string[]]$MonitorAccountUPNs,

    [Parameter(Mandatory = $false)]
    [int]$SignInLookbackDays = 7,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\BreakGlass-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

function New-StrongRandomPassword {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $base = [Convert]::ToBase64String($bytes).Substring(0, 28)
    return "$base!Zx9#"
}

$requiredScopes = @("User.ReadWrite.All", "RoleManagement.ReadWrite.Directory", "AuditLog.Read.All", "Policy.Read.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if ($CsvPath) {
    if (-not (Test-Path $CsvPath)) {
        throw "CSV file not found at path: $CsvPath"
    }

    $accountsToCreate = Import-Csv -Path $CsvPath

    foreach ($row in $accountsToCreate) {

        $upn = $row.UserPrincipalName.Trim()
        $status = "Unknown"
        $message = ""

        try {
            $generatedPassword = New-StrongRandomPassword

            $newUserParams = @{
                AccountEnabled    = $true
                DisplayName       = $row.DisplayName
                UserPrincipalName = $upn
                MailNickname      = $row.MailNickname.Trim()
                PasswordPolicies  = "DisablePasswordExpiration"
                PasswordProfile   = @{
                    Password                      = $generatedPassword
                    ForceChangePasswordNextSignIn = $false
                }
            }

            $newAccount = New-MgUser -BodyParameter $newUserParams

            $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq 'Global Administrator'" -ErrorAction Stop

            New-MgRoleManagementDirectoryRoleAssignment -BodyParameter @{
                PrincipalId      = $newAccount.Id
                RoleDefinitionId = $roleDefinition.Id
                DirectoryScopeId = "/"
            } | Out-Null

            $status = "Success"
            $message = "Break-glass account created and assigned permanent Global Administrator. GENERATED PASSWORD (store immediately, do not leave in this log): $generatedPassword"
        }
        catch {
            $status = "Failed"
            $message = $_.Exception.Message
        }

        $results.Add([PSCustomObject]@{
            UserPrincipalName = $upn
            Action            = "setup"
            Status            = $status
            Message           = $message
            Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        })
    }
}

if ($MonitorAccountUPNs -and $MonitorAccountUPNs.Count -gt 0) {

    $lookbackStart = (Get-Date).ToUniversalTime().AddDays(-$SignInLookbackDays).ToString("o")

    foreach ($monitorUpn in $MonitorAccountUPNs) {

        $monitoredUser = Get-MgUser -Filter "userPrincipalName eq '$monitorUpn'" -ErrorAction SilentlyContinue

        if (-not $monitoredUser) {
            $results.Add([PSCustomObject]@{
                UserPrincipalName = $monitorUpn
                Action            = "monitor"
                Status            = "Failed"
                Message           = "Account not found."
                Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            })
            continue
        }

        $signInFilter = "userId eq '$($monitoredUser.Id)' and createdDateTime ge $lookbackStart"
        $recentSignIns = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=$signInFilter"

        if ($recentSignIns.value.Count -gt 0) {
            $results.Add([PSCustomObject]@{
                UserPrincipalName = $monitorUpn
                Action            = "monitor"
                Status            = "ALERT"
                Message           = "$($recentSignIns.value.Count) sign-in(s) detected in the last $SignInLookbackDays day(s). Investigate immediately — break-glass accounts should not sign in during normal operations."
                Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            })
        }
        else {
            $results.Add([PSCustomObject]@{
                UserPrincipalName = $monitorUpn
                Action            = "monitor"
                Status            = "Clean"
                Message           = "No sign-in activity in the last $SignInLookbackDays day(s)."
                Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            })
        }

        $allCaPolicies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"
        $unexcludedPolicies = @()

        foreach ($policy in $allCaPolicies.value) {
            if ($policy.state -ne "enabled") { continue }
            $excludedUsers = $policy.conditions.users.excludeUsers
            if ($monitoredUser.Id -notin $excludedUsers) {
                $unexcludedPolicies += $policy.displayName
            }
        }

        if ($unexcludedPolicies.Count -gt 0) {
            $results.Add([PSCustomObject]@{
                UserPrincipalName = $monitorUpn
                Action            = "ca-exclusion-check"
                Status            = "Warning"
                Message           = "Not excluded from $($unexcludedPolicies.Count) enabled CA polic(ies): $($unexcludedPolicies -join ', ')"
                Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            })
        }
        else {
            $results.Add([PSCustomObject]@{
                UserPrincipalName = $monitorUpn
                Action            = "ca-exclusion-check"
                Status            = "Clean"
                Message           = "Properly excluded from all enabled Conditional Access policies."
                Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            })
        }
    }
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
