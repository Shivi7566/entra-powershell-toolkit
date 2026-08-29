# Device-Auditing.ps1 — Explanation

## What this script does
Produces a complete inventory and health summary of every device object in the tenant — categorizing by join type (Entra Joined, Hybrid Joined, Entra Registered), operating system, compliance state, and flagging two risk conditions: devices with no registered owner, and devices that haven't signed in recently.

## The three join types, briefly

- **Microsoft Entra Joined** (`AzureAd`) — a device fully joined to Entra ID directly, typically company-owned Windows devices set up via Autopilot or similar.
- **Hybrid Microsoft Entra Joined** (`ServerAd`) — a device joined to on-premises Active Directory *and* registered with Entra ID via Entra Connect — common in organizations still running traditional on-prem AD alongside cloud identity.
- **Microsoft Entra Registered** (`Workplace`) — a personal or BYOD device that's just registered (not fully joined) for things like app-based MFA or accessing company email — the loosest form of device trust.

This distinction matters a lot for security posture, which is why the script's very first job is sorting every device into these buckets.

## Step-by-step breakdown

**Parameters block**
- `-StaleThresholdDays` (default `90`) — controls what counts as "stale" for reporting purposes. Note this script only **reports** staleness; it doesn't remove anything — that's the deliberately separate next script in this folder.
- Two separate log paths: `-InventoryLogPath` (the full per-device export) and `-SummaryLogPath` (aggregated counts) — kept as two files since they're different shapes of data, one row-per-device versus one row-per-category.

**Connecting to Graph**
Requests `Device.Read.All` and `Directory.Read.All` — entirely read-only, matching this script's role as a pure audit tool.

**Fetching all devices once**
`Get-MgDevice -All` retrieves every device in one pass, explicitly requesting only the properties this script actually uses — keeping the query efficient in tenants with large device counts.

**Building the per-device inventory**
For each device:
1. **Translates `TrustType`** into the friendly join-type names above via a `switch` statement — the raw API values (`AzureAd`, `ServerAd`, `Workplace`) aren't self-explanatory without this translation.
2. **Looks up the registered owner** via `Get-MgDeviceRegisteredOwner` — as covered in the Graph API toolkit's `Devices.md`, a device can have at most one registered owner, so this is a single lookup rather than a collection to iterate carefully.
3. **Calculates staleness** by comparing `ApproximateLastSignInDateTime` against the cutoff date, and separately flags devices that have **never** signed in at all (a `$null` last-sign-in value) as a distinct condition from "signed in a long time ago."
4. **Flags ownerless devices** — a device with no registered owner is a real hygiene concern, since there's no clear person accountable for it.

**Building the summary**
Rather than just dumping the raw inventory, the script also produces aggregated counts — grouped by join type, by operating system, by compliance state, and totals for each risk flag — giving you a quick "state of the fleet" view without having to open the full inventory file and pivot it yourself.

**Console output**
Prints the summary table, plus a preview (first 20 rows) of ownerless and stale devices directly to the console — the two lists you're most likely to want to act on immediately, without needing to open the exported CSV first.

## Sample usage

```powershell
.\Device-Auditing.ps1
```
Or with a tighter staleness window:
```powershell
.\Device-Auditing.ps1 -StaleThresholdDays 45
```

## Notes
- **This script is intentionally read-only** — it's the "see what's actually out there" step. Pair it with the next script in this folder for actually acting on stale/inactive devices once you've reviewed this report.
- **`IsCompliant` will show as unknown/null for devices not enrolled in an MDM solution** like Intune — a large "Unknown/Not Applicable" compliance count isn't necessarily alarming on its own, especially for `Workplace`-registered BYOD devices, which typically aren't expected to report compliance at all.
- Run this **before** any device cleanup activity — a clear picture of what exists, who owns it, and how stale it is should always come before deciding what to remove.
