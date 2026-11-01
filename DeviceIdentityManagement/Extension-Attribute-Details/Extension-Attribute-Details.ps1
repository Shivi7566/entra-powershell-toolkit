Connect-MgGraph -Scopes "Device.Read.All" -NoWelcome

New-Item -Path C:\temp -ItemType Directory -Force | Out-Null

$uri = "https://graph.microsoft.com/v1.0/devices?`$select=displayName,deviceId,operatingSystem,operatingSystemVersion,trustType,accountEnabled,approximateLastSignInDateTime,extensionAttributes&`$top=999"
$all = @()

do {
    $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
    $all += $resp.value
    $uri = $resp.'@odata.nextLink'
} while ($uri)

Write-Host "Total devices: $($all.Count)"

$joinMap = @{ AzureAd = 'Entra joined'; ServerAd = 'Hybrid joined'; Workplace = 'Entra registered' }

$report = $all | ForEach-Object {
    $ea = $_.extensionAttributes
    $jt = $_.trustType
    if ($jt -and $joinMap.ContainsKey($jt)) { $jt = $joinMap[$jt] }

    [pscustomobject]@{
        DisplayName = $_.displayName
        DeviceId    = $_.deviceId
        OS          = $_.operatingSystem
        OSVersion   = $_.operatingSystemVersion
        JoinType    = $jt
        Enabled     = $_.accountEnabled
        LastSignIn  = $_.approximateLastSignInDateTime
        ExtAttr1    = $ea.extensionAttribute1
        ExtAttr2    = $ea.extensionAttribute2
        ExtAttr3    = $ea.extensionAttribute3
        ExtAttr4    = $ea.extensionAttribute4
        ExtAttr5    = $ea.extensionAttribute5
    }
}

$report | Export-Csv C:\temp\EntraDevices_ExtAttr.csv -NoTypeInformation -Encoding UTF8

$report | Where-Object { $_.ExtAttr1 -or $_.ExtAttr2 -or $_.ExtAttr3 -or $_.ExtAttr4 -or $_.ExtAttr5 } |
    Export-Csv C:\temp\EntraDevices_WithExtAttr.csv -NoTypeInformation -Encoding UTF8

$report | Group-Object JoinType | Select-Object Name, Count
