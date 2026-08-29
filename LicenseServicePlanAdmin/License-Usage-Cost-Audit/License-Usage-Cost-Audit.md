# License-Usage-Cost-Audit.ps1 — Explanation

## What this script does
Produces three separate cost-optimization reports in a single run: overall SKU utilization (how many purchased seats are actually consumed), licensed users who haven't signed in for a configurable period (prime candidates for license reclaim), and users holding more than one license SKU at once (worth a manual look for potential overlap/redundancy).

## Step-by-step breakdown

**Parameters block**
- `-InactiveDaysThreshold` (optional, default `90`) — controls how many days of no sign-in activity counts as "inactive" for the second report.
- Three separate `-...LogPath` parameters, one per report, each auto-timestamped — keeping the three outputs as distinct files rather than cramming different-shaped data into one CSV.

No CSV input is needed here — this script reads the tenant's current state directly rather than applying a list of predefined actions.

**Connecting to Graph**
Requests `Organization.Read.All` (SKU data), `User.Read.All`, and `AuditLog.Read.All` (needed specifically for `signInActivity`, which is audit-log-adjacent data).

**Report 1 — SKU utilization**
For every subscribed SKU, the script reads `PrepaidUnits.Enabled` (seats you're paying for) against `ConsumedUnits` (seats actually assigned), calculates the gap (`AvailableUnits`) and a utilization percentage. Sorted by `AvailableUnits` descending when displayed, so the SKUs with the most unused, still-being-paid-for seats surface at the top — the most directly actionable cost signal in the whole script.

**Fetching all users once**
`Get-MgUser -All` runs once, requesting `userPrincipalName`, `assignedLicenses`, and `signInActivity` together — the `-ConsistencyLevel eventual` parameter is required by Graph specifically when querying `signInActivity` at scale like this.

**Report 2 — Inactive licensed users**
For every user who actually holds at least one license (`AssignedLicenses.Count -gt 0`), the script checks their `LastSignInDateTime`. If that's missing entirely (never signed in) or older than the cutoff date (`today minus $InactiveDaysThreshold`), the user is flagged, along with which SKUs they're holding — this is the report that most directly translates to "here's where money is being wasted on people not using their licenses."

**Report 3 — Multi-license users**
Any licensed user holding **more than one** SKU at once gets flagged here, purely for human review. The script doesn't try to guess which combinations are wasteful (that requires organizational knowledge — e.g. is E1 + a standalone Teams license actually redundant, or intentional?) — it just surfaces the list so you can make that call.

**Fixing the SKU name lookup**
Each user's `AssignedLicenses` entries only contain a `SkuId` (a GUID), not a friendly name — so for each one, the script loops through and matches it against the tenant's full SKU list (`$allSkus`) to resolve the actual `SkuPartNumber` for display. This has to be a proper `foreach` loop with its own variable rather than a nested `Where-Object` using `$_` twice — nesting two `$_` references from different pipeline stages is a classic scripting trap, since the inner `$_` shadows the outer one instead of referring to it.

**Output**
Each of the three reports gets its own CSV export and its own console table, all in one script run.

## Sample usage

```powershell
.\License-Usage-Cost-Audit.ps1
```
Or with a stricter inactivity window:
```powershell
.\License-Usage-Cost-Audit.ps1 -InactiveDaysThreshold 45
```

## Notes
- **Graph doesn't expose actual pricing** — this script reports seat counts and utilization percentages, not dollar figures. To translate "12 unused SPE_E3 seats" into an actual cost savings number, you'll need to cross-reference your organization's actual per-seat pricing separately.
- The inactive users report pairs naturally with `Direct-License-Management.ps1`'s reclaim logic — this script tells you **who** to look at, that script's `-ReclaimFromDisabledUsers` (or a manual `remove` row) is how you'd actually act on it. Consider extending that reclaim logic to also catch "inactive but still enabled" accounts, not just disabled ones, if your organization is comfortable automating that further.
- Multi-license overlap detection here is intentionally conservative — it flags candidates for a human to judge rather than making automated removal decisions, since license combinations that look redundant on paper are sometimes genuinely intentional (e.g. a base license plus an add-on SKU).
