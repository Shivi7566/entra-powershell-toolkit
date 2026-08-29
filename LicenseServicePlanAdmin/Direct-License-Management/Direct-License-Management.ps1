[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [switch]$ReclaimFromDisabledUsers,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\DirectLicense-Management-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("LicenseAssignment.ReadWrite.All", "User.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]
$allSkus = Get-MgSubscribedSku -All

function Get-SkuIdByPartNumber {
    param([string]$PartNumber)
    $match = $allSkus | Where-Object { $_.SkuPartNumber -eq $PartNumber }
    if (-not $match) {
        throw "SKU '$PartNumber' not found in tenant's subscribed SKUs."
    }
    return $match.SkuId
}

if ($CsvPath) {
    if (-not (Test-Path $CsvPath)) {
        throw "CSV file not found at path: $CsvPath"
    }

    $requests = Import-Csv -Path $CsvPath

    foreach ($row in $requests) {

        $action = $row.Action.Trim().ToLower()
        $upn = $row.UserUPN.Trim()
        $status = "Unknown"
        $message = ""

        try {
            $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop

            switch ($action) {

                "assign" {
                    $skuId = Get-SkuIdByPartNumber $row.SkuPartNumber.Trim()

                    Set-MgUserLicense -UserId $user.Id -BodyParameter @{
                        AddLicenses    = @(@{ SkuId = $skuId })
                        RemoveLicenses = @()
                    }
                    $status = "Success"
                    $message = "Assigned $($row.SkuPartNumber) directly to $upn."
                }

                "remove" {
                    $skuId = Get-SkuIdByPartNumber $row.SkuPartNumber.Trim()

                    Set-MgUserLicense -UserId $user.Id -BodyParameter @{
                        AddLicenses    = @()
                        RemoveLicenses = @($skuId)
                    }
                    $status = "Success"
                    $message = "Removed $($row.SkuPartNumber) from $upn."
                }

                "upgrade" {
                    $oldSkuId = Get-SkuIdByPartNumber $row.OldSkuPartNumber.Trim()
                    $newSkuId = Get-SkuIdByPartNumber $row.NewSkuPartNumber.Trim()

                    Set-MgUserLicense -UserId $user.Id -BodyParameter @{
                        AddLicenses    = @(@{ SkuId = $newSkuId })
                        RemoveLicenses = @($oldSkuId)
                    }
                    $status = "Success"
                    $message = "Upgraded $upn from $($row.OldSkuPartNumber) to $($row.NewSkuPartNumber)."
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
            UserUPN   = $upn
            Action    = $row.Action
            Status    = $status
            Message   = $message
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        })
    }
}

if ($ReclaimFromDisabledUsers) {
    $disabledUsers = Get-MgUser -Filter "accountEnabled eq false" -Property "userPrincipalName,accountEnabled,licenseAssignmentStates" -All

    foreach ($disabledUser in $disabledUsers) {

        $directLicenses = $disabledUser.LicenseAssignmentStates | Where-Object { -not $_.AssignedByGroup }

        if ($directLicenses.Count -eq 0) { continue }

        $skuIdsToRemove = $directLicenses | ForEach-Object { $_.SkuId }

        try {
            Set-MgUserLicense -UserId $disabledUser.Id -BodyParameter @{
                AddLicenses    = @()
                RemoveLicenses = $skuIdsToRemove
            }

            $results.Add([PSCustomObject]@{
                UserUPN   = $disabledUser.UserPrincipalName
                Action    = "reclaim"
                Status    = "Success"
                Message   = "Reclaimed $($skuIdsToRemove.Count) directly-assigned license(s) from disabled user."
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            })
        }
        catch {
            $results.Add([PSCustomObject]@{
                UserUPN   = $disabledUser.UserPrincipalName
                Action    = "reclaim"
                Status    = "Failed"
                Message   = $_.Exception.Message
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            })
        }
    }
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
