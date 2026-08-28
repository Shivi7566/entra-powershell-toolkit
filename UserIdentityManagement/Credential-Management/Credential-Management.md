# Credential-Management.ps1 — Explanation

## What this script does
Covers three related credential operations from one CSV: resetting a user's password, issuing a Temporary Access Pass (TAP) for passwordless/first-time sign-in scenarios, listing a user's registered authentication methods, and removing a specific method (phone or email).

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped). Run it like:
```powershell
.\Credential-Management.ps1 -CsvPath ".\credential-requests.csv"
```

**Connecting to Graph**
Requests `UserAuthenticationMethod.ReadWrite.All` (covers TAP, phone, and email method management) plus `User.ReadWrite.All` (covers direct password resets).

**Looking up the user once per row**
Unlike the earlier scripts, the user lookup (`Get-MgUser -Filter "userPrincipalName eq '$upn'"`) happens **before** the switch statement here, since every single action in this script needs the user object first — no point repeating that lookup four separate times inside each branch.

**The switch statement (core logic)**

- **`resetpassword`** — if your CSV row includes a `NewPassword` column, that exact value is used; otherwise the script generates a random one using `[System.Guid]::NewGuid()`. Either way, `ForceChangePasswordNextSignIn` is set to `true`, so the user must set their own password the next time they sign in. The generated (or provided) password is written into the log message — **this means your log file contains plaintext passwords for any row that used a randomly generated one**, so treat that log file as sensitive and delete/secure it after use.

- **`issuetap`** — a Temporary Access Pass is a time-limited passcode used instead of a regular password, commonly for onboarding new users before they've registered MFA, or for helping a user get back in when they've lost all their authentication methods. `TapLifetimeMinutes` (default 60) controls how long it's valid, and `TapIsUsableOnce` (default `true`) controls whether it can only be used for one sign-in or reused until it expires. **The actual TAP code is only returned once**, at creation time — it's written to the log message, so again, protect that log file.

- **`listmethods`** — retrieves everything registered against the user's account (phone, email, Authenticator app, FIDO2 key, etc.) via `Get-MgUserAuthenticationMethod`, then extracts just the method type name from each result's OData type metadata for a clean, readable summary — useful before deciding whether someone actually needs a TAP or a method removal.

- **`removemethod`** — this action has its own nested switch on the `MethodType` column, supporting `phone` or `email`. It fetches all methods of that type on the user and removes each one in a loop (a user can have more than one registered phone number, for instance). Extend this nested switch with more `case`s (e.g. `fido2`, `microsoftAuthenticator`) if you need to support removing other method types later.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch, logging, and disconnect**
Same reliable pattern as the previous scripts — errors on one row don't stop the batch, everything gets logged and printed, and the session disconnects cleanly at the end.

## Sample CSV structure

```csv
Action,UserPrincipalName,NewPassword,TapLifetimeMinutes,TapIsUsableOnce,MethodType
resetpassword,jdoe@contoso.com,,,,
resetpassword,asmith@contoso.com,SpecificP@ss1!,,,
issuetap,newhire@contoso.com,,60,true,
issuetap,lockedout@contoso.com,,15,false,
listmethods,someuser@contoso.com,,,,
removemethod,formerphone@contoso.com,,,,phone
```

## Notes
- **Treat the log file from this script as sensitive** — it contains plaintext passwords and TAP codes wherever those actions ran. Store it somewhere access-controlled and delete it once you've distributed the credentials to the right people through a secure channel (not email in plaintext).
- `issuetap` is the modern, recommended way to get a user signed in for the first time or recovered from lockout **without** you as the admin ever knowing or setting their actual password — prefer it over `resetpassword` when the scenario allows it.
- Before removing a user's only registered authentication method, run `listmethods` first — removing someone's last remaining method can lock them out of self-service recovery entirely.
