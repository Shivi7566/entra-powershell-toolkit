[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$StaleThresholdDays = 90,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Disable", "Delete")]
    [string]$CleanupAction = "Disable",

    [Parameter(Mandatory = $false)]
    [switch]$PerformCleanup,

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeDeviceIds,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\StaleDeviceCleanup-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("Device.ReadWrite.All", "Directory.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]
$now = Get-Date
$staleCutoff = $now.AddDays(-$StaleThresholdDays)

Write-Host "Retrieving all devices in the tenant..."
$allDevices = Get-MgDevice -All -Property "displayName,deviceId,trustType,approximateLastSignInDateTime,createdDateTime,accountEnabled"

$staleCandidates = New-Object System.Collections.Generic.List[Object]

foreach ($device in $allDevices) {

    if ($device.DeviceId -in $ExcludeDeviceIds) { continue }

    $lastSignIn = $device.ApproximateLastSignInDateTime
    $createdDate = $device.CreatedDateTime

    $isStaleBySignIn = $lastSignIn -and ([datetime]$lastSignIn -lt $staleCutoff)
    $isStaleByNeverSignedIn = (-not $lastSignIn) -and $createdDate -and ([datetime]$createdDate -lt $staleCutoff)

    if ($isStaleBySignIn -or $isStaleByNeverSignedIn) {
        $staleCandidates.Add($device)
    }
}

Write-Host "Found $($staleCandidates.Count) stale device(s) (threshold: $StaleThresholdDays day(s))."

foreach ($staleDevice in $staleCandidates) {

    $reason = if ($staleDevice.ApproximateLastSignInDateTime) {
        "No sign-in since $($staleDevice.ApproximateLastSignInDateTime)"
    } else {
        "Never signed in; created $($staleDevice.CreatedDateTime)"
    }

    if (-not $PerformCleanup) {
        $results.Add([PSCustomObject]@{
            DisplayName = $staleDevice.DisplayName
            DeviceId    = $staleDevice.DeviceId
            Status      = "ReportOnly"
            Message     = "Would perform '$CleanupAction'. Reason: $reason"
            Timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        })
        continue
    }

    try {
        if ($CleanupAction -eq "Disable") {
            Update-MgDevice -DeviceId $staleDevice.Id -AccountEnabled:$false
            $status = "Success"
            $message = "Device disabled. Reason: $reason"
        }
        else {
            Remove-MgDevice -DeviceId $staleDevice.Id
            $status = "Success"
            $message = "Device deleted (recoverable for 30 days). Reason: $reason"
        }
    }
    catch {
        $status = "Failed"
        $message = $_.Exception.Message
    }

    $results.Add([PSCustomObject]@{
        DisplayName = $staleDevice.DisplayName
        DeviceId    = $staleDevice.DeviceId
        Status      = $status
        Message     = $message
        Timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

if (-not $PerformCleanup -and $staleCandidates.Count -gt 0) {
    Write-Host "`nThis was a report-only run. Re-run with -PerformCleanup to actually $CleanupAction these devices."
}

Disconnect-MgGraph | Out-Null
