# BreakGlass-Setup-Monitoring.ps1 — Explanation

## What this script does
Creates emergency-access ("break-glass") accounts configured according to Microsoft's recommended pattern, and separately monitors existing break-glass accounts for two things that should almost never happen: any sign-in activity, and accidental removal from Conditional Access policy exclusions.

## What a break-glass account actually is, and why it's configured differently from every other account in this repo

A break-glass account exists purely as a last-resort way into the tenant if normal admin access is somehow broken — Conditional Access misconfigured and locking everyone out, MFA provider down, PIM approval chain broken, etc. Because its entire purpose is "the emergency door that must always open," it's deliberately configured in ways that would be bad practice for a normal admin account:
- **Standing (permanent) Global Administrator**, not PIM-eligible — if PIM itself is part of what's broken during the emergency, a PIM-eligible break-glass account would be useless.
- **Excluded from Conditional Access policies** — if CA is the thing misconfigured and locking people out, the break-glass account needs to bypass it entirely.
- **Non-expiring password** — nobody should be scrambling to reset a break-glass password during an actual emergency.
- **Not force-changed on first sign-in** — same reasoning; the password needs to work exactly as sealed/stored, with no surprise change prompt blocking emergency access.

## Step-by-step breakdown

**Parameters block**
Two independent modes:
- `-CsvPath` (optional) — for creating new break-glass accounts.
- `-MonitorAccountUPNs` (optional array) with `-SignInLookbackDays` (default `7`) — for the monitoring sweep against existing break-glass accounts.

**The `New-StrongRandomPassword` helper function**
Generates a cryptographically random 32-byte value via `[System.Security.Cryptography.RandomNumberGenerator]`, base64-encodes it, and appends a fixed suffix to guarantee it satisfies typical complexity rules (upper/lower/number/symbol). This is deliberately stronger and more random than the simpler GUID-based password generation used in earlier scripts in this repo, since break-glass credentials need to withstand being written down and stored for a long time without rotation.

**Connecting to Graph**
Requests `User.ReadWrite.All`, `RoleManagement.ReadWrite.Directory`, `AuditLog.Read.All` (for sign-in monitoring), and `Policy.Read.All` (for the CA exclusion check).

**Part 1 — Setup (`-CsvPath`)**
For each row:
1. Generates a strong random password.
2. Creates the user with `PasswordPolicies: "DisablePasswordExpiration"` and `ForceChangePasswordNextSignIn: $false` — the two settings that distinguish this from a normal account creation.
3. Assigns **Global Administrator** as a standing, permanent role assignment (using the same unified RBAC endpoint as `Role-Assignment-Management.ps1`, deliberately **not** the PIM eligibility endpoint from the earlier scripts in this folder).
4. Logs the generated password directly in the result message, with an explicit warning baked into the text itself.

**Part 2 — Monitoring (`-MonitorAccountUPNs`)**
For each break-glass UPN you provide:
1. **Sign-in check** — queries `auditLogs/signIns` filtered to that user's ID within the lookback window. Any result at all is flagged as `ALERT` status, since a properly-managed break-glass account should show **zero** sign-ins during normal operations — any hit here needs immediate investigation, not routine review.
2. **Conditional Access exclusion check** — fetches every enabled CA policy in the tenant and checks whether the break-glass account's ID appears in each policy's `excludeUsers` list. Any enabled policy that does **not** exclude the account is flagged as a `Warning` — this catches a common, dangerous drift scenario: someone edits a CA policy months later, doesn't realize the break-glass account needs to stay excluded, and unknowingly breaks the emergency-access plan without anyone noticing until the day it's actually needed.

## Sample CSV structure (for setup)

```csv
DisplayName,UserPrincipalName,MailNickname
Emergency Access 1,breakglass1@contoso.onmicrosoft.com,breakglass1
Emergency Access 2,breakglass2@contoso.onmicrosoft.com,breakglass2
```

## Sample monitoring usage

```powershell
.\BreakGlass-Setup-Monitoring.ps1 -MonitorAccountUPNs "breakglass1@contoso.onmicrosoft.com","breakglass2@contoso.onmicrosoft.com" -SignInLookbackDays 30
```

## Notes
- **The generated password appears in this script's log output** — this is the single most sensitive log any script in this repo produces. Move it immediately into a proper secure storage mechanism (a physical safe, split-knowledge/dual-control storage, or a dedicated secrets vault), then securely delete the log file. Do not leave it sitting in a folder.
- **Microsoft's own guidance recommends at least two break-glass accounts**, stored/known separately (so one person's unavailability doesn't block emergency access), and explicitly recommends they be cloud-only (not synced from on-premises AD) — this script assumes that setup, since it only touches cloud-based Graph objects.
- **Run the monitoring sweep on a recurring schedule** (daily or weekly) — the entire value of this check is catching drift *before* an actual emergency, not during one. An `ALERT` or `Warning` status here deserves same-day attention, not routine backlog treatment.
- This script deliberately does **not** enroll break-glass accounts in MFA the way normal accounts are — Microsoft's guidance is to exclude them from MFA/CA entirely and rely on the password's strength and extremely limited knowledge of it as the control, rather than layering in a second factor that could itself become unavailable during the exact emergency the account exists for.
