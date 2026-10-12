[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\AppCreation-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("Application.ReadWrite.All", "Directory.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$requests = Import-Csv -Path $CsvPath

foreach ($row in $requests) {

    $action = $row.Action.Trim().ToLower()
    $displayName = $row.DisplayName.Trim()
    $status = "Unknown"
    $message = ""

    try {
        switch ($action) {

            "createapp" {
                $signInAudience = if ($row.SignInAudience) { $row.SignInAudience.Trim() } else { "AzureADMyOrg" }

                $appParams = @{
                    DisplayName    = $displayName
                    SignInAudience = $signInAudience
                }

                if ($row.RedirectUri) {
                    $redirectType = if ($row.RedirectType) { $row.RedirectType.Trim().ToLower() } else { "web" }

                    switch ($redirectType) {
                        "spa"          { $appParams["Spa"] = @{ RedirectUris = @($row.RedirectUri) } }
                        "publicclient" { $appParams["PublicClient"] = @{ RedirectUris = @($row.RedirectUri) } }
                        default        { $appParams["Web"] = @{ RedirectUris = @($row.RedirectUri) } }
                    }
                }

                $newApp = New-MgApplication -BodyParameter $appParams
                $newServicePrincipal = New-MgServicePrincipal -AppId $newApp.AppId

                if ($row.OwnerUPN) {
                    $ownerUser = Get-MgUser -Filter "userPrincipalName eq '$($row.OwnerUPN.Trim())'" -ErrorAction Stop

                    New-MgApplicationOwnerByRef -ApplicationId $newApp.Id -BodyParameter @{
                        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($ownerUser.Id)"
                    }

                    New-MgServicePrincipalOwnerByRef -ServicePrincipalId $newServicePrincipal.Id -BodyParameter @{
                        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($ownerUser.Id)"
                    }
                }

                $status = "Success"
                $message = "App registration and enterprise application created. AppId: $($newApp.AppId) | ObjectId: $($newApp.Id) | ServicePrincipalId: $($newServicePrincipal.Id)"
            }

            "createsp" {
                $newServicePrincipal = New-MgServicePrincipal -AppId $row.AppId.Trim()
                $status = "Success"
                $message = "Enterprise application (service principal) created for existing AppId $($row.AppId). ServicePrincipalId: $($newServicePrincipal.Id)"
            }

            "addowner" {
                $existingApp = Get-MgApplication -Filter "displayName eq '$displayName'" -ErrorAction Stop
                $ownerUser = Get-MgUser -Filter "userPrincipalName eq '$($row.OwnerUPN.Trim())'" -ErrorAction Stop

                New-MgApplicationOwnerByRef -ApplicationId $existingApp.Id -BodyParameter @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($ownerUser.Id)"
                }

                $status = "Success"
                $message = "Added $($row.OwnerUPN) as owner of '$displayName'."
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
        DisplayName = $displayName
        Action      = $row.Action
        Status      = $status
        Message     = $message
        Timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
