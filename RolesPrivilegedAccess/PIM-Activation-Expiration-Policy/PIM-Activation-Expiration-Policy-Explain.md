# PIM-Activation-Expiration-Policy.ps1 — Explanation

## What this script does
Covers three related PIM operations that build on top of eligibility (from `PIM-Eligibility-Automation.ps1`): actually **activating** an eligible role for real, temporary use, **deactivating** it early, reading a role's **PIM policy** (activation rules like max duration and approval requirements), and scanning for currently-active assignments about to **expire**.

## An important caveat before the code — who this script is meant to be run by

Unlike every other script in this repo, the `selfactivate` and `deactivate` actions are designed to be run **by the eligible person themselves**, in their own interactive session — not by an admin running this on someone else's behalf. `Action: "SelfActivate"` requires the calling session's own recent authentication (often including a fresh MFA challenge) tied to the actual principal being activated. An admin's own Graph connection, even with full permissions, generally cannot self-activate a role for a *different* user — this is intentional, not a bug to route around.

## Step-by-step breakdown

**Parameters block**
Two independent modes, same pattern as `Direct-License-Management.ps1`:
- `-CsvPath` (optional) — for `selfactivate`, `deactivate`, and `getpolicy` rows.
- `-CheckExpiringAssignments` (optional switch) with `-ExpiringWithinHours` (default `24`) — a tenant-wide scan for active assignments about to expire, independent of any CSV.

**Connecting to Graph**
Requests `RoleAssignmentSchedule.ReadWrite.Directory` (activation/deactivation), `RoleManagementPolicy.Read.Directory` (reading policy rules), and `User.Read.All`.

**Part 1 — CSV-driven actions**

- **`selfactivate`** — sends `Action: "SelfActivate"` to the **assignment** schedule request endpoint (a different resource from the eligibility endpoint used in the previous script). `DurationHours` (default `8`) becomes an ISO 8601 duration like `PT8H`. Note: the actual duration granted is still capped by whatever the role's PIM policy allows as a maximum — requesting 24 hours against a policy that caps activation at 4 hours will be adjusted or rejected by Graph, not silently honored.

- **`deactivate`** — sends `Action: "SelfDeactivate"`, ending an active assignment before its scheduled expiration — useful once a task requiring elevated access is finished, rather than leaving the window open until natural expiry.

- **`getpolicy`** — this is a read-only diagnostic action. It finds the PIM policy assigned to a specific role via `Get-MgPolicyRoleManagementPolicyAssignment`, then retrieves that policy's individual **rules** via `Get-MgPolicyRoleManagementPolicyRule`. PIM policies are made up of several separate named rules (each controlling one aspect — max duration, MFA requirement, approval requirement, notifications) rather than one flat settings object, so this action checks for the presence of three of the most commonly relevant ones (`Expiration_EndUser_Assignment`, `AuthenticationContext_EndUser_Assignment`, `Approval_EndUser_Assignment`) and reports whether each was found, pointing you to the full `PolicyId` for deeper inspection since fully parsing every rule's internal structure is beyond a quick report.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Part 2 — Expiring assignment scan (`-CheckExpiringAssignments`)**

Runs independently of the CSV. Fetches every currently active role assignment schedule instance tenant-wide, and flags any whose `EndDateTime` falls within the next `$ExpiringWithinHours` hours — genuinely useful as a heads-up report (e.g. run daily) so people with time-bound elevated access know before it lapses mid-task, rather than being unexpectedly cut off.

## Sample CSV structure

```csv
Action,PrincipalUPN,RoleName,DurationHours,Justification
selfactivate,jdoe@contoso.com,User Administrator,4,Resetting passwords for onboarding batch
deactivate,jdoe@contoso.com,User Administrator,,
getpolicy,,Global Administrator,,
```

## Sample expiring-assignment scan

```powershell
.\PIM-Activation-Expiration-Policy.ps1 -CheckExpiringAssignments -ExpiringWithinHours 4
```

## Notes
- **`selfactivate` will most reliably work when this script is run interactively by the actual eligible person**, not as an unattended/scheduled admin job against someone else's account — plan your automation around that reality rather than trying to force cross-user activation.
- PIM policy rules are genuinely one of the more complex parts of the Graph API to work with directly — `getpolicy` here gives you a starting diagnostic, but fully reading or modifying specific rule details (like the exact configured maximum duration value) requires drilling into each rule object's own nested properties, which vary by rule type.
- Pair `-CheckExpiringAssignments` with a scheduled/recurring run (e.g. a daily task) to build a lightweight early-warning system for people about to lose active privileged access mid-task.
