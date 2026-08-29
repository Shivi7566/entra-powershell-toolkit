# Expiration-Alerting.ps1 — Explanation

## What this script does
Scans the entire tenant — every app registration and every service principal — for credentials approaching expiry: client secrets, certificates on app registrations, certificates on service principals, and SAML token signing keys. Produces a single prioritized report so nothing quietly expires and breaks an integration without warning.

## Why this scans everything rather than working from a CSV

Unlike most scripts in this repo, expiration alerting only works if it's comprehensive — a CSV of "apps to check" requires someone to remember to add every new app to that list, which defeats the purpose of an early-warning system. This script deliberately scans the **whole tenant** every time it runs, so nothing can be accidentally left out.

## Step-by-step breakdown

**Parameters block**
- `-WarningThresholdDays` (default `30`) — anything expiring within this window gets flagged.
- `-CriticalThresholdDays` (default `7`) — a tighter, more urgent threshold within the warning window, for a two-tier severity system.
- `-LogPath` (auto-timestamped).

**Connecting to Graph**
Requests `Application.Read.All` and `Directory.Read.All` — this script is entirely read-only, no write permissions needed at all.

**The `Get-Severity` helper function**
Centralizes the threshold logic into one place, returning one of four values based on days remaining until expiry:
- **`Expired`** — already past its end date (negative days remaining) — the most urgent possible state, something is likely already broken.
- **`Critical`** — within `CriticalThresholdDays` (default 7) — act now.
- **`Warning`** — within `WarningThresholdDays` (default 30) but beyond critical — plan the rotation soon.
- **`OK`** — outside both thresholds — no action needed, and importantly, **not included in the report at all**, keeping the output focused on what actually needs attention.

**Part 1 — Scanning application registrations**
For every app in the tenant (`Get-MgApplication -All`), the script checks two collections:
- `PasswordCredentials` (client secrets) — same data source as `Credential-Rotation.ps1`'s `listcredentials` action, but here checked across **every** app at once rather than one at a time.
- `KeyCredentials` (certificates) on the application object.

Each credential's severity is calculated, and anything not `OK` gets added to the findings list.

**Part 2 — Scanning service principals**
This is the part that goes beyond what `Credential-Rotation.ps1` covers, since that script only touches the application object. Service principals can carry their **own separate** credentials:
- `KeyCredentials` on the service principal itself — most commonly **SAML token signing certificates**, used when the app is configured for SAML-based single sign-on rather than OAuth/OIDC.
- `PreferredTokenSigningKeyEndDateTime` — a dedicated property specifically tracking when the currently-preferred SAML signing key expires, checked separately since it's the specific field Entra ID actually uses to determine which signing key is active for SAML token issuance.

**Reporting**
If nothing needs attention, the script says so plainly rather than producing a confusing empty file. Otherwise, findings are sorted by `DaysRemaining` ascending — so the single most urgent item (likely already expired, or expiring tomorrow) appears at the very top of both the console table and the exported CSV.

## Sample usage

```powershell
.\Expiration-Alerting.ps1
```
Or with tighter thresholds for a more paranoid weekly check:
```powershell
.\Expiration-Alerting.ps1 -WarningThresholdDays 60 -CriticalThresholdDays 14
```

## Notes
- **This is the single most valuable script to run on a recurring schedule** in this entire folder — a client secret expiring unnoticed is one of the most common real-world causes of "the integration just stopped working overnight" incidents. A weekly scheduled run with results emailed or posted to a monitoring channel turns this from a reactive fire-drill into routine maintenance.
- **SAML token signing certificate expiry is a distinct and often-overlooked risk** — when a SAML signing cert expires, SSO for that specific application stops working, but nothing else in the tenant is affected, so it's easy to miss until users of that one app start reporting login failures. This script surfaces it specifically for that reason.
- Once this report flags something, the actual fix depends on credential type: client secrets and app-registration certificates get rotated using `Credential-Rotation.ps1`; SAML signing certificates are typically renewed through the Enterprise Application's own "Single sign-on" configuration page in the admin center, since generating a new SAML signing cert isn't currently a simple Graph write operation.
