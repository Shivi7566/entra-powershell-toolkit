# Account-Status-Automation.ps1 — Explanation

## What this script does
Handles the full range of account status changes from one CSV: enabling, disabling, locking (a stronger form of disable), soft-deleting, restoring, and permanently (hard) deleting user accounts — all logged.

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped). Run it like:
```powershell
.\Account-Status-Automation.ps1 -CsvPath ".\accounts.csv"
```

**Connecting to Graph**
Requests `User.ReadWrite.All` and `Directory.ReadWrite.All` — covers everything from enabling accounts through to permanent deletion.

**The switch statement (core logic)**
Branches on the `Action` column:

- **`enable`** — looks up the user by UPN and sets `AccountEnabled:$true`, restoring sign-in access.

- **`disable`** — sets `AccountEnabled:$false` and immediately calls `Revoke-MgUserSignInSession`. Just like in the deprovisioning script, disabling alone doesn't kill an already-active session — the revoke call forces that.

- **`lock`** — this is the strongest non-destructive action here. It doesn't just disable the account; it also **randomizes the password** to a value nobody (not even the admin running the script) writes down or keeps, using `[System.Guid]::NewGuid()` to generate it. This means even if someone re-enables the account later without resetting the password again, the old password is useless. Combined with disabling and revoking sessions, this is the closest equivalent to a hard "lock" — Entra ID doesn't have a separate native "locked" state the way on-premises AD does, so this script builds that behavior out of three combined actions.

- **`softdelete`** — calls `Remove-MgUser`, which doesn't destroy the account immediately. It moves into Entra ID's 30-day recoverable "deleted items" state, same as a normal delete through the portal.

- **`restore`** — uses `Get-MgDirectoryDeletedItemAsUser` to find the account sitting in the deleted-items state by UPN, then calls `Restore-MgDirectoryDeletedItem` to bring it back exactly as it was before deletion.

- **`harddelete`** — finds the account in the deleted-items state the same way, then calls `Remove-MgDirectoryDeletedItem` — this is **permanent and cannot be undone**, unlike `softdelete`. Only use this action deliberately.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch, logging, and disconnect**
Same reliable pattern as the earlier scripts: each row processes independently so one failure doesn't halt the batch, every outcome gets logged to CSV and printed as a table, and the Graph session closes cleanly at the end.

## Sample CSV structure

```csv
Action,UserPrincipalName
disable,jdoe@contoso.com
lock,compromised.user@contoso.com
softdelete,leaver@contoso.com
restore,leaver@contoso.com
harddelete,olduser@contoso.com
enable,returningemployee@contoso.com
```

## Notes
- **`lock` is the action to reach for during a suspected compromise** — it's faster and more thorough than a plain `disable`, since it also invalidates the known password.
- **`harddelete` bypasses the 30-day recovery window entirely** — treat any CSV row with this action as a one-way door. Consider double-checking that list before running the script against production.
- A soft-deleted account (`softdelete`) still counts toward license consumption in some scenarios until it's fully purged — worth checking `Licenses.md` in the Graph API toolkit repo if you notice licenses not freeing up as expected after a bulk offboarding run.
