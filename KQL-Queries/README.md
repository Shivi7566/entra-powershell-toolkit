# Microsoft Defender XDR — Production KQL Threat Hunting Queries
### Episode 08 Companion Scripts | Microsoft Security Stack & SOC Analyst Full Course
**Author:** Cloud Knowledge | [CloudKnowledge.in](https://cloudknowledge.in)  
**Target Console:** Microsoft Defender XDR &rarr; Advanced Hunting (https://security.microsoft.com/hunting)

---

## 📋 Overview

This folder contains the official Kusto Query Language (KQL) hunting queries and lab attack simulation scripts featured in **Episode 08: Using Threat Analytics & Advanced Hunting with KQL** of the *Microsoft Security Stack and SOC Analyst Full Course*.

These queries allow SOC analysts and threat hunters to operationalize threat intelligence, hunt for stealthy adversary techniques across endpoints and identities, execute cross-domain correlations, and deploy automated Custom Detection rules.

---

## 🎯 Hunting Queries Catalog

| Query # | Technique / Objective | Telemetry Table | MITRE ATT&CK | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Query 1** | **Suspicious PowerShell Execution** | DeviceProcessEvents | Execution (T1059.001) / Defense Evasion (T1027) | Hunts for encoded PowerShell commands (-enc), web download strings (DownloadString, IEX, curl), and script cradle launches. |
| **Query 2** | **Living-off-the-Land (LOLBin) Tool Ingress** | DeviceProcessEvents | Command and Control (T1105) | Detects native Windows administrative utilities (certutil.exe, itsadmin.exe) being abused to download payloads from external URLs. |
| **Query 3** | **LSASS Memory Dumping & Credential Theft** | DeviceProcessEvents | Credential Access (T1003.001) | Detects attempts to dump LSASS process memory using 
undll32 comsvcs.dll MiniDump, procdump.exe, or known credential scrapers. |
| **Query 4** | **Outbound Non-Browser C2 Beacons** | DeviceNetworkEvents | Command and Control (T1071) | Identifies script interpreters and command shells (cmd, powershell, wscript) opening direct TCP/UDP outbound sockets to public IP addresses. |
| **Query 5** | **Cross-Domain Phish to Process Correlation** | EmailEvents <br>&rarr; DeviceProcessEvents | Initial Access (T1566) <br>&rarr; Execution (T1204.002) | Joins Defender for Office 365 inbound email attachments with Defender for Endpoint process creation to trace patient zero infection paths. |
| **Query 6** | **Ransomware Process Tampering (Custom Detection)** | DeviceProcessEvents | Impact / Inhibit Recovery (T1490) | Detects recovery tampering (ssadmin delete shadows, cdedit ignoreallfailures) and forms the basis of a production automated detection rule. |

---

## 🚀 How to Execute Queries in Microsoft Defender

1. Navigate to the **Microsoft Defender Portal** at [security.microsoft.com](https://security.microsoft.com).
2. On the left navigation pane, expand **Hunting** and select **Advanced hunting** (https://security.microsoft.com/hunting).
3. Click the **+** (New query) button to open a blank query tab.
4. Copy and paste any query from [ThreatHuntingQueries.kql](./ThreatHuntingQueries.kql) into the editor.
5. Set the time range selector (e.g., **Past 7 days** or **Past 30 days**).
6. Click **Run query** (Ctrl + Enter) to inspect matching events.

---

## 🛡️ Promoting Query 6 into an Automated Custom Detection Rule

To convert **Query 6** into a scheduled automated detection rule:

1. Run **Query 6** inside Advanced Hunting and ensure results return valid entity columns (DeviceId, DeviceName, AccountName, ReportId).
2. Click **Create detection rule** in the top toolbar.
3. **Detection details:**
   - Rule name: Ransomware Inhibit System Recovery Tampering (vssadmin/bcdedit)
   - Frequency: Every 1 hour
   - Severity: **High**
   - Category: **Defense Evasion / Impact**
   - Technique: T1490 - Inhibit System Recovery
4. **Entities to trigger on:**
   - Device: DeviceId
   - User: AccountName
5. **Actions (Automated Response):**
   - Device actions: Check **Isolate device** (Isolation type: *Full*)
6. **Scope:** All onboarded devices.
7. Click **Submit** to activate your scheduled detection rule.

---

## 🧪 Safe Attack Simulation Script (Simulate-LabIncidents.ps1)

To test these queries in a non-production lab tenant:
1. Open PowerShell as Administrator on an onboarded Windows lab machine.
2. Run [Simulate-LabIncidents.ps1](./Simulate-LabIncidents.ps1).
3. Choose option [4] to execute harmless simulations that mimic LOLBin downloads, encoded PowerShell, and dummy shadow copy commands.
4. Return to Defender Advanced Hunting 10–15 minutes later to see live telemetry matches!

---

## 📺 Video Walkthrough
Watch the complete screen-share lab demonstration on YouTube:  
👉 **[Cloud Knowledge: Threat Analytics & Advanced Hunting with KQL](https://www.youtube.com/@CloudKnowledge)**
