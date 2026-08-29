[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\ServicePlanManagement-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("LicenseAssignment.ReadWrite.All", "User.Read.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]
$allSkus = Get-MgSubscribedSku -All

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
        $sku = $allSkus | Where-Object { $_.SkuPartNumber -eq $row.SkuPartNumber.Trim() }

        if (-not $sku) {
            throw "SKU '$($row.SkuPartNumber)' not found in tenant's subscribed SKUs."
        }

        switch ($action) {

            "disableplan" {
                $targetPlan = $sku.ServicePlans | Where-Object { $_.ServicePlanName -eq $row.ServicePlanName.Trim() }
                if (-not $targetPlan) {
                    throw "Service plan '$($row.ServicePlanName)' not found within SKU '$($row.SkuPartNumber)'."
                }

                $currentDetail = Get-MgUserLicenseDetail -UserId $user.Id | Where-Object { $_.SkuId -eq $sku.SkuId }
                if (-not $currentDetail) {
                    throw "User does not currently have SKU '$($row.SkuPartNumber)' assigned."
                }

                $currentDisabledIds = $currentDetail.ServicePlans | Where-Object { $_.ProvisioningStatus -eq "Disabled" } | ForEach-Object { $_.ServicePlanId }
                $updatedDisabledIds = @($currentDisabledIds) + $targetPlan.ServicePlanId | Select-Object -Unique

                Set-MgUserLicense -UserId $user.Id -BodyParameter @{
                    AddLicenses = @(
                        @{ SkuId = $sku.SkuId; DisabledPlans = $updatedDisabledIds }
                    )
                    RemoveLicenses = @()
                }

                $status = "Success"
                $message = "Disabled service plan '$($row.ServicePlanName)' within $($row.SkuPartNumber) for $upn."
            }

            "enableplan" {
                $targetPlan = $sku.ServicePlans | Where-Object { $_.ServicePlanName -eq $row.ServicePlanName.Trim() }
                if (-not $targetPlan) {
                    throw "Service plan '$($row.ServicePlanName)' not found within SKU '$($row.SkuPartNumber)'."
                }

                $currentDetail = Get-MgUserLicenseDetail -UserId $user.Id | Where-Object { $_.SkuId -eq $sku.SkuId }
                if (-not $currentDetail) {
                    throw "User does not currently have SKU '$($row.SkuPartNumber)' assigned."
                }

                $currentDisabledIds = $currentDetail.ServicePlans | Where-Object { $_.ProvisioningStatus -eq "Disabled" } | ForEach-Object { $_.ServicePlanId }
                $updatedDisabledIds = @($currentDisabledIds) | Where-Object { $_ -ne $targetPlan.ServicePlanId }

                Set-MgUserLicense -UserId $user.Id -BodyParameter @{
                    AddLicenses = @(
                        @{ SkuId = $sku.SkuId; DisabledPlans = @($updatedDisabledIds) }
                    )
                    RemoveLicenses = @()
                }

                $status = "Success"
                $message = "Re-enabled service plan '$($row.ServicePlanName)' within $($row.SkuPartNumber) for $upn."
            }

            "listplans" {
                $currentDetail = Get-MgUserLicenseDetail -UserId $user.Id | Where-Object { $_.SkuId -eq $sku.SkuId }
                if (-not $currentDetail) {
                    throw "User does not currently have SKU '$($row.SkuPartNumber)' assigned."
                }

                $enabled = ($currentDetail.ServicePlans | Where-Object { $_.ProvisioningStatus -ne "Disabled" }).ServicePlanName -join ", "
                $disabled = ($currentDetail.ServicePlans | Where-Object { $_.ProvisioningStatus -eq "Disabled" }).ServicePlanName -join ", "

                $status = "Success"
                $message = "Enabled: $enabled | Disabled: $disabled"
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

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
