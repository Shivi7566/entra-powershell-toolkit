# App-Enterprise-App-Creation.ps1 — Explanation

## What this script does
Creates a new **app registration** (the application object, your app's identity definition) together with its matching **enterprise application** (the service principal, the tenant-local instance you actually assign permissions and access to) in one step, plus handles the separate scenario of registering an enterprise application from an app that already exists elsewhere, and adding owners.

## Why app registration and enterprise application are handled together here

As covered in the Graph API toolkit's `AppRegistrations.md` and `EnterpriseApplications.md`, these are genuinely two different objects — `application` and `servicePrincipal` — linked by a shared `AppId`. Creating an app registration alone does **not** automatically create its enterprise application counterpart; you have to explicitly create the service principal too if you want it to show up under Enterprise Applications in the admin center and be assignable. This script's main `createapp` action does both in sequence so you don't end up with an app registration that's invisible on the Enterprise Applications side.

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped).

**Connecting to Graph**
Requests `Application.ReadWrite.All` and `Directory.ReadWrite.All`.

**The switch statement (core logic)**

- **`createapp`** — the main action:
  1. Builds the base application body with `DisplayName` and `SignInAudience` (defaults to `"AzureADMyOrg"` — single-tenant, the safest default unless you specifically need multi-tenant).
  2. If a `RedirectUri` is provided, the script checks `RedirectType` to decide **which** redirect URI bucket to populate — `Web`, `Spa` (single-page apps, using PKCE-based auth), or `PublicClient` (mobile/desktop apps, no client secret). These are genuinely different authentication flows in Entra ID, so picking the right one matters — a SPA redirect URI registered under `Web` by mistake will cause real authentication failures.
  3. Creates the application with `New-MgApplication`, then **immediately** creates the matching service principal with `New-MgServicePrincipal -AppId $newApp.AppId` — this is the step that makes the app show up as an Enterprise Application, not just an App Registration.
  4. If an `OwnerUPN` is provided, the script adds that user as an owner on **both** objects — the app registration and the service principal — since ownership on one doesn't automatically imply ownership on the other.

- **`createsp`** — for the separate, real-world scenario where you already have an `AppId` from elsewhere (a multi-tenant app from another organization, or a gallery app you're onboarding manually rather than through the gallery UI) and just need to create the tenant-local service principal instance for it. No new application object gets created here — only the enterprise application/service principal, referencing the existing `AppId`.

- **`addowner`** — adds an owner to an **existing** app registration found by display name, for cases where you need to grant ownership after the fact rather than at creation time.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch, logging, and disconnect**
Same reliable pattern as every other script in this repo.

## Sample CSV structure

```csv
Action,DisplayName,SignInAudience,RedirectUri,RedirectType,OwnerUPN,AppId
createapp,Internal Reporting Tool,AzureADMyOrg,https://reports.contoso.com/auth,Web,jdoe@contoso.com,
createapp,Mobile Field App,AzureADMyOrg,com.contoso.fieldapp://auth,PublicClient,,
createsp,,,,,,, 11111111-2222-3333-4444-555555555555
addowner,Internal Reporting Tool,,,,asmith@contoso.com,
```

## Notes
- **`SignInAudience` is difficult to change after creation** in some scenarios (particularly moving from single- to multi-tenant has specific requirements around verified publisher domains) — get this right at creation time rather than planning to adjust it later.
- After running `createapp`, the app has **no API permissions and no credentials (secrets/certificates)** yet — those come from separate scripts later in this folder (OAuth permission granting, credential rotation). A freshly created app can authenticate as itself but won't have access to anything until permissions are explicitly granted.
- `createsp` is genuinely useful for a scenario the Graph API toolkit's `EnterpriseApplications.md` flags too: sometimes you need to manually register an enterprise application for a multi-tenant app that another organization owns, without creating a duplicate/competing app registration of your own for the same `AppId`.
