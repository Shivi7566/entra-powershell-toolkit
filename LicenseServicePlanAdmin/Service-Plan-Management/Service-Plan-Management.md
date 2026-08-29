# Service-Plan-Management.ps1 — Explanation

## What this script does
Enables and disables individual **service plans** within a license a user already has — for example, keeping someone's Microsoft 365 E3 license but turning off just the Yammer or Stream component — without needing group-based licensing or removing the whole SKU.

## The core challenge this script solves

Microsoft Graph doesn't offer a simple "toggle this one feature on/off" call. Instead, disabling a service plan means **re-submitting the entire license assignment** for that SKU, with a complete list of every service plan you want disabled (not just the one you're changing). Get this wrong — for instance, submitting a list with only the newly-disabled plan and forgetting ones that were already disabled — and you'd accidentally re-enable everything else. This script's core job is building that list correctly every time.

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped).

**Connecting to Graph**
Requests `LicenseAssignment.ReadWrite.All` and `User.Read.All`.

**Pre-loading SKUs once**
Same efficiency pattern as the earlier license scripts — `Get-MgSubscribedSku -All` runs once before the loop.

**Looking up user and SKU together**
Both the user and the relevant SKU are resolved before the switch statement, since all three actions need both.

**The switch statement (core logic)**

- **`disableplan`** — this is the most involved branch, and it's worth walking through carefully:
  1. Finds the target service plan's ID by matching `ServicePlanName` against the SKU's known service plans.
  2. Calls `Get-MgUserLicenseDetail` to see **what's currently disabled** for this user on this specific SKU — this is the critical step. It reads every service plan with `ProvisioningStatus -eq "Disabled"` to build the *existing* disabled list.
  3. Adds the newly-targeted plan's ID to that existing list (using `Select-Object -Unique` to avoid duplicates if it was somehow already there).
  4. Calls `Set-MgUserLicense` with the **complete, updated** disabled list — this is what correctly preserves any plans that were already disabled while adding the new one, rather than overwriting them.

- **`enableplan`** — the mirror image: fetches the current disabled list the same way, then **filters out** the target plan's ID from that list (`Where-Object { $_ -ne $targetPlan.ServicePlanId }`), and submits the now-shorter list — re-enabling just that one plan while leaving any other previously-disabled plans untouched.

- **`listplans`** — a read-only helper: fetches the user's current license detail for the SKU and splits their service plans into two comma-separated lists — enabled and disabled — for a quick readable summary before deciding what to change.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch, logging, and disconnect**
Same reliable pattern as every other script in this repo. Both `disableplan` and `enableplan` throw a clear error early if the user doesn't actually have that SKU assigned at all — no point building a disabled-plans list against a license they don't have.

## Sample CSV structure

```csv
Action,UserUPN,SkuPartNumber,ServicePlanName
listplans,jdoe@contoso.com,SPE_E3,
disableplan,jdoe@contoso.com,SPE_E3,YAMMER_ENTERPRISE
disableplan,jdoe@contoso.com,SPE_E3,SWAY
enableplan,jdoe@contoso.com,SPE_E3,YAMMER_ENTERPRISE
```

## Notes
- **Always run `listplans` before `disableplan`/`enableplan`** on a user you're not already familiar with — it's the fastest way to see the exact service plan names as they exist for that SKU in your tenant, since these internal names (like `YAMMER_ENTERPRISE`) don't always match the product's friendly marketing name.
- This is the **per-user** equivalent of the `DisabledPlanNames` feature in `GBL-Management-Troubleshooting.ps1`, which does the same thing but at the group level for everyone inheriting that group's license. Use the group-based version for consistent bulk policy, and this script for one-off individual exceptions.
- Because disabling a plan requires resubmitting the *entire* disabled list, never build that list from scratch based on assumptions — always read the current state first (as this script does) before writing back an update.
