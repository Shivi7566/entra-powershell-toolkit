[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [switch]$CheckExpiringAssignments,

    [Parameter(Mandatory = $false)]
    [int]$ExpiringWithinHours = 24,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\PIM-Activation-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("RoleAssignmentSchedule.ReadWrite.Directory", "RoleManagementPolicy.Read.Directory", "User.Read.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if ($CsvPath) {
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
            $principal = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
            $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$($row.RoleName.Trim())'" -ErrorAction Stop

            switch ($action) {

                "selfactivate" {
                    $durationHours = if ($row.DurationHours) { $row.DurationHours.Trim() } else { "8" }

                    $activationParams = @{
                        Action           = "SelfActivate"
                        PrincipalId      = $principal.Id
                        RoleDefinitionId = $roleDefinition.Id
                        DirectoryScopeId = "/"
                        Justification    = if ($row.Justification) { $row.Justification } else { "Self-activation via PIM automation script" }
                        ScheduleInfo     = @{
                            StartDateTime = (Get-Date).ToUniversalTime().ToString("o")
                            Expiration    = @{
                                Type     = "AfterDuration"
                                Duration = "PT$($durationHours)H"
                            }
                        }
                    }

                    New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $activationParams | Out-Null
                    $status = "Success"
                    $message = "Activated '$($row.RoleName)' for $upn, duration: $durationHours hour(s)."
                }

                "deactivate" {
                    $deactivationParams = @{
                        Action           = "SelfDeactivate"
                        PrincipalId      = $principal.Id
                        RoleDefinitionId = $roleDefinition.Id
                        DirectoryScopeId = "/"
                    }

                    New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $deactivationParams | Out-Null
                    $status = "Success"
                    $message = "Deactivated '$($row.RoleName)' for $upn ahead of scheduled expiration."
                }

                "getpolicy" {
                    $policyAssignment = Get-MgPolicyRoleManagementPolicyAssignment -Filter "scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '$($roleDefinition.Id)'" -ErrorAction Stop
                    $policyRules = Get-MgPolicyRoleManagementPolicyRule -UnifiedRoleManagementPolicyId $policyAssignment.PolicyId

                    $maxDurationRule = $policyRules | Where-Object { $_.Id -eq "Expiration_EndUser_Assignment" }
                    $mfaRule = $policyRules | Where-Object { $_.Id -eq "AuthenticationContext_EndUser_Assignment" }
                    $approvalRule = $policyRules | Where-Object { $_.Id -eq "Approval_EndUser_Assignment" }

                    $status = "Success"
                    $message = "Max duration rule found: $($null -ne $maxDurationRule) | MFA-on-activation rule found: $($null -ne $mfaRule) | Approval rule found: $($null -ne $approvalRule). Inspect PolicyId '$($policyAssignment.PolicyId)' directly for full rule detail."
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
}

if ($CheckExpiringAssignments) {
    $cutoff = (Get-Date).ToUniversalTime().AddHours($ExpiringWithinHours)
    $activeInstances = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -All -ExpandProperty "roleDefinition"

    foreach ($instance in $activeInstances) {
        if ($instance.EndDateTime -and [datetime]$instance.EndDateTime -le $cutoff) {
            $principalDetail = Get-MgUser -UserId $instance.PrincipalId -ErrorAction SilentlyContinue

            $results.Add([PSCustomObject]@{
                PrincipalUPN = if ($principalDetail) { $principalDetail.UserPrincipalName } else { $instance.PrincipalId }
                Action       = "expiringcheck"
                Status       = "Flagged"
                Message      = "Role '$($instance.RoleDefinition.DisplayName)' expires at $($instance.EndDateTime)."
                Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            })
        }
    }
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
