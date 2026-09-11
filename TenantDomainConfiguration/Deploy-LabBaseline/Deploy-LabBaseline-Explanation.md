# Deploy-LabBaseline.ps1 - Explanation

## What this script does
Deploys a complete, production-grade identity and security testing baseline into a Microsoft Entra ID (Azure AD) lab tenant. In a single execution, it:
1. **Verifies and installs required Microsoft Graph PowerShell SDK modules** (`Authentication`, `Identity.DirectoryManagement`, `Users`, `Groups`).
2. **Authenticates securely to Microsoft Graph** with least-privilege scoped permissions.
3. **Discovers your default initial tenant domain** (`*.onmicrosoft.com`) dynamically so no hardcoded tenant names are needed.
4. **Provisions 6 Departmental Security Groups** (`SG-Executives`, `SG-Finance`, `SG-SecOps`, `SG-Sales`, `SG-Engineering`, `SG-AllLabUsers`).
5. **Provisions 9 Enterprise Persona Users** across Executive, Finance, SecOps/IT, Sales, and Engineering with full metadata (Job Title, Department, UPN).
6. **Populates Group Memberships** automatically adding each user to their departmental security group and the tenant-wide lab group.
7. **Provisions an Emergency Break-Glass Account** (`EmergencyBreakGlass-Admin@<TenantDomain>`) for disaster recovery and exclusion from Conditional Access policies.

---

## Prerequisites & Required Graph Scopes

To run this script, connect with an account holding **Global Administrator** or **Privileged Role Administrator** in your lab tenant.

The script requests the following Microsoft Graph permissions:
- `User.ReadWrite.All`: Create and configure persona users and passwords.
- `Group.ReadWrite.All`: Create security groups and manage group memberships.
- `Directory.ReadWrite.All`: Discover initial tenant domain and query directory objects.

---

## Step-by-step breakdown

### 1. Parameter Block & Defaults
The script accepts an optional parameter `-DefaultPassword`. If omitted, it defaults to a strong lab password:
```powershell
.\Deploy-LabBaseline.ps1 -DefaultPassword "YourStrongPassword123!"
```

### 2. Module Check & Auto-Installation
Iterates through the required Microsoft Graph sub-modules. If any module is missing, it auto-installs it from the PowerShell Gallery (`PSGallery`) under `-Scope CurrentUser`, removing the need for elevated local admin rights to install modules.

### 3. Dynamic Initial Domain Discovery
Queries `Get-MgDomain` filtering by `IsInitial -eq $true` to automatically resolve your tenant's primary `*.onmicrosoft.com` routing domain. This ensures persona UPNs (`User@tenant.onmicrosoft.com`) always match your tenant without manual editing.

### 4. Security Group Provisioning
Provisions 6 security-enabled groups:
- `SG-Executives`: Executive leadership team members.
- `SG-Finance`: Finance, accounting, and payroll personnel.
- `SG-SecOps`: Security Operations Center (SOC) analysts and IT administrators.
- `SG-Sales`: Sales and business development representatives.
- `SG-Engineering`: Software engineering and DevOps personnel.
- `SG-AllLabUsers`: Catch-all container group containing all provisioned lab accounts for tenant-wide policy assignment and testing.

Existing groups are detected and preserved to make the script completely **idempotent** (safe to re-run).

### 5. Persona Provisioning Matrix
Creates 9 structured users mirroring typical corporate roles:
| Name | Title | Department | Security Group |
|---|---|---|---|
| Megan Bowen | Chief Executive Officer | Executive | SG-Executives |
| Alex Wilber | Chief Financial Officer | Finance | SG-Finance |
| Lynne Robbins | Accounts Payable Lead | Finance | SG-Finance |
| Adele Vance | Senior SOC Analyst | Security Operations | SG-SecOps |
| Allan Deyoung | IT Administrator | Information Tech | SG-SecOps |
| Pradeep Gupta | Helpdesk Specialist | Information Tech | SG-SecOps |
| Joni Sherman | VP of Sales | Sales & Marketing | SG-Sales |
| Lee Gu | Account Executive | Sales & Marketing | SG-Sales |
| Diego Siciliani | Lead Software Engineer | Engineering | SG-Engineering |

Each user is assigned their department group and `SG-AllLabUsers`.

### 6. Emergency Break-Glass Account
Provisions `EmergencyBreakGlass-Admin@<tenant-domain>`:
- Configured with a cloud-only identity.
- Flagged explicitly as an emergency access account.
- **Critical Security Requirement**: Exclude this account from ALL Conditional Access (CA) policies to prevent accidental lockout scenarios.

---

## Usage Examples

### Basic Deployment (Default Lab Password)
```powershell
.\Deploy-LabBaseline.ps1
```

### Custom Password Deployment
```powershell
.\Deploy-LabBaseline.ps1 -DefaultPassword "CustomSecureP@ss2026!"
```

---

## Course Reference
- **Course**: Microsoft Security Stack / SOC Analyst Full Course (Cloud Knowledge)
- **Episode**: 04 (Lab Tenant Setup & Persona Deployment)
