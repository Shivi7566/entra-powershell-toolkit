[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\GroupMaintenance-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("Group.ReadWrite.All", "Directory.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$requests = Import-Csv -Path $CsvPath

foreach ($row in $requests) {

    $action = $row.Action.Trim().ToLower()
    $groupName = $row.GroupName.Trim()
    $status = "Unknown"
    $message = ""

    try {
        switch ($action) {

            "create" {
                $membershipType = $row.MembershipType.Trim().ToLower()

                $groupParams = @{
                    DisplayName     = $groupName
                    MailNickname    = $row.MailNickname.Trim()
                    Description     = $row.Description
                    MailEnabled     = $false
                    SecurityEnabled = $true
                }

                if ($membershipType -eq "dynamic") {
                    if ([string]::IsNullOrWhiteSpace($row.MembershipRule)) {
                        throw "MembershipRule is required for dynamic groups."
                    }

                    $groupParams["GroupTypes"] = @("DynamicMembership")
                    $groupParams["MembershipRule"] = $row.MembershipRule
                    $groupParams["MembershipRuleProcessingState"] = "On"
                }
                else {
                    $groupParams["GroupTypes"] = @()
                }

                $newGroup = New-MgGroup -BodyParameter $groupParams
                $status = "Success"
                $message = "Group created as $membershipType. ObjectId: $($newGroup.Id)"
            }

            "update" {
                $existingGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop

                $updateParams = @{}
                if ($row.Description) { $updateParams["Description"] = $row.Description }

                if ($row.MembershipRule) {
                    $updateParams["MembershipRule"] = $row.MembershipRule
                    $updateParams["MembershipRuleProcessingState"] = "On"
                }

                Update-MgGroup -GroupId $existingGroup.Id -BodyParameter $updateParams
                $status = "Success"
                $message = "Group updated."
            }

            "delete" {
                $existingGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop
                Remove-MgGroup -GroupId $existingGroup.Id
                $status = "Success"
                $message = "Group deleted."
            }

            "addmember" {
                $existingGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop
                $memberUser = Get-MgUser -Filter "userPrincipalName eq '$($row.MemberUPN.Trim())'" -ErrorAction Stop

                New-MgGroupMemberByRef -GroupId $existingGroup.Id -BodyParameter @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($memberUser.Id)"
                }

                $status = "Success"
                $message = "Added $($row.MemberUPN) to group."
            }

            "removemember" {
                $existingGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop
                $memberUser = Get-MgUser -Filter "userPrincipalName eq '$($row.MemberUPN.Trim())'" -ErrorAction Stop

                Remove-MgGroupMemberByRef -GroupId $existingGroup.Id -DirectoryObjectId $memberUser.Id

                $status = "Success"
                $message = "Removed $($row.MemberUPN) from group."
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
        GroupName = $groupName
        Action    = $row.Action
        Status    = $status
        Message   = $message
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
