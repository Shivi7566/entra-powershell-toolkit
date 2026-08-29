# MFA-Status-Management.ps1 — Explanation

## What this script does
Reports on MFA registration status — both for individual users and tenant-wide — and manages specific authentication methods (removing phone, email, Microsoft Authenticator, or FIDO2 registrations). This builds on `Credential-Management.ps1` from the `UserIdentityManagement` folder, but focuses specifically on MFA capability reporting and covers more method types.

## Two modes, same as several earlier scripts

- `-CsvPath` — per-user actions: checking one person's detailed status, listing their methods, or removing a specific method type.
- `-AuditMfaStatus` — a tenant-wide scan finding everyone who isn't MFA-capable, independent of any CSV.

## Step-by-step breakdown

**Parameters block**
Both `-CsvPath` and `-AuditMfaStatus` are optional and independent — you can run either, or both together in one pass.

**Connecting to Graph**
Requests `UserAuthenticationMethod.ReadWrite.All`, `Reports.Read.All` (needed for the registration details report), and `User.Read.All`.

**Part 1 — CSV-driven per-user actions**

- **`checkstatus`** — calls the `userRegistrationDetails` report endpoint for a **single specific user**, via `Invoke-MgGraphRequest` since this is reporting data rather than a standard directory object. Returns `isMfaRegistered` (has the user set up at least one MFA method), `isMfaCapable` (a slightly different, more complete signal — capable of actually satisfying an MFA challenge), which methods are registered, and their default method. `isMfaCapable` is generally the more useful field to check — a user can technically have `isMfaRegistered: true` from a weak/legacy method while still not being fully MFA capable depending on tenant policy.

- **`listmethods`** — same pattern as `Credential-Management.ps1`'s equivalent action: pulls every registered method and extracts clean type names from the OData metadata.

- **`removemethod`** — expanded compared to the earlier credential script, now supporting four method types via a nested switch: `phone`, `email`, `microsoftAuthenticator`, and `fido2` — each using its own dedicated Get/Remove cmdlet pair, since Entra ID models each authentication method type as its own distinct resource collection rather than one generic "methods" list you can write to directly.

**Part 2 — Tenant-wide MFA audit (`-AuditMfaStatus`)**

This is the part that answers "how exposed are we, overall?" rather than checking one person at a time:
1. Fetches the **entire tenant's** registration details report in one call, then explicitly handles pagination via `@odata.nextLink` — this report can be large in bigger tenants, and a single page won't contain everyone.
2. Splits the results into `isMfaCapable eq $false` and `isMfaRegistered eq $false` groups, printing overall counts to the console immediately for a quick health signal.
3. Logs every **not-capable** user individually to the results/CSV, along with whatever methods (if any) they do have registered — this becomes your actionable follow-up list, e.g. for a targeted MFA enrollment campaign.

## Sample CSV structure

```csv
Action,UserUPN,MethodType
checkstatus,jdoe@contoso.com,
listmethods,jdoe@contoso.com,
removemethod,formerphone@contoso.com,phone
removemethod,oldauthenticator@contoso.com,microsoftAuthenticator
```

## Sample tenant-wide audit usage

```powershell
.\MFA-Status-Management.ps1 -AuditMfaStatus
```

## Notes
- **`isMfaCapable` is generally more meaningful than `isMfaRegistered`** for a security posture review — capability reflects whether the user could actually complete an MFA challenge right now, which is the number that matters if you're rolling out a Conditional Access policy requiring MFA and want to know who would get locked out.
- Before removing someone's **last remaining** MFA method with `removemethod`, run `listmethods` first — same caution as the earlier credential management script: stripping someone's only method can lock them out of self-service recovery entirely, not just MFA.
- The tenant-wide audit report is a strong companion to rolling out or tightening a Conditional Access MFA requirement (see the upcoming CA policy scripts in this same folder) — run the audit first, get the not-capable list down as close to zero as practical, *then* enforce the policy, rather than enforcing first and generating a wave of lockout helpdesk tickets.
