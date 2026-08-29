# PIM-Eligibility-Automation.ps1 — Explanation

## What this script does
Grants and removes **PIM eligibility** — the "you can activate this role when you need it, but don't hold it standing" model — for users in bulk, plus reports on both what someone is currently eligible for and what they currently have actively activated. This is a fundamentally different access model from the previous script's permanent role assignments.

## The key concept: eligible vs. active

This distinction matters throughout the whole script:
- **Eligible** — the user *can* activate this role (often requiring MFA and/or approval), but doesn't have its permissions right now. This is what `makeeligible` grants.
- **Active** — the role's permissions are currently live and usable, either because someone activated an eligible assignment, or because an admin directly assigned time-bound active access. `listactive` reports on this separate state.

Making someone eligible does **not** give them the role's access immediately — it just makes activation possible.

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped).

**Connecting to Graph**
Requests `RoleEligibilitySchedule.ReadWrite.Directory` (specific to PIM eligibility, distinct from the standing-assignment permission used in the previous script), `RoleManagement.ReadWrite.Directory`, and `User.Read.All`.

**The switch statement (core logic)**

- **`makeeligible`** — resolves the user and role, then builds a request with `Action: "AdminAssign"` sent to the **eligibility** schedule request endpoint (not the assignment endpoint — a completely different resource in the API). The `DurationDays` CSV column controls the `Expiration` object: if provided, it builds an ISO 8601 duration string (`P{days}D`, e.g. `P90D` for 90 days) with `Type: "AfterDuration"`; if left blank, eligibility is granted with `Type: "NoExpiration"` — permanent eligibility (though still requiring activation each time to actually use it). A `Justification` is required by PIM's audit model — the script supplies a default if the CSV row doesn't specify one.

- **`removeeligibility`** — same resolution steps, but sends `Action: "AdminRemove"` instead — revoking the ability to activate that role at all going forward.

- **`listeligible`** — queries `roleEligibilityScheduleInstances` filtered to the specific user, expanding the role definition so real role names show up in the result rather than raw IDs. This answers "what roles could this person activate right now if they needed to?"

- **`listactive`** — queries the separate `roleAssignmentScheduleInstances` resource, answering the different question: "what roles does this person currently have live, right now, whether through self-activation or a direct time-bound admin assignment?" This is useful for a real-time privileged access snapshot — who actually holds elevated access at this exact moment, as opposed to who's merely allowed to request it.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch, logging, and disconnect**
Same reliable pattern as every other script in this repo.

## Sample CSV structure

```csv
Action,PrincipalUPN,RoleName,DurationDays,Justification
makeeligible,jdoe@contoso.com,Global Administrator,90,Approved for Q3 infrastructure project
makeeligible,asmith@contoso.com,User Administrator,,Standing eligibility per team charter
listeligible,jdoe@contoso.com,,,
listactive,jdoe@contoso.com,,,
removeeligibility,asmith@contoso.com,User Administrator,,Role no longer needed after project completion
```

## Notes
- **This script cannot self-activate a role on someone's behalf** — activation (`SelfActivate`) has to come from the eligible user's own signed-in session, and typically requires a fresh MFA challenge in that same session. An admin script running with its own credentials can't satisfy that requirement for someone else — this is by design, not a limitation worth working around.
- Setting eligibility with `NoExpiration` for high-privilege roles (like Global Administrator) somewhat defeats the "just-in-time access" purpose of PIM — a time-bound `DurationDays` value, paired with a periodic access review (see the Graph API toolkit's `IdentityGovernance.md`), is generally the better practice for genuinely sensitive roles.
- Every PIM eligibility change made through this script is still subject to whatever **PIM policy** (approval requirements, maximum duration limits) is configured for that specific role — if a request seems to silently not take effect as expected, check the role's PIM policy settings rather than assuming the script failed.
