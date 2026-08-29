# Direct-License-Management.ps1 — Explanation

## What this script does
Handles three related but distinct license workflows: **direct assignment/removal** of a license on an individual user, **upgrading** a user from one SKU to another in a single operation, and **automated reclaim** of licenses sitting on disabled (offboarded) accounts — recovering seats that are quietly going to waste.

## Step-by-step breakdown

**Parameters block**
This script has **two independent modes** that can be used separately or together:
- `-CsvPath` (optional) — a CSV of `assign`/`remove`/`upgrade` rows for individual users.
- `-ReclaimFromDisabledUsers` (optional switch) — triggers a tenant-wide scan for disabled users still holding direct licenses.

Both `-CsvPath` are optional here (unlike most other scripts in this repo) because you might only want to run the reclaim sweep on its own, without any CSV at all:
```powershell
.\Direct-License-Management.ps1 -ReclaimFromDisabledUsers
```
Or just process a CSV of individual changes:
```powershell
.\Direct-License-Management.ps1 -CsvPath ".\license-changes.csv"
```
Or both in one run.

**Connecting to Graph**
Requests `LicenseAssignment.ReadWrite.All` and `User.ReadWrite.All`.

**The `Get-SkuIdByPartNumber` helper function**
Since almost every action in this script needs to translate a human-readable SKU part number (like `ENTERPRISEPACK`) into its actual SKU ID (a GUID), this small function centralizes that lookup — including throwing a clear error if the SKU doesn't exist in the tenant, rather than letting a cryptic Graph error surface later.

**Part 1 — CSV-driven actions (only runs if `-CsvPath` was provided)**

- **`assign`** — straightforward: adds the specified SKU directly to the user via `Set-MgUserLicense`.
- **`remove`** — removes a specific SKU from the user.
- **`upgrade`** — this is the interesting one: rather than treating "upgrade" as two separate operations (remove old, then add new), it does **both in a single `Set-MgUserLicense` call**, passing the old SKU in `RemoveLicenses` and the new SKU in `AddLicenses` at the same time. This matters because it avoids a brief window where the user has *no* license at all between two separate calls — the swap happens atomically from the user's perspective.

**Part 2 — Automated reclaim (only runs if `-ReclaimFromDisabledUsers` was passed)**

This part runs independently of the CSV, scanning the whole tenant:
1. Fetches every user where `accountEnabled eq false` — i.e., every disabled account, which typically means someone who's been offboarded but not yet fully deleted.
2. For each one, checks their `licenseAssignmentStates` and filters specifically for licenses **not** assigned via a group (`-not $_.AssignedByGroup`) — this distinction is important, because you **cannot** directly remove a group-based license from an individual user; it has to be removed by taking them out of the licensing group instead (see `GBL-Management-Troubleshooting.ps1`). Trying to remove a group-inherited license directly would just fail or have no effect.
3. If the user has any qualifying direct licenses, all of them get removed in one `Set-MgUserLicense` call, freeing up those seats.

**Logging and output**
Both parts write into the **same** `$results` list, so a single run covering both a CSV batch and a reclaim sweep produces one combined log and table at the end.

## Sample CSV structure

```csv
Action,UserUPN,SkuPartNumber,OldSkuPartNumber,NewSkuPartNumber
assign,newhire@contoso.com,SPE_E3,,
remove,contractor@contoso.com,SPE_E3,,
upgrade,jdoe@contoso.com,,SPE_E1,SPE_E3
```

## Notes
- **The reclaim sweep only touches directly-assigned licenses** — it deliberately leaves group-based licenses alone, since removing those requires a different action entirely (removing the user from the licensing group). Running this alongside a regular offboarding process that also handles group removal (see the `Bulk-UserProvisioning.ps1` deprovision action) gives you full license recovery coverage across both licensing methods.
- Consider running `-ReclaimFromDisabledUsers` on a **recurring schedule** (weekly, say) rather than only during active offboarding — it's a good safety net for catching any licenses that slipped through a manual offboarding process.
- Before relying on this in production, run it once without immediately trusting the reclaim numbers — cross-check a handful of flagged users in the admin portal to confirm the license removal matches what you expect, especially in tenants with complex mixed direct+group licensing.
