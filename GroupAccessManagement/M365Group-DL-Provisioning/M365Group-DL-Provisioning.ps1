[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\M365GroupProvisioning-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("Group.ReadWrite.All", "Directory.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]
$exchangeConnected = $false

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

            "createm365group" {
                $ownerUser = Get-MgUser -Filter "userPrincipalName eq '$($row.Owner.Trim())'" -ErrorAction Stop

                $groupParams = @{
                    DisplayName     = $groupName
                    MailNickname    = $row.MailNickname.Trim()
                    Description     = $row.Description
                    MailEnabled     = $true
                    SecurityEnabled = $false
                    GroupTypes      = @("Unified")
                    Visibility      = if ($row.Visibility) { $row.Visibility.Trim() } else { "Private" }
                    "Owners@odata.bind" = @("https://graph.microsoft.com/v1.0/users/$($ownerUser.Id)")
                }

                $newGroup = New-MgGroup -BodyParameter $groupParams
                $status = "Success"
                $message = "Microsoft 365 group created. ObjectId: $($newGroup.Id)"
            }

            "createdistributionlist" {
                if (-not $exchangeConnected) {
                    Connect-ExchangeOnline -ShowBanner:$false
                    $exchangeConnected = $true
                }

                $dlParams = @{
                    Name               = $groupName
                    DisplayName        = $groupName
                    PrimarySmtpAddress = $row.MailNickname.Trim() + "@" + $row.DomainName.Trim()
                    Type               = "Distribution"
                }

                if ($row.Owner) {
                    $dlParams["ManagedBy"] = $row.Owner.Trim()
                }

                New-DistributionGroup @dlParams | Out-Null
                $status = "Success"
                $message = "Distribution list created: $($dlParams.PrimarySmtpAddress)"
            }

            "addmember" {
                $existingGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop
                $memberUser = Get-MgUser -Filter "userPrincipalName eq '$($row.MemberUPN.Trim())'" -ErrorAction Stop

                New-MgGroupMemberByRef -GroupId $existingGroup.Id -BodyParameter @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($memberUser.Id)"
                }

                $status = "Success"
                $message = "Added $($row.MemberUPN) to M365 group."
            }

            "removemember" {
                $existingGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop
                $memberUser = Get-MgUser -Filter "userPrincipalName eq '$($row.MemberUPN.Trim())'" -ErrorAction Stop

                Remove-MgGroupMemberByRef -GroupId $existingGroup.Id -DirectoryObjectId $memberUser.Id

                $status = "Success"
                $message = "Removed $($row.MemberUPN) from M365 group."
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

if ($exchangeConnected) {
    Disconnect-ExchangeOnline -Confirm:$false | Out-Null
}

Disconnect-MgGraph | Out-Null
