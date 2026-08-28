# Guest-B2B-Lifecycle.ps1 — Explanation

## What this script does
Manages the full B2B guest lifecycle from a single CSV: sending invitations, resending unredeemed ones, checking whether a guest has accepted, and removing guest accounts — with a full log of every action.

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required), `-DefaultRedirectUrl` (optional — used when a row doesn't specify its own redirect URL, defaults to `https://myapps.microsoft.com`), and `-LogPath` (optional, auto-timestamped). Run it like:
```powershell
.\Guest-B2B-Lifecycle.ps1 -CsvPath ".\guests.csv"
```

**Connecting to Graph**
Requests `User.Invite.All`, `User.ReadWrite.All`, and `Directory.ReadWrite.All` — invite permission for sending invitations, read/write for looking up and removing existing guest accounts.

**CSV validation**
Confirms the CSV file exists before doing anything, same safety check as the provisioning script.

**The main loop and switch statement**
Branches on the `Action` column:

- **`invite`** — builds the invitation body (`InvitedUserEmailAddress`, `InvitedUserDisplayName`, `InviteRedirectUrl`, `SendInvitationMessage: true`) and calls `New-MgInvitation`. If your CSV row includes an `InviteMessage` column, that text becomes a custom message in the invitation email via `InvitedUserMessageInfo`. The response includes the newly created guest's object ID, which gets logged.

- **`resend`** — first confirms the guest actually exists (`Get-MgUser` filtered by email and `userType eq 'Guest'`), then calls `New-MgInvitation` again with the same email. Microsoft Graph treats this as a resend for guests who haven't yet redeemed their original invitation, rather than creating a duplicate account.

- **`checkstatus`** — looks up the guest and reads two key properties: `ExternalUserState` (`PendingAcceptance` or `Accepted`) and `ExternalUserStateChangeDateTime` (when that state last changed). This is the fastest way to audit who's actually accepted their invite versus who's still sitting pending.

- **`remove`** — looks up the guest by email, then deletes the account outright with `Remove-MgUser`. Like any user deletion, this goes into the tenant's 30-day recoverable "deleted items" state rather than disappearing permanently right away.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch per row**
Same pattern as the provisioning script — each guest is processed independently, so one failure (e.g. "guest not found" on a resend) doesn't stop the rest of the batch.

**Logging and output**
Every row's outcome — email, action, status, message, timestamp — is collected, exported to a CSV log, and printed as a table at the end.

**Disconnecting**
Session is cleanly closed with `Disconnect-MgGraph`.

## Sample CSV structure

```csv
Action,Email,DisplayName,RedirectUrl,InviteMessage
invite,partner1@vendor.com,Partner One,,Welcome to our collaboration space.
resend,partner2@vendor.com,,,
checkstatus,partner1@vendor.com,,,
remove,formerpartner@vendor.com,,,
```

## Notes
- `checkstatus` is worth running periodically on a whole partner list — it's the cleanest way to find guests stuck in `PendingAcceptance` for weeks, who are good candidates for either a `resend` or a `remove`.
- `remove` deletes the guest object entirely — if you only want to pause their access without deleting, disable the account instead (`AccountEnabled:$false`, same approach as the deprovisioning script) rather than using this action.
