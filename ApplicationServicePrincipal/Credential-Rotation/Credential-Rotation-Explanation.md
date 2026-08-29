# Credential-Rotation.ps1 — Explanation

## What this script does
Manages the full credential lifecycle for app registrations: listing current secrets/certificates and their expiry status, adding a new secret, removing a specific secret, performing a proper **rotation** (add-then-remove, avoiding a gap with no valid credential), and adding a certificate credential.

## A naming note worth clarifying up front

The task this covers is commonly called "service principal credential rotation," but technically, client secrets and certificates live on the **application** object, not the service principal — as covered in the Graph API toolkit's `AppRegistrations.md`. This script operates against `Get-MgApplication`/`Add-MgApplicationPassword`/etc. accordingly. The service principal (enterprise application side) does have its own separate credential-related actions in some scenarios (like SAML signing certificates), but standard OAuth client secrets and certs belong to the application object — that's what this script manages.

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped).

**Connecting to Graph**
Requests `Application.ReadWrite.All`.

**Looking up the app once per row**
Same pattern as the credential management script from `UserIdentityManagement` — the app lookup happens before the switch statement, since every action needs it.

**The switch statement (core logic)**

- **`listcredentials`** — reads both `PasswordCredentials` (secrets) and `KeyCredentials` (certificates) off the app object, and for each one calculates days remaining until expiry (`EndDateTime` minus now). This is the action to run first, regularly, as a health check — before anything is actually expired and breaking authentication.

- **`addsecret`** — adds a new secret with a configurable expiry (`ExpiryMonths`, default `6`) and a description. `Add-MgApplicationPassword` returns the actual secret value in `SecretText`, but **only in this one response** — Graph never lets you retrieve an existing secret's value again after this moment, which is why the value is written directly into the log message here.

- **`removesecret`** — finds a secret by matching its `DisplayName` (the description you gave it when it was created) and removes it via its `KeyId`. Note this means giving secrets meaningful, unique descriptions at creation time really matters — an unnamed or duplicately-named secret makes targeted removal harder.

- **`rotatesecret`** — this is the properly-ordered rotation workflow, and the order matters: it **adds the new secret first**, capturing its value, and only **after** that succeeds does it loop through and remove every old secret (`$oldKeyIds`, captured before the new one was added). This sequencing avoids a window where the app has zero valid secrets — if the new secret creation somehow failed, the old ones are still untouched and the app keeps working while you investigate.

- **`addcertificate`** — reads a certificate file from disk (expects a `.cer` public certificate file, not a private key), converts it to the base64-encoded byte format Graph expects for `KeyCredentials`, and **appends** it to the app's existing certificate list via `Update-MgApplication` — deliberately appending rather than replacing, since certificate rotation typically wants overlap (old cert still valid while the new one is being adopted by downstream systems) rather than an abrupt swap.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch, logging, and disconnect**
Same reliable pattern as every other script in this repo.

## Sample CSV structure

```csv
Action,AppDisplayName,SecretDescription,ExpiryMonths,CertFilePath
listcredentials,Internal Reporting Tool,,,
addsecret,Internal Reporting Tool,CI/CD Pipeline Secret,12,
rotatesecret,Internal Reporting Tool,,6,
removesecret,Old Integration App,Legacy secret 2024,,
addcertificate,Payment Gateway Connector,Production signing cert,,C:\certs\prod-cert.cer
```

## Notes
- **Every secret value shown by this script (`addsecret`, `rotatesecret`) is visible exactly once** — same handling discipline as the break-glass and credential management scripts earlier in this repo: get it into a secrets vault immediately, then delete the log file. There is no way to retrieve a lost secret value later; you'd have to create a new one.
- **`rotatesecret`'s add-first-remove-second ordering is deliberate and important** — don't be tempted to simplify it to remove-then-add, since that creates a real window where the application has no valid credential and any live integration using it would start failing immediately.
- Prefer **certificates over client secrets** where the consuming application supports it — certificates are generally considered more secure (private key never transmitted to Entra ID) and this script's `addcertificate` action only ever needs the **public** certificate file, never a private key.
- Pair `listcredentials` with a scheduled recurring run across all your registered apps, similar in spirit to the group audit script — catching a secret 30 days before expiry is a routine maintenance task; catching it the day after expiry is an incident.
