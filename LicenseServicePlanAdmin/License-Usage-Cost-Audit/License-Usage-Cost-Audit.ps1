[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$InactiveDaysThreshold = 90,

    [Parameter(Mandatory = $false)]
    [string]$SkuUtilizationLogPath = ".\SkuUtilization-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv",

    [Parameter(Mandatory = $false)]
    [string]$InactiveUsersLogPath = ".\InactiveLicensedUsers-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv",

    [Parameter(Mandatory = $false)]
    [string]$MultiLicenseLogPath = ".\MultiLicenseUsers-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("Organization.Read.All", "User.Read.All", "AuditLog.Read.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$allSkus = Get-MgSubscribedSku -All

$skuUtilization = New-Object System.Collections.Generic.List[Object]

foreach ($sku in $allSkus) {
    $prepaidEnabled = $sku.PrepaidUnits.Enabled
    $consumed = $sku.ConsumedUnits
    $available = $prepaidEnabled - $consumed
    $utilizationPercent = if ($prepaidEnabled -gt 0) { [math]::Round(($consumed / $prepaidEnabled) * 100, 1) } else { 0 }

    $skuUtilization.Add([PSCustomObject]@{
        SkuPartNumber      = $sku.SkuPartNumber
        PrepaidEnabled     = $prepaidEnabled
        ConsumedUnits      = $consumed
        AvailableUnits     = $available
        UtilizationPercent = $utilizationPercent
    })
}

$skuUtilization | Export-Csv -Path $SkuUtilizationLogPath -NoTypeInformation
Write-Host "SKU utilization report:"
$skuUtilization | Sort-Object AvailableUnits -Descending | Format-Table -AutoSize

$allUsers = Get-MgUser -All -Property "userPrincipalName,assignedLicenses,signInActivity" -ConsistencyLevel eventual

$inactiveLicensedUsers = New-Object System.Collections.Generic.List[Object]
$multiLicenseUsers = New-Object System.Collections.Generic.List[Object]
$cutoffDate = (Get-Date).AddDays(-$InactiveDaysThreshold)

foreach ($licensedUser in $allUsers) {

    if ($licensedUser.AssignedLicenses.Count -eq 0) { continue }

    $lastSignIn = $licensedUser.SignInActivity.LastSignInDateTime
    $resolvedSkuNames = @()
    foreach ($assignedLicense in $licensedUser.AssignedLicenses) {
        $matchedSku = $allSkus | Where-Object { $_.SkuId -eq $assignedLicense.SkuId }
        if ($matchedSku) { $resolvedSkuNames += $matchedSku.SkuPartNumber }
    }
    $skuNames = $resolvedSkuNames -join ", "

    if (-not $lastSignIn -or [datetime]$lastSignIn -lt $cutoffDate) {
        $inactiveLicensedUsers.Add([PSCustomObject]@{
            UserPrincipalName = $licensedUser.UserPrincipalName
            LastSignIn        = if ($lastSignIn) { $lastSignIn } else { "Never" }
            AssignedSkuCount  = $licensedUser.AssignedLicenses.Count
            AssignedSkus      = $skuNames
        })
    }

    if ($licensedUser.AssignedLicenses.Count -gt 1) {
        $multiLicenseUsers.Add([PSCustomObject]@{
            UserPrincipalName = $licensedUser.UserPrincipalName
            AssignedSkuCount  = $licensedUser.AssignedLicenses.Count
            AssignedSkus      = $skuNames
        })
    }
}

$inactiveLicensedUsers | Export-Csv -Path $InactiveUsersLogPath -NoTypeInformation
$multiLicenseUsers | Export-Csv -Path $MultiLicenseLogPath -NoTypeInformation

Write-Host "`nInactive licensed users (no sign-in in $InactiveDaysThreshold+ days): $($inactiveLicensedUsers.Count)"
$inactiveLicensedUsers | Format-Table -AutoSize

Write-Host "`nUsers holding more than one license SKU (review for possible overlap): $($multiLicenseUsers.Count)"
$multiLicenseUsers | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
