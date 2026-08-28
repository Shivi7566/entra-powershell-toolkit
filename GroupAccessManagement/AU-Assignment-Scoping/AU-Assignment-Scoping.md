# AU-Assignment-Scoping.ps1 — Explanation

## What this script does
Manages Administrative Unit (AU) membership — adding and removing users or groups — and **scoped role assignments**, which delegate admin permissions limited to just that AU rather than the whole tenant (e.g. a regional "User Administrator" who can only manage users within their own AU, not globally).

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped).

**Connecting to Graph**
Requests `AdministrativeUnit.ReadWrite.All` (AU membership) and `RoleManagement.ReadWrite.Directory` (required specifically for assigning scoped roles — a broader permission than AU membership alone needs).

**Looking up the AU once per row**
Like the credential management script, the AU lookup happens **before** the switch statement, since every action in this script operates against a specific administrative unit.

**The switch statement (core logic)**

- **`addmember`** — reads a `MemberType` column (`User` or `Group`) to know which kind of object to look up, resolves it to its object ID, then adds it to the AU using `New-MgDirectoryAdministrativeUnitMemberByRef`. Administrative Units can contain both individual users and entire groups, which is why this branching matters — the lookup logic differs depending on which type you're adding.

- **`removemember`** — same type-aware lookup, but calls `Remove-MgDirectoryAdministrativeUnitMemberByRef` to take the object back out of the AU.

- **`assignscopedrole`** — this is the delegation piece. First it resolves the `RoleName` (e.g. `"User Administrator"`, `"Helpdesk Administrator"`) to its role **template** ID via `Get-MgDirectoryRoleTemplate` — note this uses the role template, not an already-activated directory role, since scoped role assignments reference the template directly. Then it resolves the target user, and calls `New-MgDirectoryAdministrativeUnitScopedRoleMember` with both IDs. The result: that user now holds that admin role, but their authority is **scoped to only this AU** — they cannot use that role's permissions against users, groups, or devices outside it.

- **`removescopedrole`** — this one requires an extra lookup step: scoped role assignments have their own unique ID (different from the user's or role's ID), so the script first retrieves **all** scoped role members on the AU via `Get-MgDirectoryAdministrativeUnitScopedRoleMember`, then filters that list to find the one entry matching the target user's ID, before calling `Remove-MgDirectoryAdministrativeUnitScopedRoleMember` with that assignment's own ID. If no matching assignment is found, it throws a clear error rather than silently doing nothing.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch, logging, and disconnect**
Same reliable pattern as every other script in this repo.

## Sample CSV structure

```csv
Action,AUName,MemberType,MemberIdentifier,RoleName,PrincipalUPN
addmember,West Region,User,jdoe@contoso.com,,
addmember,West Region,Group,West Region Sales Team,,
removemember,West Region,User,formeremployee@contoso.com,,
assignscopedrole,West Region,,,User Administrator,regionaladmin@contoso.com
removescopedrole,West Region,,,,formeradmin@contoso.com
```

## Notes
- **Scoped role assignments are the actual point of Administrative Units** in most real-world designs — the ability to say "this person can reset passwords / manage users, but *only* for this region/department/subsidiary" without giving them tenant-wide power. If you're not using `assignscopedrole` at all, the AU is mostly just an organizational container without its delegation benefit.
- The role name passed to `assignscopedrole` must **exactly match** a built-in role template's display name — a small typo (e.g. "User Admin" instead of "User Administrator") will cause the lookup to fail cleanly rather than assign the wrong role, since `Get-MgDirectoryRoleTemplate` won't find a match.
- Combine this script with `RolesPrivilegedAccess` folder's upcoming role assignment scripts if you also need to check whether a role is available for AU-scoping at all — not every built-in role supports being scoped to an AU.
