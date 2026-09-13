<#
.SYNOPSIS
    Exports Microsoft Secure Score Summary and Improvement Actions via Microsoft Graph.
.DESCRIPTION
    Connects to Microsoft Graph Security API, retrieves current tenant Secure Score,
    category point distribution, and all pending Improvement Actions, exporting results
    to a structured CSV report.
.NOTES
    Course: Microsoft Security Stack / SOC Analyst Full Course (Cloud Knowledge)
    Episode: 06 (Working with Secure Score & Triaging Improvement Actions)
#>

[CmdletBinding()]
param (
    [string]$OutputPath = ".\SecureScore_Report_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Cloud Knowledge - Microsoft Secure Score Telemetry     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Verify / Load Microsoft.Graph.Security module
$ModuleName = "Microsoft.Graph.Security"
if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
    Write-Host "[*] Module $ModuleName not found. Installing for CurrentUser..." -ForegroundColor Yellow
    Install-Module $ModuleName -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
}
Import-Module $ModuleName -ErrorAction Stop

# 2. Connect to Microsoft Graph Security Endpoint
Write-Host "[*] Connecting to Microsoft Graph..." -ForegroundColor Yellow
$RequiredScopes = @("SecurityEvents.Read.All")
Connect-MgGraph -Scopes $RequiredScopes

$Context = Get-MgContext
if (-not $Context) {
    Write-Host "[!] Authentication failed or cancelled." -ForegroundColor Red
    return
}
Write-Host ("[+] Authenticated as: {0} (Tenant ID: {1})" -f $Context.Account, $Context.TenantId) -ForegroundColor Green

# 3. Retrieve Latest Secure Score Snapshot
Write-Host "`n[*] Retrieving latest tenant Secure Score snapshot..." -ForegroundColor Yellow
$Scores = Get-MgSecuritySecureScore -Top 1
if (-not $Scores) {
    Write-Host "[!] No Secure Score telemetry found for this tenant." -ForegroundColor Red
    return
}

$Latest = $Scores[0]
$CurrentScore = [math]::Round($Latest.CurrentScore, 2)
$MaxScore = [math]::Round($Latest.MaxScore, 2)
$Percentage = if ($MaxScore -gt 0) { [math]::Round(($CurrentScore / $MaxScore) * 100, 2) } else { 0 }

Write-Host "----------------------------------------------------------" -ForegroundColor DarkCyan
Write-Host ("  Current Secure Score : {0} / {1} ({2}%)" -f $CurrentScore, $MaxScore, $Percentage) -ForegroundColor Green
Write-Host ("  Snapshot Date        : {0}" -f $Latest.CreatedDateTime) -ForegroundColor Gray
Write-Host "----------------------------------------------------------" -ForegroundColor DarkCyan

Write-Host "`n[*] Category Point Breakdown:" -ForegroundColor Yellow
$CategoryData = @()
foreach ($cat in $Latest.ControlScores) {
    $cScore = [math]::Round($cat.Score, 2)
    $cMax = [math]::Round($cat.ScoreInPercentage, 2)
    Write-Host ("  - {0,-18} : {1,6} pts" -f $cat.ControlCategory, $cScore) -ForegroundColor White
}

# 4. Retrieve Improvement Actions
Write-Host "`n[*] Retrieving Improvement Action Profiles..." -ForegroundColor Yellow
$Profiles = Get-MgSecuritySecureScoreControlProfile -All

Write-Host ("[+] Total Improvement Actions Retrieved: {0}" -f $Profiles.Count) -ForegroundColor Green

$Report = @()
foreach ($p in $Profiles) {
    $Report += [PSCustomObject]@{
        Title               = $p.Title
        Category            = $p.ControlCategory
        MaxPoints           = $p.MaxScore
        ActionType          = $p.ActionType
        UserImpact          = $p.UserImpact
        ImplementationCost  = $p.ImplementationCost
        Tier                = $p.Tier
        ThreatsMitigated    = ($p.Threats -join "; ")
        RemediationImpact   = $p.RemediationImpact
    }
}

# 5. Export to CSV
$Report | Sort-Object -Property MaxPoints -Descending | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host ("  [+] Report successfully exported to: {0}" -f $OutputPath) -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
