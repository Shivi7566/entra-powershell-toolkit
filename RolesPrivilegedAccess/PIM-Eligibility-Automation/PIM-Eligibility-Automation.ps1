[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\PIM-Eligibility-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("RoleEligibilitySchedule.ReadWrite.Directory", "RoleManagement.ReadWrite.Directory", "User.Read.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$requests = Import-Csv -Path $CsvPath

foreach ($row in $requests) {

    $action = $row.Action.Trim().ToLower()
    $upn = $row.PrincipalUPN.Trim()
    $status = "Unknown"
    $message = ""

    try {
        switch ($action) {

            "makeeligible" {
                $principal = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
                $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$($row.RoleName.Trim())'" -ErrorAction Stop

                $expiration = if ($row.DurationDays) {
                    @{
                        Type     = "AfterDuration"
                        Duration = "P$($row.DurationDays.Trim())D"
                    }
                } else {
                    @{ Type = "NoExpiration" }
                }

                $eligibilityParams = @{
                    Action           = "AdminAssign"
                    PrincipalId      = $principal.Id
                    RoleDefinitionId = $roleDefinition.Id
                    DirectoryScopeId = "/"
                    Justification    = if ($row.Justification) { $row.Justification } else { "Bulk PIM eligibility automation" }
                    ScheduleInfo     = @{
                        StartDateTime = (Get-Date).ToUniversalTime().ToString("o")
                        Expiration    = $expiration
                    }
                }

                New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -BodyParameter $eligibilityParams | Out-Null
                $status = "Success"
                $message = "Made $upn PIM-eligible for '$($row.RoleName)'. Expiration: $($expiration.Type)"
            }

            "removeeligibility" {
                $principal = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
                $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$($row.RoleName.Trim())'" -ErrorAction Stop

                $removalParams = @{
                    Action           = "AdminRemove"
                    PrincipalId      = $principal.Id
                    RoleDefinitionId = $roleDefinition.Id
                    DirectoryScopeId = "/"
                    Justification    = if ($row.Justification) { $row.Justification } else { "Bulk PIM eligibility removal" }
                }

                New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -BodyParameter $removalParams | Out-Null
                $status = "Success"
                $message = "Removed PIM eligibility for '$($row.RoleName)' from $upn."
            }

            "listeligible" {
                $principal = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
                $eligibleInstances = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter "principalId eq '$($principal.Id)'" -ExpandProperty "roleDefinition"

                $roleNames = $eligibleInstances | ForEach-Object { $_.RoleDefinition.DisplayName }
                $status = "Success"
                $message = if ($roleNames) { "Currently eligible for: $($roleNames -join ', ')" } else { "No active PIM eligibility found." }
            }

            "listactive" {
                $principal = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
                $activeInstances = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -Filter "principalId eq '$($principal.Id)'" -ExpandProperty "roleDefinition"

                $roleNames = $activeInstances | ForEach-Object { $_.RoleDefinition.DisplayName }
                $status = "Success"
                $message = if ($roleNames) { "Currently active (time-bound) assignments: $($roleNames -join ', ')" } else { "No currently active PIM assignments." }
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
        PrincipalUPN = $upn
        Action       = $row.Action
        Status       = $status
        Message      = $message
        Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
