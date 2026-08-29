# GBL-Management-Troubleshooting.ps1 — Explanation

## What this script does
Configures Group-Based Licensing (assigning/removing a license SKU on a group so every current and future member inherits it), and troubleshoots the two most common GBL problems: finding which specific members have licensing errors, and manually triggering reprocessing for a stuck user.

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped).

**Connecting to Graph**
Requests `LicenseAssignment.ReadWrite.All` (the least-privileged permission for license operations), `Group.Read.All`, and `User.Read.All`.

**Pre-loading all SKUs once**
`$allSkus = Get-MgSubscribedSku -All` runs **once**, before the main loop, rather than inside it — since every `assigngbl`/`removegbl` row needs to look up SKU details, and the tenant's list of subscribed SKUs doesn't change mid-script. Fetching it once and filtering in-memory (`Where-Object`) is far more efficient than calling Graph again for every row.

**The switch statement (core logic)**

- **`assigngbl`** — looks up the group and the SKU (matched by its human-readable `SkuPartNumber`, like `ENTERPRISEPACK`, rather than the raw GUID — much easier to work with in a CSV). If the CSV row includes a `DisabledPlanNames` column (comma-separated), the script resolves each named service plan against the SKU's actual `ServicePlans` list to get their real service plan IDs — this is what lets you assign a license bundle while turning off specific features within it (e.g. license everyone with Microsoft 365 E3 but disable Yammer). The license is then applied to the group with `Set-MgGroupLicense`, and every current/future member inherits it automatically.

- **`removegbl`** — same SKU lookup, but calls `Set-MgGroupLicense` with an empty `AddLicenses` and the SKU ID in `RemoveLicenses`, unassigning that license from the group.

- **`checkgrouperrors`** — this is the main troubleshooting action. It reads the group's own `licenseProcessingState` (a tenant-level status indicating whether GBL is actively processing, has warnings, or has failed), then loops through every member, checking each user's individual `licenseAssignmentStates` for any entry with `State: "Error"`. Only users actually in an error state get reported — this quickly answers "which specific people are affected" instead of you having to click through the whole membership list in the portal one by one.

- **`reprocessuser`** — calls the beta `reprocessLicenseAssignment` endpoint (referenced in the Graph API toolkit's `Licenses.md`) for one specific user, via `Invoke-MgGraphRequest` since this action isn't yet wrapped by a dedicated SDK cmdlet. This is the standard fix once you know which user has an error — it re-runs group-based license evaluation for just that person without waiting for a full group-wide reprocessing cycle.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch, logging, and disconnect**
Same reliable pattern as every other script in this repo.

## Sample CSV structure

```csv
Action,GroupName,SkuPartNumber,DisabledPlanNames,UserUPN
assigngbl,All Engineering,ENTERPRISEPACK,,
assigngbl,Sales Team,ENTERPRISEPACK,YAMMER_ENTERPRISE,
checkgrouperrors,All Engineering,,,
reprocessuser,,,,jdoe@contoso.com
removegbl,Old Project Team,ENTERPRISEPACK,,
```

## Notes
- **The single most common cause of GBL errors** is a user missing `usageLocation` — flagged already in the Graph API toolkit's `Licenses.md`. If `checkgrouperrors` reports errors across many members at once, check whether those accounts have a usage location set before assuming anything else is wrong.
- SKU part numbers (like `ENTERPRISEPACK` for Microsoft 365 E3) aren't always obvious from the product's marketing name — if you're not sure of the exact string, run `Get-MgSubscribedSku -All | Select SkuPartNumber` once manually to see exactly what your tenant's subscriptions are called internally before building your CSV.
- `checkgrouperrors` can take a while on very large groups, since it makes one additional Graph call per member to check their individual license assignment states — for huge groups, consider narrowing to specific suspect users instead of the full membership if you already have a shortlist.
