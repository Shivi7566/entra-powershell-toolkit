# Bulk-UserProvisioning.ps1 — Explanation

## What this script does
Reads a CSV file of users and, for each row, either **creates**, **updates**, or **deprovisions** (disables) that user in Microsoft Entra ID — all in a single run, with a full success/failure log at the end.

## Step-by-step breakdown

**Parameters block**
The script takes two inputs: `-CsvPath` (required, points to your input file) and `-LogPath` (optional, auto-generates a timestamped filename if you don't provide one). Run it like:
```powershell
.\Bulk-UserProvisioning.ps1 -CsvPath ".\users.csv"
```

**Connecting to Graph**
`Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All"` opens a sign-in with exactly the permissions this script needs — nothing broader. `-NoWelcome` just suppresses the banner text.

**Results collection**
`$results` is an empty list that holds one record per user processed, so you get a full report at the end instead of just watching text scroll by.

**CSV validation**
Before doing anything else, the script checks the CSV file actually exists at the given path, and stops immediately with a clear error if not — better than failing halfway through 200 users.

**The main loop**
`foreach ($row in $users)` walks through every row in your CSV one at a time. Your CSV needs these columns (not all required for every action): `Action`, `UserPrincipalName`, `DisplayName`, `MailNickname`, `Password`, `Department`, `JobTitle`, `UsageLocation`.

**The switch statement (core logic)**
Branches on the `Action` column value:
- **`new`** — builds a password profile (forces a password change on first sign-in, best practice) and creates the user with `New-MgUser`.
- **`update`** — looks up the existing user by UPN, then only updates fields that actually have a value in that row (leave columns blank for anything you're not changing).
- **`deprovision`** — looks up the user, disables the account (`AccountEnabled:$false`), and immediately revokes active sign-in sessions with `Revoke-MgUserSignInSession`. This matters: disabling an account alone doesn't kill an already-active session or token — this line forces the user out right away.
- **`default`** — catches typos or unexpected values in the Action column and marks that row "Skipped" instead of silently failing.

**Try/catch per user**
Each row is wrapped in its own `try/catch`, so if one user fails (duplicate UPN, bad password policy, etc.), the script logs the error and **keeps going** to the next user instead of stopping the whole batch.

**Logging every result**
After each row, a record is added to `$results` capturing the UPN, action, status (Success/Failed/Skipped), any error message, and a timestamp.

**Final output**
Once the loop finishes, results are exported to a CSV log file (a permanent audit trail) and also printed to the screen as a formatted table for a quick glance.

**Disconnecting**
`Disconnect-MgGraph` cleanly ends the session at the end.

## Sample CSV structure

```csv
Action,UserPrincipalName,DisplayName,MailNickname,Password,Department,JobTitle,UsageLocation
new,jdoe@contoso.com,John Doe,jdoe,TempP@ss123!,Engineering,Developer,US
update,asmith@contoso.com,Alice Smith,,,,Sales Manager,
deprovision,bwilson@contoso.com,,,,,,
```
