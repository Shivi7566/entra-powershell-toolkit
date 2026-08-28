[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$GroupNamesCsv,

    [Parameter(Mandatory = $false)]
    [switch]$RemoveDisabledMembers,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\GroupAudit-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("Group.ReadWrite.All", "User.Read.All", "Directory.Read.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$findings = New-Object System.Collections.Generic.List[Object]

if ($GroupNamesCsv) {
    if (-not (Test-Path $GroupNamesCsv)) {
        throw "Group list CSV not found at path: $GroupNamesCsv"
    }
    $targetNames = (Import-Csv -Path $GroupNamesCsv) | ForEach-Object { $_.GroupName.Trim() }
    $groupsToAudit = $targetNames | ForEach-Object { Get-MgGroup -Filter "displayName eq '$_'" }
}
else {
    $groupsToAudit = Get-MgGroup -All
}

foreach ($group in $groupsToAudit) {

    if (-not $group) { continue }

    $groupName = $group.DisplayName
    $owners = Get-MgGroupOwner -GroupId $group.Id
    $members = Get-MgGroupMember -GroupId $group.Id -All

    if ($owners.Count -eq 0) {
        $findings.Add([PSCustomObject]@{
            GroupName = $groupName
            GroupId   = $group.Id
            Finding   = "OwnerlessGroup"
            Detail    = "Group has zero owners."
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        })
    }

    if ($members.Count -eq 0) {
        $findings.Add([PSCustomObject]@{
            GroupName = $groupName
            GroupId   = $group.Id
            Finding   = "EmptyGroup"
            Detail    = "Group has zero members."
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        })
    }

    foreach ($member in $members) {
        if ($member.AdditionalProperties["@odata.type"] -ne "#microsoft.graph.user") {
            continue
        }

        $memberDetail = Get-MgUser -UserId $member.Id -Property "accountEnabled,userPrincipalName" -ErrorAction SilentlyContinue

        if ($memberDetail -and $memberDetail.AccountEnabled -eq $false) {
            $findings.Add([PSCustomObject]@{
                GroupName = $groupName
                GroupId   = $group.Id
                Finding   = "DisabledMemberStillInGroup"
                Detail    = "Disabled user still a member: $($memberDetail.UserPrincipalName)"
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            })

            if ($RemoveDisabledMembers) {
                Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $member.Id
                $findings.Add([PSCustomObject]@{
                    GroupName = $groupName
                    GroupId   = $group.Id
                    Finding   = "CleanupPerformed"
                    Detail    = "Removed disabled user from group: $($memberDetail.UserPrincipalName)"
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                })
            }
        }
    }
}

if ($findings.Count -eq 0) {
    Write-Host "No issues found across $($groupsToAudit.Count) group(s) audited."
}

$findings | Export-Csv -Path $LogPath -NoTypeInformation
$findings | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
