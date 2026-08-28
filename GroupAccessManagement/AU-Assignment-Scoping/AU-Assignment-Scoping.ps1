[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\AUAssignmentScoping-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("AdministrativeUnit.ReadWrite.All", "RoleManagement.ReadWrite.Directory")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$requests = Import-Csv -Path $CsvPath

foreach ($row in $requests) {

    $action = $row.Action.Trim().ToLower()
    $auName = $row.AUName.Trim()
    $status = "Unknown"
    $message = ""

    try {
        $au = Get-MgDirectoryAdministrativeUnit -Filter "displayName eq '$auName'" -ErrorAction Stop

        switch ($action) {

            "addmember" {
                $memberType = $row.MemberType.Trim().ToLower()

                $memberId = if ($memberType -eq "group") {
                    (Get-MgGroup -Filter "displayName eq '$($row.MemberIdentifier.Trim())'" -ErrorAction Stop).Id
                } else {
                    (Get-MgUser -Filter "userPrincipalName eq '$($row.MemberIdentifier.Trim())'" -ErrorAction Stop).Id
                }

                New-MgDirectoryAdministrativeUnitMemberByRef -AdministrativeUnitId $au.Id -BodyParameter @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$memberId"
                }

                $status = "Success"
                $message = "Added $memberType '$($row.MemberIdentifier)' to AU '$auName'."
            }

            "removemember" {
                $memberType = $row.MemberType.Trim().ToLower()

                $memberId = if ($memberType -eq "group") {
                    (Get-MgGroup -Filter "displayName eq '$($row.MemberIdentifier.Trim())'" -ErrorAction Stop).Id
                } else {
                    (Get-MgUser -Filter "userPrincipalName eq '$($row.MemberIdentifier.Trim())'" -ErrorAction Stop).Id
                }

                Remove-MgDirectoryAdministrativeUnitMemberByRef -AdministrativeUnitId $au.Id -DirectoryObjectId $memberId

                $status = "Success"
                $message = "Removed $memberType '$($row.MemberIdentifier)' from AU '$auName'."
            }

            "assignscopedrole" {
                $roleTemplate = Get-MgDirectoryRoleTemplate -Filter "displayName eq '$($row.RoleName.Trim())'" -ErrorAction Stop
                $principalUser = Get-MgUser -Filter "userPrincipalName eq '$($row.PrincipalUPN.Trim())'" -ErrorAction Stop

                $scopedRoleParams = @{
                    RoleId = $roleTemplate.Id
                    RoleMemberInfo = @{
                        Id = $principalUser.Id
                    }
                }

                New-MgDirectoryAdministrativeUnitScopedRoleMember -AdministrativeUnitId $au.Id -BodyParameter $scopedRoleParams
                $status = "Success"
                $message = "Assigned scoped role '$($row.RoleName)' to $($row.PrincipalUPN) within AU '$auName'."
            }

            "removescopedrole" {
                $scopedMembers = Get-MgDirectoryAdministrativeUnitScopedRoleMember -AdministrativeUnitId $au.Id
                $principalUser = Get-MgUser -Filter "userPrincipalName eq '$($row.PrincipalUPN.Trim())'" -ErrorAction Stop

                $matchingAssignment = $scopedMembers | Where-Object { $_.RoleMemberInfo.Id -eq $principalUser.Id }

                if (-not $matchingAssignment) {
                    throw "No scoped role assignment found for $($row.PrincipalUPN) in AU '$auName'."
                }

                Remove-MgDirectoryAdministrativeUnitScopedRoleMember -AdministrativeUnitId $au.Id -ScopedRoleMembershipId $matchingAssignment.Id
                $status = "Success"
                $message = "Removed scoped role assignment for $($row.PrincipalUPN) from AU '$auName'."
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
        AUName    = $auName
        Action    = $row.Action
        Status    = $status
        Message   = $message
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
