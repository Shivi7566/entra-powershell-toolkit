# Group-Audit-Cleanup.ps1 — Explanation

## What this script does
Scans groups across the tenant (or a specific list you provide) and reports three common hygiene issues: groups with no owners, groups with no members, and disabled user accounts that are still sitting in group membership. Optionally, it can automatically clean up that last issue.

## Why this script is structured differently from the others

Every script so far has been "take a CSV of intended actions, apply each one." This one is the opposite pattern — it's a **read/report tool first**, with cleanup as an optional add-on, because you generally want to *see* what's wrong across your groups before deciding what to fix, rather than pre-deciding fixes row by row.

## Step-by-step breakdown

**Parameters block**
- `-GroupNamesCsv` (optional) — if provided, only audits the groups listed in that file. If omitted, the script audits **every group in the tenant**.
- `-RemoveDisabledMembers` (optional switch) — if included on the command line, the script doesn't just report disabled members still in groups, it actually removes them.
- `-LogPath` (optional, auto-timestamped).

Run it in report-only mode first:
```powershell
.\Group-Audit-Cleanup.ps1
```
Or scoped to specific groups:
```powershell
.\Group-Audit-Cleanup.ps1 -GroupNamesCsv ".\groups-to-check.csv"
```
Or with actual cleanup enabled:
```powershell
.\Group-Audit-Cleanup.ps1 -RemoveDisabledMembers
```

**Connecting to Graph**
Requests `Group.ReadWrite.All` (write access needed only if `-RemoveDisabledMembers` is used), `User.Read.All` (to check each member's enabled status), and `Directory.Read.All`.

**Deciding what to audit**
If `-GroupNamesCsv` was given, the script reads that file and looks up each named group individually. Otherwise, `Get-MgGroup -All` pulls every group in the tenant — worth knowing this could be a large, slower operation in a big tenant, since it also then checks membership on every single one.

**The main audit loop**
For each group:

1. **Ownerless check** — `Get-MgGroupOwner` returns the owner list; if it's empty, that's logged as an `OwnerlessGroup` finding. Groups with no owner are a real governance risk — no one is accountable for managing membership, and if the group controls access to something sensitive, there's literally no one positioned to review or revoke that access.

2. **Empty group check** — `Get-MgGroupMember -All` retrieves every member; if the count is zero, that's logged as `EmptyGroup` — often a sign of a group created for a project that never launched, or one that's outlived its purpose.

3. **Disabled member check** — this is the more involved part. For every member that is actually a **user** (filtering out other groups or service principals nested inside, which don't have an `AccountEnabled` property the same way), the script fetches that user's current `AccountEnabled` status. If `false`, it's logged as `DisabledMemberStillInGroup` — this matters because group membership can carry access rights (SharePoint sites, apps, licenses) that a disabled account might still technically retain access to depending on how those permissions were granted.

4. **Optional cleanup** — only if `-RemoveDisabledMembers` was passed on the command line, the script actually removes that disabled user from the group with `Remove-MgGroupMemberByRef`, and logs a separate `CleanupPerformed` finding documenting exactly what was removed.

**No findings case**
If the whole audit comes back completely clean, the script prints a plain confirmation message rather than an empty, confusing report.

**Output**
All findings — whatever type — go into one combined CSV log and a console table, so you get one report covering every issue category in a single file.

## Sample scoped CSV structure (for `-GroupNamesCsv`)

```csv
GroupName
Marketing Team
Project Falcon Team
All Engineering
```

## Notes
- **Run this without `-RemoveDisabledMembers` first**, review the report, and only re-run with cleanup enabled once you're confident about what it's going to remove — this is a good habit for any script capable of making changes based on a scan rather than an explicit CSV instruction.
- This audit doesn't currently check **nested group membership depth** or **duplicate/near-duplicate group names** — both reasonable extensions if you find this useful and want to grow it further.
- Auditing every group tenant-wide (no `-GroupNamesCsv`) can take a while in a large tenant, since it's making at least 2 Graph calls per group (owners + members) plus one more per disabled-looking member — for very large tenants, consider running it scoped to specific groups on a rotating schedule instead of the whole tenant every time.
