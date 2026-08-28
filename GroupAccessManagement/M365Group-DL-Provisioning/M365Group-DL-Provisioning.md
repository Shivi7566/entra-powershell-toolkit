# M365Group-DL-Provisioning.ps1 — Explanation

## What this script does
Provisions **Microsoft 365 Groups** (via Microsoft Graph) and classic **Distribution Lists** (via Exchange Online PowerShell) from the same CSV — plus adding/removing members from M365 groups. These are two genuinely different object types managed through two different APIs, and this script bridges both in one workflow.

## An important distinction before the code

**Microsoft 365 Groups** (also called "Unified" groups) are fully manageable through Microsoft Graph — they're what most modern collaboration features (Teams, Planner, shared mailbox) are built on.

**Classic Distribution Lists** are an older Exchange object type. **Microsoft Graph cannot create these** — there's no Graph endpoint for it. They can only be created through **Exchange Online PowerShell** (the `ExchangeOnlineManagement` module), which is a completely separate connection and authentication flow from Microsoft Graph. This script handles both by connecting to each service only when actually needed.

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped).

**Connecting to Graph**
Requests `Group.ReadWrite.All` and `Directory.ReadWrite.All` upfront, since most rows in a typical batch will be M365 group actions.

**Lazy Exchange Online connection**
`$exchangeConnected` starts as `$false`. The script only calls `Connect-ExchangeOnline` the **first time** it hits a `createdistributionlist` row — if your CSV never has that action, this script never opens an Exchange session at all, avoiding an unnecessary second sign-in prompt. Once connected, it stays connected for the rest of the run.

**The switch statement (core logic)**

- **`createm365group`** — looks up the specified owner by UPN first (M365 groups require at least one owner at creation), then builds the group with `MailEnabled: true`, `SecurityEnabled: false`, and `GroupTypes: ["Unified"]` — this exact combination is what makes it a Microsoft 365 group rather than a plain security group (see the earlier `Bulk-Group-Maintenance.ps1` for that comparison). The owner is attached using the `"Owners@odata.bind"` syntax, which is how Graph expects you to link a relationship at creation time in a single request rather than a separate follow-up call. `Visibility` defaults to `"Private"` if not specified in the CSV.

- **`createdistributionlist`** — triggers the lazy Exchange Online connection if not already connected, then calls `New-DistributionGroup` (an Exchange Online cmdlet, not a Graph one) with a primary SMTP address built from the `MailNickname` and `DomainName` columns. If an `Owner` value is provided, it's passed as `ManagedBy`.

- **`addmember`** / **`removemember`** — same pattern as the security group script: look up the group and target user, then use `New-MgGroupMemberByRef` / `Remove-MgGroupMemberByRef`. These only apply to M365 groups here — distribution list membership uses different Exchange Online cmdlets (`Add-DistributionGroupMember`/`Remove-DistributionGroupMember`), not covered in this script.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Cleanup at the end**
The script disconnects from Exchange Online **only if it actually connected** during this run (`if ($exchangeConnected)`), then disconnects from Graph unconditionally.

## Sample CSV structure

```csv
Action,GroupName,MailNickname,DomainName,Description,Owner,Visibility,MemberUPN
createm365group,Marketing Team,marketing-team,,Collaboration space for Marketing,jdoe@contoso.com,Private,
createdistributionlist,All Staff Announcements,all-staff,contoso.com,Company-wide announcements,jdoe@contoso.com,,
addmember,Marketing Team,,,,,,,asmith@contoso.com
removemember,Marketing Team,,,,,,,formeruser@contoso.com
```

## Notes
- **`ExchangeOnlineManagement` must be installed separately** (`Install-Module ExchangeOnlineManagement`) before this script can run any `createdistributionlist` rows — it's not part of the Microsoft Graph PowerShell SDK.
- Connecting to Exchange Online will prompt for a **separate sign-in**, even if you're already connected to Microsoft Graph — they're not the same session, even against the same tenant.
- If you don't need distribution lists at all, this script still works fine using only the `createm365group`/`addmember`/`removemember` actions — the Exchange connection simply never triggers.
