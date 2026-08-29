[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\GBL-Management-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("LicenseAssignment.ReadWrite.All", "Group.Read.All", "User.Read.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$requests = Import-Csv -Path $CsvPath
$allSkus = Get-MgSubscribedSku -All

foreach ($row in $requests) {

    $action = $row.Action.Trim().ToLower()
    $groupName = $row.GroupName.Trim()
    $status = "Unknown"
    $message = ""

    try {
        switch ($action) {

            "assigngbl" {
                $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop
                $sku = $allSkus | Where-Object { $_.SkuPartNumber -eq $row.SkuPartNumber.Trim() }

                if (-not $sku) {
                    throw "SKU '$($row.SkuPartNumber)' not found in tenant's subscribed SKUs."
                }

                $disabledPlanIds = @()
                if ($row.DisabledPlanNames) {
                    $planNames = $row.DisabledPlanNames.Split(",") | ForEach-Object { $_.Trim() }
                    foreach ($planName in $planNames) {
                        $matchedPlan = $sku.ServicePlans | Where-Object { $_.ServicePlanName -eq $planName }
                        if ($matchedPlan) {
                            $disabledPlanIds += $matchedPlan.ServicePlanId
                        }
                    }
                }

                $licenseParams = @{
                    AddLicenses = @(
                        @{
                            SkuId         = $sku.SkuId
                            DisabledPlans = $disabledPlanIds
                        }
                    )
                    RemoveLicenses = @()
                }

                Set-MgGroupLicense -GroupId $group.Id -BodyParameter $licenseParams
                $status = "Success"
                $message = "Assigned $($row.SkuPartNumber) to group. Disabled plans: $($disabledPlanIds.Count)"
            }

            "removegbl" {
                $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop
                $sku = $allSkus | Where-Object { $_.SkuPartNumber -eq $row.SkuPartNumber.Trim() }

                if (-not $sku) {
                    throw "SKU '$($row.SkuPartNumber)' not found in tenant's subscribed SKUs."
                }

                $licenseParams = @{
                    AddLicenses    = @()
                    RemoveLicenses = @($sku.SkuId)
                }

                Set-MgGroupLicense -GroupId $group.Id -BodyParameter $licenseParams
                $status = "Success"
                $message = "Removed $($row.SkuPartNumber) from group."
            }

            "checkgrouperrors" {
                $group = Get-MgGroup -Filter "displayName eq '$groupName'" -Property "licenseProcessingState,displayName" -ErrorAction Stop
                $processingState = $group.AdditionalProperties["licenseProcessingState"]["state"]

                $members = Get-MgGroupMember -GroupId $group.Id -All
                $errorCount = 0
                $errorDetails = @()

                foreach ($member in $members) {
                    if ($member.AdditionalProperties["@odata.type"] -ne "#microsoft.graph.user") { continue }

                    $memberUser = Get-MgUser -UserId $member.Id -Property "userPrincipalName,licenseAssignmentStates" -ErrorAction SilentlyContinue
                    $errorStates = $memberUser.LicenseAssignmentStates | Where-Object { $_.State -eq "Error" }

                    if ($errorStates) {
                        $errorCount++
                        $errorDetails += "$($memberUser.UserPrincipalName): $($errorStates.Error -join '; ')"
                    }
                }

                $status = "Success"
                $message = "Group processing state: $processingState | Members with license errors: $errorCount"
                if ($errorDetails.Count -gt 0) {
                    $message += " | Details: $($errorDetails -join ' || ')"
                }
            }

            "reprocessuser" {
                $targetUser = Get-MgUser -Filter "userPrincipalName eq '$($row.UserUPN.Trim())'" -ErrorAction Stop
                Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/users/$($targetUser.Id)/reprocessLicenseAssignment" | Out-Null
                $status = "Success"
                $message = "Reprocessing triggered for $($row.UserUPN)."
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
