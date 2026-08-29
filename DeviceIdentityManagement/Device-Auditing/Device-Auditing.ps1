[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$StaleThresholdDays = 90,

    [Parameter(Mandatory = $false)]
    [string]$InventoryLogPath = ".\Device-Inventory-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv",

    [Parameter(Mandatory = $false)]
    [string]$SummaryLogPath = ".\Device-Summary-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("Device.Read.All", "Directory.Read.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

Write-Host "Retrieving all devices in the tenant..."
$allDevices = Get-MgDevice -All -Property "displayName,deviceId,trustType,operatingSystem,operatingSystemVersion,isCompliant,isManaged,approximateLastSignInDateTime,accountEnabled"

$now = Get-Date
$staleCutoff = $now.AddDays(-$StaleThresholdDays)
$inventory = New-Object System.Collections.Generic.List[Object]

foreach ($device in $allDevices) {

    $joinType = switch ($device.TrustType) {
        "AzureAd"  { "Microsoft Entra Joined" }
        "ServerAd" { "Hybrid Microsoft Entra Joined" }
        "Workplace" { "Microsoft Entra Registered" }
        default    { "Unknown" }
    }

    $owners = Get-MgDeviceRegisteredOwner -DeviceId $device.Id -ErrorAction SilentlyContinue
    $ownerUpn = if ($owners) { ($owners | ForEach-Object { $_.AdditionalProperties["userPrincipalName"] }) -join ", " } else { "" }

    $lastSignIn = $device.ApproximateLastSignInDateTime
    $isStale = $lastSignIn -and ([datetime]$lastSignIn -lt $staleCutoff)
    $neverSignedIn = -not $lastSignIn

    $inventory.Add([PSCustomObject]@{
        DisplayName        = $device.DisplayName
        DeviceId           = $device.DeviceId
        JoinType           = $joinType
        OperatingSystem    = $device.OperatingSystem
        OSVersion          = $device.OperatingSystemVersion
        IsCompliant        = $device.IsCompliant
        IsManaged          = $device.IsManaged
        AccountEnabled     = $device.AccountEnabled
        LastSignIn         = if ($lastSignIn) { $lastSignIn } else { "Never" }
        IsStale            = $isStale
        HasNoOwner         = [string]::IsNullOrEmpty($ownerUpn)
        OwnerUPN           = $ownerUpn
    })
}

$inventory | Export-Csv -Path $InventoryLogPath -NoTypeInformation

$summary = New-Object System.Collections.Generic.List[Object]

$byJoinType = $inventory | Group-Object JoinType
foreach ($group in $byJoinType) {
    $summary.Add([PSCustomObject]@{ Category = "Join Type"; Value = $group.Name; Count = $group.Count })
}

$byOS = $inventory | Group-Object OperatingSystem
foreach ($group in $byOS) {
    $summary.Add([PSCustomObject]@{ Category = "Operating System"; Value = $group.Name; Count = $group.Count })
}

$compliantCount = ($inventory | Where-Object { $_.IsCompliant -eq $true }).Count
$nonCompliantCount = ($inventory | Where-Object { $_.IsCompliant -eq $false }).Count
$unknownComplianceCount = ($inventory | Where-Object { $null -eq $_.IsCompliant }).Count
$summary.Add([PSCustomObject]@{ Category = "Compliance"; Value = "Compliant"; Count = $compliantCount })
$summary.Add([PSCustomObject]@{ Category = "Compliance"; Value = "Not Compliant"; Count = $nonCompliantCount })
$summary.Add([PSCustomObject]@{ Category = "Compliance"; Value = "Unknown/Not Applicable"; Count = $unknownComplianceCount })

$staleCount = ($inventory | Where-Object { $_.IsStale -eq $true }).Count
$neverSignedInCount = ($inventory | Where-Object { $_.LastSignIn -eq "Never" }).Count
$ownerlessCount = ($inventory | Where-Object { $_.HasNoOwner -eq $true }).Count
$summary.Add([PSCustomObject]@{ Category = "Risk Flags"; Value = "Stale (no sign-in $StaleThresholdDays+ days)"; Count = $staleCount })
$summary.Add([PSCustomObject]@{ Category = "Risk Flags"; Value = "Never Signed In"; Count = $neverSignedInCount })
$summary.Add([PSCustomObject]@{ Category = "Risk Flags"; Value = "No Registered Owner"; Count = $ownerlessCount })

$summary | Export-Csv -Path $SummaryLogPath -NoTypeInformation

Write-Host "`nTotal devices audited: $($inventory.Count)"
Write-Host "`nSummary breakdown:"
$summary | Format-Table -AutoSize

Write-Host "`nDevices with no registered owner (top 20 shown):"
$inventory | Where-Object { $_.HasNoOwner -eq $true } | Select-Object -First 20 | Format-Table DisplayName, JoinType, OperatingSystem, LastSignIn -AutoSize

Write-Host "`nStale devices, no sign-in in $StaleThresholdDays+ days (top 20 shown):"
$inventory | Where-Object { $_.IsStale -eq $true } | Select-Object -First 20 | Format-Table DisplayName, JoinType, LastSignIn -AutoSize

Disconnect-MgGraph | Out-Null
