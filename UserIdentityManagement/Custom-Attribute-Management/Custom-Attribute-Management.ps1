[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\CustomAttributeManagement-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("CustomSecAttributeAssignment.ReadWrite.All", "CustomSecAttributeDefinition.Read.All", "User.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$requests = Import-Csv -Path $CsvPath

foreach ($row in $requests) {

    $action = $row.Action.Trim().ToLower()
    $upn = $row.UserPrincipalName.Trim()
    $status = "Unknown"
    $message = ""

    try {
        $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop

        switch ($action) {

            "setcustomattribute" {
                $attributeSet = $row.AttributeSet.Trim()
                $attributeName = $row.AttributeName.Trim()
                $valueType = $row.ValueType.Trim().ToLower()
                $rawValue = $row.AttributeValue.Trim()

                $typedValue = switch ($valueType) {
                    "boolean" { [System.Convert]::ToBoolean($rawValue) }
                    "integer" { [int]$rawValue }
                    default   { $rawValue }
                }

                $body = @{
                    customSecurityAttributes = @{
                        $attributeSet = @{
                            "@odata.type" = "#Microsoft.DirectoryServices.CustomSecurityAttributeValue"
                            $attributeName = $typedValue
                        }
                    }
                } | ConvertTo-Json -Depth 5

                Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/beta/users/$($user.Id)" -Body $body -ContentType "application/json"

                $status = "Success"
                $message = "Set $attributeSet.$attributeName = $rawValue ($valueType)."
            }

            "getcustomattributes" {
                $response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/users/$($user.Id)?`$select=customSecurityAttributes"

                if ($response.customSecurityAttributes) {
                    $summary = ($response.customSecurityAttributes | ConvertTo-Json -Depth 5 -Compress)
                    $status = "Success"
                    $message = "Attributes: $summary"
                }
                else {
                    $status = "Success"
                    $message = "No custom security attributes assigned to this user."
                }
            }

            "setextensionattribute" {
                $extNumber = $row.ExtensionAttributeNumber.Trim()
                $extValue = $row.ExtensionAttributeValue.Trim()

                if ($extNumber -notin 1..15) {
                    throw "ExtensionAttributeNumber must be between 1 and 15. Received: $extNumber"
                }

                $fieldName = "extensionAttribute$extNumber"
                $body = @{
                    onPremisesExtensionAttributes = @{
                        $fieldName = $extValue
                    }
                } | ConvertTo-Json -Depth 5

                Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/users/$($user.Id)" -Body $body -ContentType "application/json"

                $status = "Success"
                $message = "Set onPremisesExtensionAttributes.$fieldName = $extValue"
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
        UserPrincipalName = $upn
        Action            = $row.Action
        Status            = $status
        Message           = $message
        Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
