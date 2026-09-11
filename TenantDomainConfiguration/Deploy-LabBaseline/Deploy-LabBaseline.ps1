<#
.SYNOPSIS
    Automated Tenant Baseline & Persona Deployment Script for Microsoft Security Course.
.DESCRIPTION
    Deploys structured persona users across departments, creates departmental security groups,
    adds users to groups, and provisions an emergency Break-Glass account using Microsoft Graph.
.NOTES
    Course: Microsoft Security Stack / SOC Analyst Full Course (Cloud Knowledge)
    Episode: 04 (Lab Tenant Setup)
#>

[CmdletBinding()]
param (
    [string]$DefaultPassword = "VS5kevDfS64ge6Q"
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Cloud Knowledge - Microsoft Security Lab Tenant Setup   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 0. Ensure Execution Policy permits module loading
if ((Get-ExecutionPolicy) -eq "Restricted") {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction SilentlyContinue
}

# 1. Verify / Install and Load Microsoft.Graph Modules
$RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Identity.DirectoryManagement",
    "Microsoft.Graph.Users",
    "Microsoft.Graph.Groups"
)

foreach ($mod in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Host "[*] Module $mod not found. Installing..." -ForegroundColor Yellow
        Install-Module $mod -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
    }
    Write-Host "[*] Loading module: $mod..." -ForegroundColor Gray
    Import-Module $mod -ErrorAction Stop
}

# 2. Connect to Microsoft Graph
Write-Host "[*] Connecting to Microsoft Graph..." -ForegroundColor Yellow
$RequiredScopes = @("User.ReadWrite.All", "Group.ReadWrite.All", "Directory.ReadWrite.All")
Connect-MgGraph -Scopes $RequiredScopes

$Context = Get-MgContext
if (-not $Context) {
    Write-Host "[!] Failed to connect to Microsoft Graph. Authentication was cancelled or failed." -ForegroundColor Red
    return
}

$InitialDomain = Get-MgDomain | Where-Object { $_.IsInitial -eq $true }
$TenantDomain = $InitialDomain.Id
if ([string]::IsNullOrWhiteSpace($TenantDomain)) {
    Write-Host "[!] Unable to retrieve Tenant Domain. Please ensure your account has Directory.ReadWrite.All permission." -ForegroundColor Red
    return
}
Write-Host ("[+] Connected to Tenant Domain: {0} (Tenant ID: {1})" -f $TenantDomain, $Context.TenantId) -ForegroundColor Green

# 3. Define Persona Matrix
$Personas = @(
    @{ FirstName = "Megan";   LastName = "Bowen";     UPN = "MeganB@$TenantDomain";    Title = "Chief Executive Officer"; Department = "Executive";            Group = "SG-Executives" },
    @{ FirstName = "Alex";    LastName = "Wilber";    UPN = "AlexW@$TenantDomain";     Title = "Chief Financial Officer"; Department = "Finance";              Group = "SG-Finance" },
    @{ FirstName = "Lynne";   LastName = "Robbins";   UPN = "LynneR@$TenantDomain";    Title = "Accounts Payable Lead";   Department = "Finance";              Group = "SG-Finance" },
    @{ FirstName = "Adele";   LastName = "Vance";     UPN = "AdeleV@$TenantDomain";    Title = "Senior SOC Analyst";      Department = "Security Operations";  Group = "SG-SecOps" },
    @{ FirstName = "Allan";   LastName = "Deyoung";   UPN = "AllanD@$TenantDomain";    Title = "IT Administrator";        Department = "Information Tech";     Group = "SG-SecOps" },
    @{ FirstName = "Pradeep"; LastName = "Gupta";     UPN = "PradeepG@$TenantDomain";  Title = "Helpdesk Specialist";     Department = "Information Tech";     Group = "SG-SecOps" },
    @{ FirstName = "Joni";    LastName = "Sherman";   UPN = "JoniS@$TenantDomain";     Title = "VP of Sales";             Department = 'Sales & Marketing';    Group = "SG-Sales" },
    @{ FirstName = "Lee";     LastName = "Gu";        UPN = "LeeG@$TenantDomain";      Title = "Account Executive";       Department = 'Sales & Marketing';    Group = "SG-Sales" },
    @{ FirstName = "Diego";   LastName = "Siciliani"; UPN = "DiegoS@$TenantDomain";    Title = "Lead Software Engineer";  Department = "Engineering";          Group = "SG-Engineering" }
)

# 4. Create Security Groups
$GroupsToCreate = @(
    @{ Name="SG-Executives";  Description="Executive Leadership Team Members" },
    @{ Name="SG-Finance";     Description="Finance and Accounting Team Members" },
    @{ Name="SG-SecOps";      Description="Security Operations and IT Administration" },
    @{ Name="SG-Sales";       Description="Sales and Business Development Team" },
    @{ Name="SG-Engineering"; Description="Software Engineering and DevOps Team" },
    @{ Name="SG-AllLabUsers"; Description="All Provisioned Lab Users for Security Testing" }
)

Write-Host "`n[*] Creating Departmental Security Groups..." -ForegroundColor Yellow
$GroupMap = @{}
foreach ($g in $GroupsToCreate) {
    $existing = Get-MgGroup -Filter "displayName eq '$($g.Name)'" -ErrorAction SilentlyContinue
    if (-not $existing) {
        $created = New-MgGroup -DisplayName $g.Name -MailEnabled:$false -MailNickname ($g.Name -replace "-","") -SecurityEnabled:$true -Description $g.Description
        Write-Host "  [+] Created Group: $($g.Name)" -ForegroundColor Green
        $GroupMap[$g.Name] = $created.Id
    } else {
        Write-Host "  [i] Group already exists: $($g.Name)" -ForegroundColor Gray
        $GroupMap[$g.Name] = $existing.Id
    }
}

# 5. Create Persona Users
Write-Host "`n[*] Provisioning Persona Users..." -ForegroundColor Yellow
$PasswordProfile = @{
    ForceChangePasswordNextSignIn = $false
    Password = $DefaultPassword
}

foreach ($p in $Personas) {
    $existingUser = Get-MgUser -Filter "userPrincipalName eq '$($p.UPN)'" -ErrorAction SilentlyContinue
    if (-not $existingUser) {
        $newUser = New-MgUser -DisplayName "$($p.FirstName) $($p.LastName)" `
                              -GivenName $p.FirstName `
                              -Surname $p.LastName `
                              -UserPrincipalName $p.UPN `
                              -MailNickname ($p.FirstName.ToLower() + $p.LastName.ToLower()) `
                              -JobTitle $p.Title `
                              -Department $p.Department `
                              -AccountEnabled:$true `
                              -PasswordProfile $PasswordProfile
        Write-Host "  [+] Created User: $($p.FirstName) $($p.LastName) ($($p.Department))" -ForegroundColor Green
        $userId = $newUser.Id
    } else {
        Write-Host "  [i] User already exists: $($p.UPN)" -ForegroundColor Gray
        $userId = $existingUser.Id
    }

    # Add to department group
    $deptGroupId = $GroupMap[$p.Group]
    if ($deptGroupId) {
        try {
            New-MgGroupMember -GroupId $deptGroupId -DirectoryObjectId $userId -ErrorAction SilentlyContinue
        } catch { }
    }
    # Add to all lab users group
    $allUsersGroupId = $GroupMap["SG-AllLabUsers"]
    if ($allUsersGroupId) {
        try {
            New-MgGroupMember -GroupId $allUsersGroupId -DirectoryObjectId $userId -ErrorAction SilentlyContinue
        } catch { }
    }
}

# 6. Create Emergency Break-Glass Account
Write-Host "`n[*] Configuring Emergency Break-Glass Account..." -ForegroundColor Yellow
$BreakGlassUPN = "EmergencyBreakGlass-Admin@$TenantDomain"
$existingBG = Get-MgUser -Filter "userPrincipalName eq '$BreakGlassUPN'" -ErrorAction SilentlyContinue
if (-not $existingBG) {
    $bgUser = New-MgUser -DisplayName "Emergency BreakGlass Admin" `
                         -UserPrincipalName $BreakGlassUPN `
                         -MailNickname "breakglass" `
                         -JobTitle "Cloud Emergency Account" `
                         -Department "Information Security" `
                         -AccountEnabled:$true `
                         -PasswordProfile @{ ForceChangePasswordNextSignIn = $false; Password = $DefaultPassword }
    Write-Host "  [+] Created Break-Glass Account: $BreakGlassUPN" -ForegroundColor Magenta
    Write-Host "  [!] IMPORTANT: Exclude this account from ALL Conditional Access policies!" -ForegroundColor Yellow
} else {
    Write-Host "  [i] Break-Glass Account already exists: $BreakGlassUPN" -ForegroundColor Gray
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  [+] LAB TENANT DEPLOYMENT COMPLETE!                     " -ForegroundColor Green
Write-Host "  Total Personas: $($Personas.Count) | Total Groups: $($GroupsToCreate.Count)" -ForegroundColor Green
Write-Host "  Default Password: $DefaultPassword" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
