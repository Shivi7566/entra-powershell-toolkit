# Bulk-Group-Maintenance.ps1 — Explanation

## What this script does
Creates, updates, deletes, and manages membership for **security groups** — both traditional assigned (manual membership) and dynamic (rule-based, auto-managed membership) — all from a single CSV, with the ability to mix both group types in the same batch.

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped).

**Connecting to Graph**
Requests `Group.ReadWrite.All` and `Directory.ReadWrite.All` — covers group CRUD and membership changes.

**The switch statement (core logic)**

- **`create`** — this is the most involved branch, since it needs to build a different request body depending on `MembershipType`:
  - If `MembershipType` is `dynamic`, the script requires a `MembershipRule` column value (throws an error immediately if missing — no point creating a dynamic group with no rule), sets `GroupTypes` to `["DynamicMembership"]`, and sets `MembershipRuleProcessingState` to `"On"` so the rule starts evaluating immediately rather than sitting paused.
  - Otherwise, it creates a standard **assigned** group with an empty `GroupTypes` array — membership will be managed manually via the `addmember`/`removemember` actions below.
  - Every group is created as `MailEnabled: false, SecurityEnabled: true` — a pure security group, not a Microsoft 365 group (that's covered by a separate, upcoming script since M365 groups have different required properties).

- **`update`** — looks up the group by `DisplayName`, then updates whichever fields are present in the row: `Description`, and/or `MembershipRule` (useful for adjusting an existing dynamic group's rule without recreating the whole group — note this only makes sense for groups that are already dynamic).

- **`delete`** — looks up and removes the group entirely via `Remove-MgGroup`.

- **`addmember`** — looks up both the group and the target user, then adds the user using `New-MgGroupMemberByRef` with an `@odata.id` reference pointing at the user's full directory object URL. This is the standard Graph pattern for adding a member to a group's `members` collection.

- **`removemember`** — same lookups, but calls `Remove-MgGroupMemberByRef` to take the user back out.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch, logging, and disconnect**
Same reliable pattern as every other script in this repo — one row's failure doesn't stop the batch, everything gets logged and printed, session disconnects cleanly.

## Sample CSV structure

```csv
Action,GroupName,MailNickname,Description,MembershipType,MembershipRule,MemberUPN
create,All Engineering,all-engineering,Everyone in the Engineering department,Dynamic,"user.department -eq ""Engineering""",
create,Project Falcon Team,project-falcon,Manually managed project team,Assigned,,
addmember,Project Falcon Team,,,,,jdoe@contoso.com
addmember,Project Falcon Team,,,,,asmith@contoso.com
removemember,Project Falcon Team,,,,,formeruser@contoso.com
update,All Engineering,,Updated description text,,,
delete,Old Temp Group,,,,,
```

## Notes
- **`addmember`/`removemember` will fail (or are meaningless) on dynamic groups** — Entra ID calculates dynamic group membership automatically from the rule; you can't manually add or remove a member from one. Only use those two actions against groups created with `MembershipType: Assigned`.
- Dynamic membership rules can take a little time to fully evaluate against the whole directory after a group is created or its rule changes — don't be surprised if membership doesn't populate instantly; it's asynchronous in the background.
- Double-quote escaping in `MembershipRule` (like `"Engineering"` inside the rule string) needs care in CSV — the sample above shows the correct way to embed quotes within a quoted CSV field (doubled `""`).
