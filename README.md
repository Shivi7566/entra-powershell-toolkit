# Microsoft Entra ID & Security PowerShell Toolkit
### Production Automation Scripts for Cloud Administrators & SOC Analysts
**Author:** Cloud Knowledge | [CloudKnowledge.in](https://cloudknowledge.in)

Welcome to the **entra-powershell-toolkit** repository! This repository contains battle-tested, production-grade PowerShell automation scripts for managing, hardening, auditing, and operating Microsoft Entra ID, Microsoft Defender, and Microsoft 365 cloud environments.

---

## 🚀 Featured Course Automation Scripts

| Episode / Feature | Script Name | Module / Category | Description |
| :--- | :--- | :--- | :--- |
| **Episode 04** | [`Deploy-LabBaseline.ps1`](./TenantDomainConfiguration/Deploy-LabBaseline/Deploy-LabBaseline.ps1) | `TenantDomainConfiguration` | Deploys a full corporate identity baseline (9 persona users, 6 security groups, break-glass admin) in 60s. |
| **Episode 06** | [`Export-SecureScoreReport.ps1`](./AuditingReportingCompliance/Export-SecureScoreReport/Export-SecureScoreReport.ps1) | `AuditingReportingCompliance` | Connects to Microsoft Graph Security API to audit Secure Score and export all Improvement Actions to CSV. |
| **Episode 08** | [ThreatHuntingQueries.kql](./KQL-Queries/ThreatHuntingQueries.kql) | KQL-Queries / ThreatHunting | 6 production KQL queries detecting LOLBins, LSASS dumps, non-browser C2 beacons, cross-domain phish correlation, and custom detection rule. |

---

## 📂 Repository Structure & Modules

### 1. 🛡️ [Auditing, Reporting & Compliance](./AuditingReportingCompliance/)
- **[`Export-SecureScoreReport`](./AuditingReportingCompliance/Export-SecureScoreReport/)**: Automates tenant Secure Score extraction, category point breakdown, and prioritized improvement action CSV reporting via Microsoft Graph. ([Explanation](./AuditingReportingCompliance/Export-SecureScoreReport/Export-SecureScoreReport-Explanation.md))

### 2. 🌐 [Tenant & Domain Configuration](./TenantDomainConfiguration/)
- **[`Deploy-LabBaseline`](./TenantDomainConfiguration/Deploy-LabBaseline/)**: Automated provisioning of enterprise lab personas, departmental security groups, and disaster recovery break-glass accounts. ([Explanation](./TenantDomainConfiguration/Deploy-LabBaseline/Deploy-LabBaseline-Explanation.md))

### 3. 🔐 [Security & Conditional Access](./SecurityAuthConditionalAccess/)
- **[`MFA-Status-Management`](./SecurityAuthConditionalAccess/MFA-Status-Management/)**: Audits MFA registration states, authentication methods, and enforcement across tenant users.

### 4. 👑 [Roles & Privileged Access](./RolesPrivilegedAccess/)
- **`BreakGlass-Setup-Monitoring`**: Emergency access accounts creation, hardening, and sign-in alert triggers.
- **`PIM-Eligibility-Automation`**: Automate Privileged Identity Management (PIM) role assignments and expiration policies.
- **`Role-Assignment-Management`**: Auditing and managing directory roles across admins.

### 5. 💻 [Device Identity Management](./DeviceIdentityManagement/)
- **`BitLocker-Key-Management`**: Audits and retrieves BitLocker recovery keys escrowed in Microsoft Entra.
- **`Device-Auditing`**: Comprehensive auditing of Entra joined, registered, and hybrid devices.
- **`Stale-Device-Cleanup`**: Automated identification and cleanup of inactive tenant device records.

### 6. 👥 [User & Identity Management](./UserIdentityManagement/)
- **`Bulk-UserProvisioning`**: Bulk onboarding and attribute synchronization.
- **`Account-Status-Automation`**: Automated account disablement and lifecycle actions.
- **`Guest-B2B-Lifecycle`**: External identity and B2B guest account review.

### 7. 🏷️ [License & Service Plan Administration](./LicenseServicePlanAdmin/)
- **`Direct-License-Management` & `GBL-Management-Troubleshooting`**: Group-based licensing assignment and troubleshooting.
- **`License-Usage-Cost-Audit`**: License allocation versus utilization analysis.

### 8. 📦 [Application & Service Principal Management](./ApplicationServicePrincipal/)
- **`App-Enterprise-App-Creation`**: App registration and enterprise application deployment.
- **`Credential-Rotation` & `Expiration-Alerting`**: Service principal secret/certificate expiration monitoring.
- **`OAuth-Consent-Automation`**: Delegated and application permission auditing.

---

### 9. 🎯 [KQL Threat Hunting & Advanced Detection Engine](./KQL-Queries/)
- **[ThreatHuntingQueries.kql](./KQL-Queries/ThreatHuntingQueries.kql)**: Production KQL hunting queries for Defender XDR telemetry tables (DeviceProcessEvents, DeviceNetworkEvents, EmailEvents). ([Documentation](./KQL-Queries/README.md))
- **[Simulate-LabIncidents.ps1](./KQL-Queries/Simulate-LabIncidents.ps1)**: Safe attack simulator to trigger telemetry and open test incidents for live hunting drills.

## ⚡ Prerequisites

All scripts in this repository use the official **Microsoft Graph PowerShell SDK**:
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Repository PSGallery
```
Scripts automatically check and install missing sub-modules on launch.

---

## 📺 Official Video Tutorials & Lab Walkthroughs
These scripts accompany hands-on lessons in the **Microsoft Security Stack & SOC Analyst Full Course** by Cloud Knowledge:
- **YouTube Channel**: [Cloud Knowledge](https://www.youtube.com/@CloudKnowledge)
- **Website**: [CloudKnowledge.in](https://cloudknowledge.in)

---

## 📄 License & Contributing
Feel free to fork, submit issues, or contribute pull requests to help expand and improve these automation toolkits for the cybersecurity community!
