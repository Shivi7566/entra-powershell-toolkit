[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [switch]$AuditEscrowGaps,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\BitLocker-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("BitlockerKey.Read.All", "BitlockerKey.ReadBasic.All", "Device.Read.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if ($CsvPath) {
    if (-not (Test-Path $CsvPath)) {
        throw "CSV file not found at path: $CsvPath"
    }

    $requests = Import-Csv -Path $CsvPath

    foreach ($row in $requests) {

        $deviceId = $row.DeviceId.Trim()
        $status = "Unknown"
        $message = ""

        try {
            $keyMetadataResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$deviceId'"

            if ($keyMetadataResponse.value.Count -eq 0) {
                throw "No BitLocker recovery key found escrowed for device $deviceId."
            }

            $keyId = $keyMetadataResponse.value[0].id
            $keyDetailResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/informationProtection/bitlocker/recoveryKeys/$($keyId)?`$select=key"

            $status = "Success"
            $message = "RECOVERY KEY (store immediately, this call is audit-logged): $($keyDetailResponse.key)"
        }
        catch {
            $status = "Failed"
            $message = $_.Exception.Message
        }

        $results.Add([PSCustomObject]@{
            DeviceId  = $deviceId
            Action    = "retrievekey"
            Status    = $status
            Message   = $message
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        })
    }
}

if ($AuditEscrowGaps) {

    Write-Host "Retrieving all Windows devices..."
    $allDevices = Get-MgDevice -All -Property "displayName,deviceId,operatingSystem,accountEnabled" -Filter "operatingSystem eq 'Windows'"

    Write-Host "Retrieving all escrowed BitLocker recovery key metadata..."
    $allKeys = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/informationProtection/bitlocker/recoveryKeys"
    $devicesWithKeys = $allKeys.value | ForEach-Object { $_.deviceId } | Select-Object -Unique

    $gapCount = 0

    foreach ($windowsDevice in $allDevices) {
        if ($windowsDevice.DeviceId -notin $devicesWithKeys) {
            $gapCount++
            $results.Add([PSCustomObject]@{
                DeviceId  = $windowsDevice.DeviceId
                Action    = "escrowgap"
                Status    = "Gap"
                Message   = "Windows device '$($windowsDevice.DisplayName)' has no BitLocker recovery key escrowed to Entra ID."
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            })
        }
    }

    Write-Host "Escrow audit complete. $gapCount Windows device(s) out of $($allDevices.Count) have no escrowed BitLocker key."
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
