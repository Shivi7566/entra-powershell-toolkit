# OAuth-Consent-Automation.ps1 — Explanation

## What this script does
Grants **delegated permissions** (scopes an app uses on behalf of a signed-in user) and **application permissions** (app roles an app uses on its own, with no user present) with admin consent, plus reports what an app currently holds — the piece that comes after `App-Enterprise-App-Creation.ps1`, since a freshly created app has neither of these yet.

## The core distinction this script is built around

- **Delegated permissions** — the app acts *as* a signed-in user, limited to whatever that user could do themselves (e.g. `User.Read`, reading the signed-in user's own profile). Consenting for "all users" means every user in the tenant is pre-approved to use the app with this permission, without each person hitting an individual consent prompt.
- **Application permissions** — the app acts *as itself*, with no user context at all (e.g. a background service reading all users' data via `User.Read.All`). These are inherently more powerful and always require admin consent — there's no per-user version of this.

Getting the wrong one wired up is a very common real-world mistake, so this script keeps them as clearly separate actions.

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped).

**Connecting to Graph**
Requests `Application.ReadWrite.All`, `DelegatedPermissionGrant.ReadWrite.All`, and `AppRoleAssignment.ReadWrite.All` — three distinct permissions reflecting the three distinct things this script touches.

**The `Get-ResourceServicePrincipal` helper function**
Most permission grants target **Microsoft Graph** as the resource, so this helper special-cases that lookup using Graph's own well-known, fixed `AppId` (`00000003-0000-0000-c000-000000000000`) rather than matching on display name — display names can technically vary or be localized, but this AppId is constant across every tenant in the world. For any other resource (a different first-party or third-party API), it falls back to a normal display-name lookup.

**Resolving three objects per row, before the switch**
Every action needs: the client app (the app registration being granted permissions), its service principal, and the resource's service principal (what the permission is *against*) — so all three lookups happen once, up front.

**The switch statement (core logic)**

- **`grantdelegated`** — creates an OAuth2 permission grant with `ConsentType: "AllPrincipals"` — this is the admin-consent-for-everyone pattern, functionally identical to what happens when an admin clicks "Grant admin consent" in the portal. The `Scope` property takes a **single space-separated string** of scope names (e.g. `"User.Read Directory.Read.All"`), not an array — a common gotcha worth remembering when building the CSV.

- **`grantapplication`** — this one requires an extra lookup step: application permissions are defined as `AppRoles` on the **resource's** service principal object, each with its own internal ID separate from its human-readable `Value` (like `User.Read.All`). The script searches the resource SP's `AppRoles` collection for the one matching your requested value, then creates the assignment using that role's actual ID — trying to assign by the string value directly would fail, since Graph's assignment API needs the role's GUID.

- **`listgrants`** — reports both grant types together for a given app: delegated scopes currently consented, and application permission role IDs currently assigned. Useful as a pre-flight check before modifying an app's permissions, or as a periodic access review.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch, logging, and disconnect**
Same reliable pattern as every other script in this repo.

## Sample CSV structure

```csv
Action,AppDisplayName,ResourceAppDisplayName,DelegatedScopes,AppRoleValue
grantdelegated,Internal Reporting Tool,Microsoft Graph,User.Read Directory.Read.All,
grantapplication,Nightly Sync Service,Microsoft Graph,,User.Read.All
listgrants,Internal Reporting Tool,Microsoft Graph,,
```

## Notes
- **`grantapplication` is the more powerful, higher-risk action** — application permissions have no user context to limit their blast radius, so an app with `User.ReadWrite.All` as an application permission can modify *any* user in the tenant, unattended. Treat every row using this action with the same scrutiny you'd give a standing privileged role assignment.
- **Granting the same delegated scope twice** (running `grantdelegated` again for the same app/resource/scope combination) will typically create a duplicate or conflicting grant rather than cleanly updating the existing one — run `listgrants` first to check current state before re-granting, especially in a script meant to be re-run idempotently.
- This script assumes the target app **already has a service principal** (created via `App-Enterprise-App-Creation.ps1`'s `createapp` or `createsp` actions) — permission grants happen against the service principal, not the raw application object, so run that script first for any brand-new app.
