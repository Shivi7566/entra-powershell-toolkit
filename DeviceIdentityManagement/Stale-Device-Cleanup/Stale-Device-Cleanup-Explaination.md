# Stale-Device-Cleanup.ps1 — Explanation

## What this script does
Finds devices that haven't been used recently (or have never signed in since being created), and — only when explicitly told to — either disables or deletes them. This is the action-taking counterpart to `Device-Auditing.ps1`, which only reports; this script is designed to be safe-by-default and only makes real changes when you deliberately opt in.

## Step-by-step breakdown

**Parameters block**
- `-StaleThresholdDays` (default `90`) — same concept as the auditing script.
- `-CleanupAction` (`"Disable"` or `"Delete"`, default `"Disable"`) — using `[ValidateSet(...)]` so PowerShell itself rejects any other value immediately, rather than letting a typo silently do nothing.
- `-PerformCleanup` (switch, **defaults to off**) — this is the safety gate. Without it, the script only **reports** what it would do; nothing is actually changed.
- `-ExcludeDeviceIds` (optional array) — an explicit escape hatch for known exceptions (e.g. a conference room device that's rarely signed into but shouldn't be touched).
- `-LogPath` (auto-timestamped).

**Connecting to Graph**
Requests `Device.ReadWrite.All` and `Directory.ReadWrite.All` — write permissions are requested even in report-only mode, since the same script handles both, but nothing is actually written unless `-PerformCleanup` is present.

**Identifying stale candidates**
This uses **two separate staleness conditions**, both handled explicitly rather than treating "no recent sign-in" as one blanket rule:
1. **`isStaleBySignIn`** — the device has signed in before, but not since the cutoff date.
2. **`isStaleByNeverSignedIn`** — the device has **never** signed in at all (`ApproximateLastSignInDateTime` is null), but was **created** long enough ago that "never signed in" is itself suspicious rather than just "newly provisioned and not yet used." This distinction matters — a device registered yesterday with no sign-in yet is completely normal and shouldn't be flagged; a device registered 6 months ago that's never once signed in almost certainly should be.

Devices in `-ExcludeDeviceIds` are skipped entirely before either check runs.

**The report-only branch**
If `-PerformCleanup` wasn't passed, every stale candidate gets logged with status `"ReportOnly"` and a message describing exactly what *would* happen and why — no Graph write calls are made at all in this branch.

**The actual cleanup branch**
Only reached if `-PerformCleanup` was explicitly passed:
- **`Disable`** (the default action) — sets `AccountEnabled:$false` on the device, which blocks it from being used for authentication without destroying the object. Reversible by simply re-enabling it later — a good first step for anything you're not 100% certain about.
- **`Delete`** — calls `Remove-MgDevice`, which — like users and groups elsewhere in this repo — moves the device into a 30-day recoverable "deleted items" state rather than permanently destroying it immediately.

Each action is wrapped in try/catch, same reliable pattern as every other script in this repo — one device's failure doesn't stop the batch.

**Final reminder**
If the run was report-only and candidates were found, the script prints an explicit reminder of exactly what flag to add to actually perform the cleanup — removing any ambiguity about what running it again with different parameters will do.

## Sample usage

**Report only (default, safe to run anytime):**
```powershell
.\Stale-Device-Cleanup.ps1 -StaleThresholdDays 90
```

**Actually disable stale devices:**
```powershell
.\Stale-Device-Cleanup.ps1 -StaleThresholdDays 90 -PerformCleanup
```

**Actually delete, with specific exclusions:**
```powershell
.\Stale-Device-Cleanup.ps1 -StaleThresholdDays 90 -CleanupAction Delete -PerformCleanup -ExcludeDeviceIds "aaaa-1111","bbbb-2222"
```

## Notes
- **Always run in report-only mode first**, review the output, and only add `-PerformCleanup` once you're confident in the list — same discipline established by `Group-Audit-Cleanup.ps1` earlier in this repo.
- **`Disable` is the recommended first move over `Delete`** for most cleanup cycles — it immediately stops the device from being usable while keeping the object (and its history/associations) intact, giving you a safety window before committing to deletion in a later, separate pass.
- Cross-reference this script's candidates against `Device-Auditing.ps1`'s ownerless devices report — a device that's both stale **and** has no registered owner is a particularly strong cleanup candidate, since there's no one who would even notice or object to its removal.
