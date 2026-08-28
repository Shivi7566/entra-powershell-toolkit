# Attribute-Standardization-Sync.ps1 — Explanation

## What this script does
Takes a source-of-truth CSV (e.g. exported from an HR system) and syncs standardized versions of key attributes — Department, Job Title, Office Location, City, Country, Mobile Phone, Employee ID — into Entra ID, **only updating fields that are actually out of sync**, rather than blindly overwriting everything on every run.

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional). This must be the very first thing in the script — PowerShell requires the `param()` block to come before any other code, including function definitions, or the script won't parse correctly.

**Helper functions — defined after param(), before the main logic**

- **`Format-StandardizedText`** — takes a raw text value, trims leading/trailing whitespace, collapses any repeated internal spaces down to single spaces, and converts it to Title Case (e.g. `"  ENGINEERING  dept"` becomes `"Engineering Dept"`). This is the core of "standardisation" — it doesn't matter how messily the source data was entered, this function normalizes it to one consistent format.

- **`Format-StandardizedPhone`** — strips everything from a phone number except digits and a leading `+`, so `"+1 (555) 123-4567"` and `"+15551234567"` both normalize to the same value. This matters because without normalization, the script would think a properly-formatted number needs "updating" every single run, just because of cosmetic differences.

**Connecting to Graph**
Requests `User.ReadWrite.All` — the only permission needed for reading and writing these standard directory attributes.

**The sync logic — the important part**

For each row in the CSV:
1. **Fetch the current values** from Entra ID with `Get-MgUser`, explicitly requesting only the properties this script cares about (`-Property` parameter) — keeping the query efficient rather than pulling the entire user object.
2. **Build a standardized version** of every incoming value using the helper functions above.
3. **Compare old vs. new**, field by field. `$currentUser.AdditionalProperties[...]` is used to read the raw current value (Graph SDK objects store less-common properties in this dictionary rather than as fixed top-level properties).
4. **Only add a field to `$changes` if it's actually different** from what's already there.
5. If `$changes` ends up empty, the row is marked `NoChange` — **no API call is made at all**. If there are real differences, a single `Update-MgUser` call sends only the changed fields.

This "diff before write" pattern is what makes this genuinely different from the earlier bulk-update script — you can run this against your entire user base on a recurring schedule (e.g. nightly), and it will only touch the handful of accounts that actually drifted out of standard, rather than hammering the API with a write for every single user every time.

**Logging and output**
Every row logs its UPN, final status (`Updated`, `NoChange`, or `Failed`), a message describing what happened, and a timestamp — exported to CSV and printed as a table.

## Sample CSV structure

```csv
UserPrincipalName,Department,JobTitle,OfficeLocation,City,Country,MobilePhone,EmployeeId
jdoe@contoso.com,engineering,software developer,building a - floor 3,seattle,united states,+1 (555) 123-4567,E10234
asmith@contoso.com,SALES  ,Sales Manager,,new york,usa,555.987.6543,E10567
```

## Notes
- This script is a good candidate for a **scheduled task** — running it nightly against a fresh HR export keeps Entra ID attributes continuously aligned with the source system, catching drift (manual edits, typos, inconsistent entry) automatically over time.
- The "diff before write" approach also reduces unnecessary entries in your audit logs (see `AuditLogs.md` in the Graph API toolkit) — every real update still shows up there, but you won't flood the log with no-op writes.
- `Format-StandardizedText` uses simple Title Case — if your organization has specific exceptions (e.g. acronyms like "IT" or "HR" that shouldn't be title-cased to "It"/"Hr"), you'll want to extend that function with a lookup list of exceptions before relying on it at scale.
