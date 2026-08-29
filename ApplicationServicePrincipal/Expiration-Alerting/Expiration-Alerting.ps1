[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$WarningThresholdDays = 30,

    [Parameter(Mandatory = $false)]
    [int]$CriticalThresholdDays = 7,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\ExpirationAlerts-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$requiredScopes = @("Application.Read.All", "Directory.Read.All")
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$findings = New-Object System.Collections.Generic.List[Object]
$now = Get-Date

function Get-Severity {
    param([datetime]$EndDate)

    $daysRemaining = ($EndDate - $now).Days

    if ($daysRemaining -lt 0) { return "Expired" }
    if ($daysRemaining -le $CriticalThresholdDays) { return "Critical" }
    if ($daysRemaining -le $WarningThresholdDays) { return "Warning" }
    return "OK"
}

Write-Host "Scanning application registrations for expiring secrets and certificates..."
$allApplications = Get-MgApplication -All

foreach ($app in $allApplications) {

    foreach ($secret in $app.PasswordCredentials) {
        $severity = Get-Severity -EndDate $secret.EndDateTime
        if ($severity -eq "OK") { continue }

        $findings.Add([PSCustomObject]@{
            ObjectType    = "Application"
            ObjectName    = $app.DisplayName
            CredentialType = "ClientSecret"
            CredentialName = $secret.DisplayName
            ExpiresOn     = $secret.EndDateTime
            DaysRemaining = ($secret.EndDateTime - $now).Days
            Severity      = $severity
            Timestamp     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        })
    }

    foreach ($cert in $app.KeyCredentials) {
        $severity = Get-Severity -EndDate $cert.EndDateTime
        if ($severity -eq "OK") { continue }

        $findings.Add([PSCustomObject]@{
            ObjectType    = "Application"
            ObjectName    = $app.DisplayName
            CredentialType = "Certificate"
            CredentialName = $cert.DisplayName
            ExpiresOn     = $cert.EndDateTime
            DaysRemaining = ($cert.EndDateTime - $now).Days
            Severity      = $severity
            Timestamp     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        })
    }
}

Write-Host "Scanning service principals for SAML token signing certificates..."
$allServicePrincipals = Get-MgServicePrincipal -All -Property "displayName,keyCredentials,preferredTokenSigningKeyEndDateTime,tags"

foreach ($servicePrincipal in $allServicePrincipals) {

    foreach ($cert in $servicePrincipal.KeyCredentials) {
        $severity = Get-Severity -EndDate $cert.EndDateTime
        if ($severity -eq "OK") { continue }

        $findings.Add([PSCustomObject]@{
            ObjectType    = "ServicePrincipal"
            ObjectName    = $servicePrincipal.DisplayName
            CredentialType = "Certificate"
            CredentialName = $cert.DisplayName
            ExpiresOn     = $cert.EndDateTime
            DaysRemaining = ($cert.EndDateTime - $now).Days
            Severity      = $severity
            Timestamp     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        })
    }

    if ($servicePrincipal.PreferredTokenSigningKeyEndDateTime) {
        $severity = Get-Severity -EndDate $servicePrincipal.PreferredTokenSigningKeyEndDateTime
        if ($severity -ne "OK") {
            $findings.Add([PSCustomObject]@{
                ObjectType    = "ServicePrincipal"
                ObjectName    = $servicePrincipal.DisplayName
                CredentialType = "SAMLTokenSigningCert"
                CredentialName = "PreferredTokenSigningKey"
                ExpiresOn     = $servicePrincipal.PreferredTokenSigningKeyEndDateTime
                DaysRemaining = ($servicePrincipal.PreferredTokenSigningKeyEndDateTime - $now).Days
                Severity      = $severity
                Timestamp     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            })
        }
    }
}

if ($findings.Count -eq 0) {
    Write-Host "No credentials expiring within $WarningThresholdDays day(s) were found."
}
else {
    Write-Host "`nFound $($findings.Count) credential(s) requiring attention:"
    $findings | Sort-Object DaysRemaining | Format-Table -AutoSize
}

$findings | Export-Csv -Path $LogPath -NoTypeInformation

Disconnect-MgGraph | Out-Null
