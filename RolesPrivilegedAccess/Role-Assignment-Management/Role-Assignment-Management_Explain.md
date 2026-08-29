# Role-Assignment-Management.ps1 — Explanation

## What this script does
Assigns and removes both **built-in** Entra directory roles (like "User Administrator") and **custom** roles you define yourself, lists a user's current role assignments, and creates new custom role definitions — all using the modern unified RBAC API rather than the older, more limited legacy directory roles model.

## Why this uses the unified RBAC API

As covered in the Graph API toolkit's `RolesAndAdministrators.md`, Microsoft recommends `/roleManagement/directory/...` endpoints over the legacy `/directoryRoles` API for new work — it supports custom roles, AU-scoped assignments, and PIM in one consistent model. Every cmdlet in this script (`*-MgRoleManagementDirectory*`) reflects that modern API.

## Step-by-step breakdown

**Parameters block**
Takes `-CsvPath` (required) and `-LogPath` (optional, auto-timestamped).

**Connecting to Graph**
Requests `RoleManagement.ReadWrite.Directory` and `User.Read.All`.

**The switch statement (core logic)**

- **`assignrole`** — resolves the target user and looks up the role definition by its exact display name (works for both built-in roles like "Helpdesk Administrator" and any custom roles you've already created — they live in the same `roleDefinitions` collection). The `DirectoryScopeId` column controls scope: leave it blank for a tenant-wide assignment (defaults to `"/"`), or provide an Administrative Unit's ID to scope the role to just that AU — the same delegation pattern covered in `AU-Assignment-Scoping.ps1`, but driven from this script instead.

- **`removerole`** — this needs an extra step compared to assignment: role assignments have their own unique ID, separate from the user's ID or the role's ID, so the script first **finds** the specific assignment by filtering on both `principalId` and `roleDefinitionId` together, then removes it by that assignment's own ID. Throws a clear error if no matching assignment exists, rather than silently doing nothing.

- **`listroles`** — retrieves all role assignments for a given user, using `-ExpandProperty "roleDefinition"` so the response includes each role's actual display name inline, rather than just a raw role definition ID you'd have to look up separately. Useful before making changes, or for a quick access review on a specific person.

- **`createcustomrole`** — builds a brand-new custom role definition. The `AllowedResourceActions` CSV column holds a comma-separated list of specific permission strings (e.g. `microsoft.directory/users/create`, `microsoft.directory/users/password/update`) that define exactly what the role can do — custom roles in Entra ID are built from these granular action strings rather than inheriting from a built-in role. `IsEnabled: true` makes the role immediately assignable once created.

- **`default`** — catches unrecognized Action values and marks the row "Skipped".

**Try/catch, logging, and disconnect**
Same reliable pattern as every other script in this repo.

## Sample CSV structure

```csv
Action,PrincipalUPN,RoleName,DirectoryScopeId,RoleDescription,AllowedResourceActions
assignrole,jdoe@contoso.com,Helpdesk Administrator,,,
assignrole,asmith@contoso.com,User Administrator,/administrativeUnits/xxxx-xxxx,,
listroles,jdoe@contoso.com,,,,
removerole,jdoe@contoso.com,Helpdesk Administrator,,,
createcustomrole,,Password Reset Only,,Can only reset user passwords,"microsoft.directory/users/password/update"
```

## Notes
- **`createcustomrole` requires an Entra ID P1 or P2 license** — custom roles aren't available on the free tier. If this action fails unexpectedly, license level is worth checking first.
- Finding the exact `AllowedResourceActions` strings you need takes some research — Microsoft Learn maintains a full reference of available resource actions. Start narrow (grant only what's genuinely needed) rather than copying a broad built-in role's full permission set into a "custom" role that isn't actually more restrictive.
- This script handles **permanent, standing** role assignments only. For time-bound, approval-gated access (PIM eligible assignments, self-activation), see the next script in this folder — that's a related but distinct workflow built on different endpoints.
