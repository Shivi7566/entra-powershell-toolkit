[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\OAuthConsent-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("Application.ReadWrite.All", "DelegatedPermissionGrant.ReadWrite.All", "AppRoleAssignment.ReadWrite.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$results = New-Object System.Collections.Generic.List[Object]

function Get-ResourceServicePrincipal {
    param([string]$Name)

    if ($Name.Trim().ToLower() -eq "microsoft graph") {
        return Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
    }

    return Get-MgServicePrincipal -Filter "displayName eq '$Name'" -ErrorAction Stop
}

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found at path: $CsvPath"
}

$requests = Import-Csv -Path $CsvPath

foreach ($row in $requests) {

    $action = $row.Action.Trim().ToLower()
    $appName = $row.AppDisplayName.Trim()
    $status = "Unknown"
    $message = ""

    try {
        $clientApp = Get-MgApplication -Filter "displayName eq '$appName'" -ErrorAction Stop
        $clientServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$($clientApp.AppId)'" -ErrorAction Stop
        $resourceServicePrincipal = Get-ResourceServicePrincipal -Name $row.ResourceAppDisplayName.Trim()

        switch ($action) {

            "grantdelegated" {
                $grantParams = @{
                    ClientId    = $clientServicePrincipal.Id
                    ConsentType = "AllPrincipals"
                    ResourceId  = $resourceServicePrincipal.Id
                    Scope       = $row.DelegatedScopes.Trim()
                }

                New-MgOauth2PermissionGrant -BodyParameter $grantParams | Out-Null
                $status = "Success"
                $message = "Granted delegated scopes '$($row.DelegatedScopes)' against $($row.ResourceAppDisplayName), admin consented for all users."
            }

            "grantapplication" {
                $matchedRole = $resourceServicePrincipal.AppRoles | Where-Object { $_.Value -eq $row.AppRoleValue.Trim() }

                if (-not $matchedRole) {
                    throw "App role '$($row.AppRoleValue)' not found on resource '$($row.ResourceAppDisplayName)'."
                }

                $roleAssignmentParams = @{
                    PrincipalId = $clientServicePrincipal.Id
                    ResourceId  = $resourceServicePrincipal.Id
                    AppRoleId   = $matchedRole.Id
                }

                New-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $resourceServicePrincipal.Id -BodyParameter $roleAssignmentParams | Out-Null
                $status = "Success"
                $message = "Granted application permission '$($row.AppRoleValue)' on $($row.ResourceAppDisplayName) to $appName."
            }

            "listgrants" {
                $delegatedGrants = Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $clientServicePrincipal.Id
                $appRoleGrants = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $clientServicePrincipal.Id

                $delegatedSummary = ($delegatedGrants | ForEach-Object { $_.Scope }) -join " | "
                $appRoleSummary = ($appRoleGrants | ForEach-Object { $_.AppRoleId }) -join ", "

                $status = "Success"
                $message = "Delegated scopes: [$delegatedSummary] | Application permission role IDs: [$appRoleSummary]"
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
        AppDisplayName = $appName
        Action         = $row.Action
        Status         = $status
        Message        = $message
        Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
