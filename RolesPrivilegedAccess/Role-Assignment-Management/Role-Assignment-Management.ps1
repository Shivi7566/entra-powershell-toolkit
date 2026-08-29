[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\RoleAssignment-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("RoleManagement.ReadWrite.Directory", "User.Read.All")
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

            "assignrole" {
                $principal = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
                $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$($row.RoleName.Trim())'" -ErrorAction Stop

                if (-not $roleDefinition) {
                    throw "Role definition '$($row.RoleName)' not found."
                }

                $scopeId = if ($row.DirectoryScopeId) { $row.DirectoryScopeId.Trim() } else { "/" }

                $assignmentParams = @{
                    PrincipalId      = $principal.Id
                    RoleDefinitionId = $roleDefinition.Id
                    DirectoryScopeId = $scopeId
                }

                New-MgRoleManagementDirectoryRoleAssignment -BodyParameter $assignmentParams | Out-Null
                $status = "Success"
                $message = "Assigned role '$($row.RoleName)' to $upn, scope: $scopeId."
            }

            "removerole" {
                $principal = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
                $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$($row.RoleName.Trim())'" -ErrorAction Stop

                $existingAssignment = Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$($principal.Id)' and roleDefinitionId eq '$($roleDefinition.Id)'" -ErrorAction Stop

                if (-not $existingAssignment) {
                    throw "No active assignment found for '$($row.RoleName)' on $upn."
                }

                foreach ($assignment in $existingAssignment) {
                    Remove-MgRoleManagementDirectoryRoleAssignment -UnifiedRoleAssignmentId $assignment.Id
                }

                $status = "Success"
                $message = "Removed role '$($row.RoleName)' from $upn."
            }

            "listroles" {
                $principal = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
                $assignments = Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$($principal.Id)'" -ExpandProperty "roleDefinition"

                $roleNames = $assignments | ForEach-Object { $_.RoleDefinition.DisplayName }
                $status = "Success"
                $message = if ($roleNames) { "Current roles: $($roleNames -join ', ')" } else { "No directory roles currently assigned." }
            }

            "createcustomrole" {
                $allowedActions = $row.AllowedResourceActions.Split(",") | ForEach-Object { $_.Trim() }

                $customRoleParams = @{
                    DisplayName     = $row.RoleName.Trim()
                    Description     = $row.RoleDescription
                    IsEnabled       = $true
                    RolePermissions = @(
                        @{
                            AllowedResourceActions = $allowedActions
                        }
                    )
                }

                $newRole = New-MgRoleManagementDirectoryRoleDefinition -BodyParameter $customRoleParams
                $status = "Success"
                $message = "Created custom role '$($row.RoleName)'. RoleDefinitionId: $($newRole.Id)"
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
