[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\AttributeStandardization-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

function Format-StandardizedText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $trimmed = $Value.Trim() -replace '\s+', ' '
    return (Get-Culture).TextInfo.ToTitleCase($trimmed.ToLower())
}

function Format-StandardizedPhone {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $digitsOnly = $Value -replace '[^\d+]', ''
    return $digitsOnly
}

$requiredScopes = @("User.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$sourceRecords = Import-Csv -Path $CsvPath

foreach ($row in $sourceRecords) {

    $upn = $row.UserPrincipalName.Trim()
    $status = "Unknown"
    $message = ""

    try {
        $currentUser = Get-MgUser -Filter "userPrincipalName eq '$upn'" -Property "id,department,jobTitle,officeLocation,city,country,mobilePhone,employeeId" -ErrorAction Stop

        $standardized = @{
            Department     = Format-StandardizedText $row.Department
            JobTitle       = Format-StandardizedText $row.JobTitle
            OfficeLocation = Format-StandardizedText $row.OfficeLocation
            City           = Format-StandardizedText $row.City
            Country        = Format-StandardizedText $row.Country
            MobilePhone    = Format-StandardizedPhone $row.MobilePhone
            EmployeeId     = $row.EmployeeId.Trim()
        }

        $changes = @{}

        foreach ($key in $standardized.Keys) {
            $newValue = $standardized[$key]
            $currentValue = $currentUser.AdditionalProperties[$key.Substring(0,1).ToLower() + $key.Substring(1)]

            if ($null -ne $newValue -and $newValue -ne $currentValue) {
                $changes[$key] = $newValue
            }
        }

        if ($changes.Count -gt 0) {
            Update-MgUser -UserId $currentUser.Id -BodyParameter $changes
            $status = "Updated"
            $message = "Fields changed: $($changes.Keys -join ', ')"
        }
        else {
            $status = "NoChange"
            $message = "All attributes already standardized and in sync."
        }
    }
    catch {
        $status = "Failed"
        $message = $_.Exception.Message
    }

    $results.Add([PSCustomObject]@{
        UserPrincipalName = $upn
        Status            = $status
        Message           = $message
        Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
